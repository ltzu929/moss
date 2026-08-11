"""Godot child-process execution and cross-platform memory sampling."""

import ctypes
from dataclasses import dataclass
import os
import platform
from pathlib import Path
import queue
import shutil
import subprocess
import sys
import threading
import time
from typing import Sequence


DEFAULT_MEMORY_LIMIT_MB = 4096


@dataclass
class CommandResult:
    exit_code: int
    output: str
    duration_seconds: float
    timed_out: bool = False
    memory_limit_exceeded: bool = False
    peak_memory_bytes: int = 0


def find_godot(godot_arg: str | None) -> str | None:
    if godot_arg:
        return godot_arg

    godot_bin = os.environ.get("GODOT_BIN")
    if godot_bin:
        return godot_bin

    for command_name in ("godot", "godot4"):
        if shutil.which(command_name):
            return command_name

    return None


def _stream_reader(
    stream,
    output_queue: queue.Queue[str | None],
) -> None:
    try:
        for line in iter(stream.readline, ""):
            output_queue.put(line)
    finally:
        stream.close()
        output_queue.put(None)


class _WindowsProcessMemoryCountersEx(ctypes.Structure):
    _fields_ = [
        ("cb", ctypes.c_ulong),
        ("page_fault_count", ctypes.c_ulong),
        ("peak_working_set_size", ctypes.c_size_t),
        ("working_set_size", ctypes.c_size_t),
        ("quota_peak_paged_pool_usage", ctypes.c_size_t),
        ("quota_paged_pool_usage", ctypes.c_size_t),
        ("quota_peak_non_paged_pool_usage", ctypes.c_size_t),
        ("quota_non_paged_pool_usage", ctypes.c_size_t),
        ("pagefile_usage", ctypes.c_size_t),
        ("peak_pagefile_usage", ctypes.c_size_t),
        ("private_usage", ctypes.c_size_t),
    ]


def _read_process_memory_bytes(process: subprocess.Popen[str]) -> int:
    if process.poll() is not None:
        return 0

    system_name = platform.system()
    if system_name == "Windows":
        process_handle = getattr(process, "_handle", None)
        if process_handle is None:
            return 0
        counters = _WindowsProcessMemoryCountersEx()
        counters.cb = ctypes.sizeof(counters)
        get_process_memory_info = ctypes.windll.psapi.GetProcessMemoryInfo
        succeeded = get_process_memory_info(
            ctypes.c_void_p(int(process_handle)),
            ctypes.byref(counters),
            counters.cb,
        )
        return int(counters.private_usage) if succeeded else 0

    if system_name == "Linux":
        try:
            status = Path(f"/proc/{process.pid}/status").read_text(
                encoding="utf-8"
            )
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            return 0
        for line in status.splitlines():
            if line.startswith("VmRSS:"):
                return int(line.split()[1]) * 1024

    return 0


def run_command(
    command: Sequence[str],
    project_root: Path,
    timeout_seconds: int | float,
    *,
    echo: bool = True,
    memory_limit_mb: int = DEFAULT_MEMORY_LIMIT_MB,
) -> CommandResult:
    """Run one Godot command while preserving output, timeout, and memory gates."""
    started = time.monotonic()
    try:
        process = subprocess.Popen(
            list(command),
            cwd=project_root,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
        )
    except FileNotFoundError:
        message = f"Godot executable not found: {command[0]}"
        if echo:
            print(message, file=sys.stderr, flush=True)
        return CommandResult(127, message + "\n", 0.0)

    assert process.stdout is not None
    output_queue: queue.Queue[str | None] = queue.Queue()
    reader = threading.Thread(
        target=_stream_reader,
        args=(process.stdout, output_queue),
        daemon=True,
    )
    reader.start()

    output_lines: list[str] = []
    stream_finished = False
    timed_out = False
    memory_limit_exceeded = False
    peak_memory_bytes = 0
    memory_limit_bytes = memory_limit_mb * 1024 * 1024
    while process.poll() is None or not stream_finished:
        elapsed = time.monotonic() - started
        if process.poll() is None and not memory_limit_exceeded:
            memory_bytes = _read_process_memory_bytes(process)
            peak_memory_bytes = max(peak_memory_bytes, memory_bytes)
            if (
                memory_limit_bytes > 0
                and memory_bytes > memory_limit_bytes
            ):
                memory_limit_exceeded = True
                process.kill()
        if (
            process.poll() is None
            and not memory_limit_exceeded
            and elapsed > timeout_seconds
        ):
            timed_out = True
            process.kill()

        try:
            line = output_queue.get(timeout=0.05)
        except queue.Empty:
            continue

        if line is None:
            stream_finished = True
            continue

        output_lines.append(line)
        if echo:
            print(line, end="", flush=True)

    reader.join(timeout=1.0)
    exit_code = process.wait()
    duration = time.monotonic() - started
    if timed_out:
        exit_code = 124
        timeout_message = (
            f"Command timed out after {timeout_seconds}s: {' '.join(command)}"
        )
        output_lines.append(timeout_message + "\n")
        if echo:
            print(timeout_message, file=sys.stderr, flush=True)
    elif memory_limit_exceeded:
        exit_code = 125
        peak_memory_mb = peak_memory_bytes / (1024 * 1024)
        memory_message = (
            f"Command exceeded memory limit of {memory_limit_mb} MiB "
            f"(peak {peak_memory_mb:.1f} MiB): {' '.join(command)}"
        )
        output_lines.append(memory_message + "\n")
        if echo:
            print(memory_message, file=sys.stderr, flush=True)

    return CommandResult(
        exit_code=exit_code,
        output="".join(output_lines),
        duration_seconds=duration,
        timed_out=timed_out,
        memory_limit_exceeded=memory_limit_exceeded,
        peak_memory_bytes=peak_memory_bytes,
    )
