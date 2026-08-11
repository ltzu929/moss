"""Strict log and terminal-marker evaluation for Godot test processes."""

from dataclasses import dataclass, field
import re

from tools.godot_process import CommandResult
from tools.godot_test_catalog import TestSpec


@dataclass
class SceneResult:
    scene: str
    suite: str
    mode: str
    status: str
    exit_code: int
    duration_seconds: float
    timed_out: bool
    memory_limit_exceeded: bool = False
    peak_memory_mb: float = 0.0
    missing_markers: list[str] = field(default_factory=list)
    unexpected_errors: list[str] = field(default_factory=list)
    failure_reasons: list[str] = field(default_factory=list)


ANSI_ESCAPE_RE = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
KNOWN_GODOT_AI_ERROR_FRAGMENTS = (
    "Attempt to open script 'res://addons/godot_ai/runtime/game_helper.gd' "
    "resulted in error 'File not found'",
    "Failed loading resource: res://addons/godot_ai/runtime/game_helper.gd",
    "Failed to create an autoload, can't load from UID or path: "
    "res://addons/godot_ai/runtime/game_helper.gd",
    "Failed to instantiate an autoload, can't load from path: "
    "res://addons/godot_ai/runtime/game_helper.gd",
)


def _normalized_log_line(line: str) -> str:
    return ANSI_ESCAPE_RE.sub("", line).strip()


def is_known_godot_ai_error(line: str) -> bool:
    return any(fragment in line for fragment in KNOWN_GODOT_AI_ERROR_FRAGMENTS)


def find_unexpected_errors(
    output: str,
    *,
    allow_missing_godot_ai: bool = False,
) -> list[str]:
    errors: list[str] = []
    for raw_line in output.splitlines():
        line = _normalized_log_line(raw_line)
        if not line:
            continue

        is_failure_line = (
            "ERROR:" in line
            or "SCRIPT ERROR:" in line
            or "Parse Error:" in line
            or "[FAIL]" in line
            or "[ERROR]" in line
            or "[FATAL]" in line
        )
        if not is_failure_line:
            continue
        if allow_missing_godot_ai and is_known_godot_ai_error(line):
            continue
        errors.append(line)
    return errors


def evaluate_scene_result(
    spec: TestSpec,
    command_result: CommandResult,
) -> SceneResult:
    missing_markers = [
        marker
        for marker in spec.required_markers
        if marker not in command_result.output
    ]
    unexpected_errors = find_unexpected_errors(
        command_result.output,
        allow_missing_godot_ai=True,
    )
    failure_reasons: list[str] = []
    if command_result.timed_out:
        failure_reasons.append("timeout")
    if command_result.memory_limit_exceeded:
        failure_reasons.append("memory_limit_exceeded")
    if command_result.exit_code != 0:
        failure_reasons.append(f"exit_code={command_result.exit_code}")
    if missing_markers:
        failure_reasons.append("missing_terminal_marker")
    if unexpected_errors:
        failure_reasons.append("unexpected_error_log")

    return SceneResult(
        scene=spec.scene,
        suite=spec.suite,
        mode=spec.mode,
        status="passed" if not failure_reasons else "failed",
        exit_code=command_result.exit_code,
        duration_seconds=round(command_result.duration_seconds, 3),
        timed_out=command_result.timed_out,
        memory_limit_exceeded=command_result.memory_limit_exceeded,
        peak_memory_mb=round(
            command_result.peak_memory_bytes / (1024 * 1024),
            1,
        ),
        missing_markers=missing_markers,
        unexpected_errors=unexpected_errors,
        failure_reasons=failure_reasons,
    )


def build_import_result(
    phase: str,
    command_result: CommandResult,
    *,
    unexpected_errors: list[str] | None = None,
) -> dict:
    """Project a command result into the frozen import-report schema."""
    return {
        "phase": phase,
        "exit_code": command_result.exit_code,
        "duration_seconds": round(command_result.duration_seconds, 3),
        "timed_out": command_result.timed_out,
        "memory_limit_exceeded": command_result.memory_limit_exceeded,
        "peak_memory_mb": round(
            command_result.peak_memory_bytes / (1024 * 1024),
            1,
        ),
        "unexpected_errors": unexpected_errors or [],
    }


def import_result_failed(result: dict) -> bool:
    return (
        result.get("exit_code", 1) != 0
        or result.get("timed_out", False)
        or result.get("memory_limit_exceeded", False)
        or bool(result.get("unexpected_errors", []))
    )
