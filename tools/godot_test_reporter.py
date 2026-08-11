"""Stable JSON and GitHub Job Summary reports for Godot test runs."""

from dataclasses import asdict
import json
import os
from pathlib import Path

from tools.godot_test_evaluator import SceneResult, import_result_failed


def write_json_report(
    report_path: Path,
    *,
    suite: str,
    import_results: list[dict],
    scene_results: list[SceneResult],
    total_duration_seconds: float,
) -> None:
    report_path.parent.mkdir(parents=True, exist_ok=True)
    imports_passed = bool(import_results) and all(
        not import_result_failed(result) for result in import_results
    )
    tests_passed = bool(scene_results) and all(
        result.status == "passed" for result in scene_results
    )
    payload = {
        "suite": suite,
        "status": "passed" if imports_passed and tests_passed else "failed",
        "total_duration_seconds": round(total_duration_seconds, 3),
        "imports": import_results,
        "tests": [asdict(result) for result in scene_results],
        "summary": {
            "total": len(scene_results),
            "passed": sum(
                result.status == "passed" for result in scene_results
            ),
            "failed": sum(
                result.status == "failed" for result in scene_results
            ),
        },
    }
    report_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def append_github_summary(
    suite: str,
    import_results: list[dict],
    scene_results: list[SceneResult],
    total_duration_seconds: float,
) -> None:
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not summary_path:
        return

    failed = sum(result.status == "failed" for result in scene_results)
    lines = [
        f"### Godot test suite: `{suite}`",
        "",
        "#### Import phases",
        "",
        "| Phase | Status | Duration | Peak memory |",
        "| --- | --- | ---: | ---: |",
    ]
    for result in import_results:
        status = "failed" if import_result_failed(result) else "passed"
        lines.append(
            f"| `{result.get('phase', 'unknown')}` | {status} | "
            f"{float(result.get('duration_seconds', 0.0)):.3f}s | "
            f"{float(result.get('peak_memory_mb', 0.0)):.1f} MiB |"
        )
    lines.extend([
        "",
        "#### Test scenes",
        "",
        "| Scene | Mode | Status | Duration | Peak memory |",
        "| --- | --- | --- | ---: | ---: |",
    ])
    for result in scene_results:
        lines.append(
            f"| `{result.scene}` | {result.mode} | {result.status} | "
            f"{result.duration_seconds:.3f}s | {result.peak_memory_mb:.1f} MiB |"
        )
    lines.extend([
        "",
        f"Total: {len(scene_results) - failed} passed, {failed} failed, "
        f"{total_duration_seconds:.3f}s.",
        "",
    ])
    with Path(summary_path).open("a", encoding="utf-8") as summary_file:
        summary_file.write("\n".join(lines))
