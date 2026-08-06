#!/usr/bin/env python3
"""审计 MOSS 事件、选项和区域的稳定内容身份。

该工具做两件事：

* 从真实 ``.tres`` 资源生成或比对身份映射基线；
* 扫描 ``.gd``、``.tres`` 和 ``.tscn`` 中的身份相关字段，输出五类用途清单，
  为运行时身份替换和后续解耦批次提供可复核的事实基线。

工具只使用 Python 标准库，不修改生产资源。只有显式传入
``--write-baseline`` 时才会写入指定的基线文件。
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path
from typing import Any, Optional


IDENTITY_FIELDS: tuple[str, ...] = (
    "event_id",
    "option_id",
    "region_id",
    "event_title",
    "event_description",
    "event_region",
    "region_name",
    "display_name",
    "button_text",
    "triggered_events",
    "required_event_state",
    "required_decision_tag_key",
    "required_decision_tag_value",
    "event_state_key",
    "condition",
    "branch",
)

REGION_ID_BY_NAME: dict[str, str] = {
    "亚洲": "asia",
    "北美": "north_america",
    "欧洲": "europe",
    "非洲": "africa",
    "南美": "south_america",
    "大洋洲": "oceania",
}

USAGE_CATEGORIES: tuple[str, ...] = (
    "display_only",
    "runtime_identity",
    "condition",
    "log_or_test",
    "data_reference",
)

_RESOURCE_BLOCK_RE = re.compile(
    r"(?ms)^\[sub_resource type=\"Resource\" id=\"[^\"]+\"\]\n"
    r"(.*?)(?=^\[sub_resource|^\[resource\]|\Z)"
)
_FUNCTION_DECLARATION_RE = re.compile(
    r"^\s*func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\("
)
RUNTIME_IDENTITY_FUNCTIONS: frozenset[str] = frozenset(
    {
        "_get_event_trigger_key",
        "_get_event_option",
        "_find_sector_by_id",
    }
)


def _read_field(text: str, field: str) -> Optional[str]:
    match = re.search(
        rf"(?m)^{re.escape(field)}\s*=\s*\"([^\"]*)\"\s*$", text
    )
    return match.group(1) if match else None


def _parse_options(text: str) -> list[dict[str, Any]]:
    options: list[dict[str, Any]] = []
    for match in _RESOURCE_BLOCK_RE.finditer(text):
        body = match.group(1)
        button_text = _read_field(body, "button_text")
        if button_text is None:
            continue
        options.append(
            {
                "index": len(options),
                "option_id": _read_field(body, "option_id"),
                "button_text": button_text,
                "decision_tag_key": _read_field(body, "decision_tag_key") or "",
                "decision_tag_value": _read_field(body, "decision_tag_value") or "",
            }
        )
    return options


def _collect_decision_tag_writes(
    events: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    """收集所有选项实际写入的完整决策标签对。"""
    writes: list[dict[str, Any]] = []
    for event in events:
        for index, option in enumerate(event.get("options", [])):
            key = str(option.get("decision_tag_key") or "")
            value = str(option.get("decision_tag_value") or "")
            if not key and not value:
                continue
            writes.append(
                {
                    "path": event.get("path", ""),
                    "event_id": event.get("event_id", ""),
                    "option_index": option.get("index", index),
                    "option_id": option.get("option_id", ""),
                    "decision_tag_key": key,
                    "decision_tag_value": value,
                }
            )
    return writes


def _resource_path(root: Path, path: Path) -> str:
    return "res://" + path.relative_to(root).as_posix()


def collect_mapping(root: Path) -> dict[str, Any]:
    """从真实事件和区域资源构造可序列化身份映射。"""
    events: list[dict[str, Any]] = []
    event_dir = root / "data" / "events"
    for path in sorted(event_dir.glob("*.tres")):
        text = path.read_text(encoding="utf-8")
        events.append(
            {
                "path": _resource_path(root, path),
                "event_id": _read_field(text, "event_id"),
                "event_title": _read_field(text, "event_title"),
                "event_region": _read_field(text, "event_region"),
                "required_decision_tag_key": _read_field(
                    text, "required_decision_tag_key"
                )
                or "",
                "required_decision_tag_value": _read_field(
                    text, "required_decision_tag_value"
                )
                or "",
                "options": _parse_options(text),
            }
        )

    sectors: list[dict[str, Any]] = []
    for path in sorted((root / "data").glob("sector_*.tres")):
        text = path.read_text(encoding="utf-8")
        sectors.append(
            {
                "path": _resource_path(root, path),
                "region_id": _read_field(text, "region_id"),
                "region_name": _read_field(text, "region_name"),
            }
        )

    return {
        "schema_version": 1,
        "events": events,
        "sectors": sectors,
        "decision_tag_writes": _collect_decision_tag_writes(events),
    }


def validate_mapping(mapping: dict[str, Any]) -> list[str]:
    """检查身份映射中的缺失、重复、错配和条件分支引用。"""
    errors: list[str] = []
    sector_names: set[str] = set()
    sector_ids: set[str] = set()

    events = mapping.get("events", [])
    decision_tag_pairs: set[tuple[str, str]] = set()
    decision_tag_keys: set[str] = set()
    for event in events:
        event_path = str(event.get("path", ""))
        for index, option in enumerate(event.get("options", []), start=1):
            tag_key = str(option.get("decision_tag_key") or "")
            tag_value = str(option.get("decision_tag_value") or "")
            if bool(tag_key) != bool(tag_value):
                errors.append(
                    "选项决策标签必须同时提供键和值：%s #%d -> %s/%s"
                    % (event_path, index, tag_key, tag_value)
                )
            if tag_key and tag_value:
                decision_tag_pairs.add((tag_key, tag_value))
                decision_tag_keys.add(tag_key)

    for sector in mapping.get("sectors", []):
        path = str(sector.get("path", ""))
        region_name = sector.get("region_name") or ""
        region_id = sector.get("region_id") or ""
        if not region_name:
            errors.append(f"区域名称缺失：{path}")
        if not region_id:
            errors.append(f"区域 ID 缺失：{path}")
        expected_region_id = REGION_ID_BY_NAME.get(region_name)
        if expected_region_id is None:
            errors.append(f"区域名称不在固定映射中：{path} -> {region_name}")
        elif region_id != expected_region_id:
            errors.append(
                f"区域 ID 错配：{path} -> {region_id}，期望 {expected_region_id}"
            )
        if region_name in sector_names:
            errors.append(f"区域名称重复：{region_name}")
        if region_id and region_id in sector_ids:
            errors.append(f"区域 ID 重复：{region_id}")
        sector_names.add(region_name)
        if region_id:
            sector_ids.add(region_id)

    event_ids: set[str] = set()
    for event in events:
        path = str(event.get("path", ""))
        event_id = event.get("event_id") or ""
        event_title = event.get("event_title") or ""
        event_region = event.get("event_region") or ""
        expected_event_id = Path(path.replace("res://", "", 1)).stem
        if not event_id:
            errors.append(f"事件 ID 缺失：{path}")
        elif event_id != expected_event_id:
            errors.append(
                f"事件 ID 与资源路径错配：{path} -> {event_id}，期望 {expected_event_id}"
            )
        if event_id and event_id in event_ids:
            errors.append(f"事件 ID 重复：{event_id}")
        if event_id:
            event_ids.add(event_id)
        if not event_title:
            errors.append(f"事件标题缺失：{path}")
        if not event_region:
            errors.append(f"事件区域缺失：{path}")
        elif event_region not in sector_ids:
            errors.append(f"事件区域 ID 未映射到真实区域：{path} -> {event_region}")

        branch_key = event.get("required_decision_tag_key") or ""
        branch_value = event.get("required_decision_tag_value") or ""
        if bool(branch_key) != bool(branch_value):
            errors.append(
                f"条件分支引用必须同时提供键和值：{path} -> {branch_key}/{branch_value}"
            )
        elif branch_key and (branch_key, branch_value) not in decision_tag_pairs:
            if branch_key not in decision_tag_keys:
                errors.append(
                    f"条件分支引用的决策标签键不存在：{path} -> {branch_key}"
                )
            else:
                errors.append(
                    f"条件分支引用的决策标签值不存在：{path} -> {branch_key}/{branch_value}"
                )

        option_ids: set[str] = set()
        for index, option in enumerate(event.get("options", []), start=1):
            option_id = option.get("option_id") or ""
            button_text = option.get("button_text") or ""
            expected_option_id = f"option_{index:02d}"
            if not option_id:
                errors.append(f"选项 ID 缺失：{path} #{index}")
            elif option_id != expected_option_id:
                errors.append(
                    f"选项 ID 与固定顺序错配：{path} #{index} -> {option_id}，期望 {expected_option_id}"
                )
            if option_id and option_id in option_ids:
                errors.append(f"事件内选项 ID 重复：{path} -> {option_id}")
            if option_id:
                option_ids.add(option_id)
            if not button_text:
                errors.append(f"选项文字缺失：{path} #{index}")

    return errors


def _path_text(root: Path, path: Path) -> str:
    return path.relative_to(root).as_posix()


def classify_usage(
    path: str,
    line: str,
    *,
    function_scope: str = "",
) -> Optional[dict[str, Any]]:
    """将一行身份相关使用归入计划规定的五类用途。"""
    fields = [field for field in IDENTITY_FIELDS if field in line]
    if not fields:
        return None

    lowered = line.lower()
    if function_scope in RUNTIME_IDENTITY_FUNCTIONS or any(
        marker in line
        for marker in (
            "triggered_events",
            "match event.event_id",
            "_get_event_trigger_key",
            "_get_event_option",
            "_find_sector_by_id",
        )
    ):
        category = "runtime_identity"
    elif any(
        marker in line
        for marker in ("required_", "event_state", "condition", "branch")
    ):
        category = "condition"
    elif path.startswith("tests/") or "record_" in lowered or "log" in lowered:
        category = "log_or_test"
    elif path.endswith(".tres") and any(
        line.lstrip().startswith(field + " =") for field in fields
    ):
        category = "display_only" if any(
            field in fields
            for field in (
                "event_title",
                "event_description",
                "region_name",
                "display_name",
                "button_text",
            )
        ) else "data_reference"
    elif ".text" in lowered or "label" in lowered or "display" in lowered:
        category = "display_only"
    else:
        category = "data_reference"

    return {
        "path": path,
        "line": line.strip(),
        "fields": fields,
        "category": category,
        "function_scope": function_scope,
    }


def scan_usage(root: Path) -> list[dict[str, Any]]:
    """扫描项目代码、场景和数据中的身份相关使用。"""
    entries: list[dict[str, Any]] = []
    scan_roots = (root / "scripts", root / "tests", root / "scenes", root / "data")
    for scan_root in scan_roots:
        if not scan_root.exists():
            continue
        for path in sorted(scan_root.rglob("*")):
            if path.suffix not in {".gd", ".tres", ".tscn"}:
                continue
            relative = _path_text(root, path)
            function_scope = ""
            for line_number, line in enumerate(
                path.read_text(encoding="utf-8").splitlines(), start=1
            ):
                if path.suffix == ".gd":
                    function_match = _FUNCTION_DECLARATION_RE.match(line)
                    if function_match:
                        function_scope = function_match.group(1)
                usage = classify_usage(
                    relative,
                    line,
                    function_scope=function_scope,
                )
                if usage is not None:
                    entries.append({"line_number": line_number, **usage})
    return entries


def _write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def _load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _mapping_diff(expected: Any, actual: Any) -> str:
    expected_text = json.dumps(expected, ensure_ascii=False, indent=2, sort_keys=True)
    actual_text = json.dumps(actual, ensure_ascii=False, indent=2, sort_keys=True)
    return "基线与当前身份映射不一致。\n期望：\n%s\n当前：\n%s" % (
        expected_text,
        actual_text,
    )


def main(
    argv: Optional[list[str]] = None,
    *,
    root: Optional[Path] = None,
) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="项目根目录，默认使用当前仓库",
    )
    baseline_group = parser.add_mutually_exclusive_group()
    baseline_group.add_argument("--baseline", type=Path, help="比对身份映射基线")
    baseline_group.add_argument(
        "--write-baseline", type=Path, help="写入身份映射基线"
    )
    parser.add_argument("--report-json", type=Path, help="写入身份使用审计报告")
    args = parser.parse_args(argv)

    project_root = (root or args.root).resolve()
    mapping = collect_mapping(project_root)

    validation_errors = validate_mapping(mapping)
    if validation_errors:
        print("[CONTENT-IDENTITY-AUDIT] 身份映射审计失败：", file=sys.stderr)
        for error in validation_errors:
            print(f"  - {error}", file=sys.stderr)
        return 1

    if args.write_baseline is not None:
        _write_json(args.write_baseline, mapping)
    if args.baseline is not None:
        expected = _load_json(args.baseline)
        if expected != mapping:
            print(_mapping_diff(expected, mapping), file=sys.stderr)
            return 1

    usage = scan_usage(project_root)
    counts = Counter(entry["category"] for entry in usage)
    report = {
        "schema_version": 1,
        "usage": usage,
        "counts": {category: counts.get(category, 0) for category in USAGE_CATEGORIES},
    }
    if args.report_json is not None:
        _write_json(args.report_json, report)

    print(
        "[CONTENT-IDENTITY-AUDIT] events=%d sectors=%d usages=%d categories=%s"
        % (
            len(mapping["events"]),
            len(mapping["sectors"]),
            len(usage),
            ",".join(
                "%s:%d" % (category, counts.get(category, 0))
                for category in USAGE_CATEGORIES
            ),
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
