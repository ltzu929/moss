#!/usr/bin/env python3
"""MOSS 测试私有访问审计工具。

扫描 tests/ 下的 GDScript 测试文件，识别测试代码对生产对象私有成员
（`_` 前缀约定）的跨脚本访问，输出基线 JSON 或执行门禁检查。

三类访问：
- direct_member：`obj._foo` / `obj._foo()`
- engine_callback：跨对象调用 Godot 生命周期回调或 `_on_*` 信号处理器
- dynamic_get / dynamic_set / dynamic_call：`get/set/call("_...")`

豁免：注释、字符串字面量（含三引号多行）、裸名调用、`self._xxx`、
`super._xxx`、字符串参数不以 `_` 开头的字典 `.get("key")`。

实现采用逐行 token 化：每行被拆成 code / str 两类 token，注释与字符串
内容不会进入 code token（避免误报），字符串 token 保留原文供动态访问
解析（避免漏报）。

仅使用 Python 标准库；路径处理兼容 Windows（输出统一正斜杠）。
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path
from typing import Optional

# Godot 引擎生命周期回调集合：跨对象直接调用这些回调属于实现耦合，
# 即使语法上允许也必须报告。
ENGINE_CALLBACKS: frozenset[str] = frozenset({
    "_init",
    "_ready",
    "_enter_tree",
    "_exit_tree",
    "_process",
    "_physics_process",
    "_input",
    "_shortcut_input",
    "_unhandled_input",
    "_unhandled_key_input",
    "_notification",
    "_draw",
    "_gui_input",
    "_get_minimum_size",
    "_set",
    "_get",
    "_to_string",
    "_get_property_list",
    "_validate_property",
    "_get_configuration_warnings",
    "_make_custom_tooltip",
    "_get_tooltip",
})

# 直接成员访问：点号（可带空白）后紧跟 `_` 开头的标识符
_DIRECT_MEMBER_RE = re.compile(r"\.\s*_[A-Za-z][A-Za-z0-9_]*")

# 动态访问：get / set / call 后紧跟括号
_DYNAMIC_RE = re.compile(r"\b(get|set|call)\b\s*\(")

# 点号前的接收者尾部标识符（用于排除 self./super.）
_RECEIVER_TAIL_RE = re.compile(r"([A-Za-z_][A-Za-z0-9_]*)\s*$")

# 免于审计的接收者：测试类自身与父类
_SELF_SUPER: frozenset[str] = frozenset({"self", "super"})

# 动态访问方法名 -> kind
_DYNAMIC_KINDS = {
    "get": "dynamic_get",
    "set": "dynamic_set",
    "call": "dynamic_call",
}

# 行解析状态
_CODE = 0               # 普通代码
_STR_DOUBLE = 1         # "..." 字符串
_STR_SINGLE = 2         # '...' 字符串
_STR_TRIPLE_DOUBLE = 3  # """...""" 多行字符串
_STR_TRIPLE_SINGLE = 4  # '''...''' 多行字符串

# token 类型
_TOKEN_CODE = "code"    # 纯代码片段（不含注释与字符串内容）
_TOKEN_STR = "str"      # 字符串字面量（保留原文，含引号与转义）


def is_engine_callback(member: str) -> bool:
    """判断成员名是否属于引擎回调/信号处理器集合。"""
    return member in ENGINE_CALLBACKS or member.startswith("_on_")


def split_line(line: str, state: int) -> tuple[list[tuple[str, str]], int]:
    """把一行拆成（kind, text）token 列表，返回（tokens, 下一行状态）。

    - code token：不含注释与字符串内容，供直接成员访问正则使用；
    - str token：字符串字面量原文（含引号与转义），供动态访问解析使用。
    注释（`#` 到行尾，字符串内部的 `#` 除外）不产生 token。三引号字符串
    可跨行，状态会延续到下一行。
    """
    tokens: list[tuple[str, str]] = []
    code_buf: list[str] = []
    str_buf: list[str] = []
    i = 0
    n = len(line)
    while i < n:
        c = line[i]
        if state == _CODE:
            if c == "#":
                # 注释：行内剩余内容全部忽略
                break
            if c == '"' or c == "'":
                if line.startswith(c * 3, i):
                    # 进入三引号多行字符串
                    if code_buf:
                        tokens.append((_TOKEN_CODE, "".join(code_buf)))
                        code_buf = []
                    str_buf = [c * 3]
                    state = _STR_TRIPLE_DOUBLE if c == '"' else _STR_TRIPLE_SINGLE
                    i += 3
                    continue
                # 进入普通字符串
                if code_buf:
                    tokens.append((_TOKEN_CODE, "".join(code_buf)))
                    code_buf = []
                str_buf = [c]
                state = _STR_DOUBLE if c == '"' else _STR_SINGLE
                i += 1
                continue
            code_buf.append(c)
            i += 1
            continue
        if state in (_STR_DOUBLE, _STR_SINGLE):
            # 普通字符串：处理转义，寻找结束引号
            quote = '"' if state == _STR_DOUBLE else "'"
            if c == "\\":
                if i + 1 < n:
                    str_buf.append(line[i : i + 2])
                    i += 2
                else:
                    str_buf.append(c)
                    i += 1
                continue
            str_buf.append(c)
            i += 1
            if c == quote:
                tokens.append((_TOKEN_STR, "".join(str_buf)))
                state = _CODE
            continue
        # 三引号字符串：处理转义，寻找结束标记
        marker = '"""' if state == _STR_TRIPLE_DOUBLE else "'''"
        if line.startswith(marker, i):
            str_buf.append(marker)
            tokens.append((_TOKEN_STR, "".join(str_buf)))
            state = _CODE
            i += 3
            continue
        if c == "\\":
            if i + 1 < n:
                str_buf.append(line[i : i + 2])
                i += 2
            else:
                str_buf.append(c)
                i += 1
            continue
        str_buf.append(c)
        i += 1
    if code_buf:
        tokens.append((_TOKEN_CODE, "".join(code_buf)))
    return tokens, state


def parse_string_at(code: str, start: int) -> tuple[Optional[str], int]:
    """解析 code[start] 处的字符串字面量，返回（内容, 结束下标）。

    处理转义序列；无法解析时返回 (None, -1)。
    """
    quote = code[start]
    if code.startswith(quote * 3, start):
        marker = quote * 3
        i = start + 3
        while i < len(code):
            if code.startswith(marker, i):
                return code[start + 3 : i], i + 3
            if code[i] == "\\":
                i += 2
            else:
                i += 1
        return None, -1
    i = start + 1
    chars: list[str] = []
    while i < len(code):
        c = code[i]
        if c == "\\":
            if i + 1 < len(code):
                nxt = code[i + 1]
                if nxt in (quote, "\\"):
                    chars.append(nxt)  # 去转义：\" \\ 只保留字符本身
                else:
                    chars.append("\\")
                    chars.append(nxt)
                i += 2
                continue
            chars.append("\\")
            i += 1
            continue
        if c == quote:
            return "".join(chars), i + 1
        chars.append(c)
        i += 1
    return None, -1


def extract_accesses(tokens: list[tuple[str, str]]) -> list[tuple[str, str]]:
    """从一行 token 流中提取（member, kind）访问列表。

    - 直接成员访问只作用于 code token（字符串与注释内容已隔离）；
    - 动态访问在 code token 中找到 `get/set/call(` 调用后，取紧随其后的
      str token 解析字符串参数，参数以 `_` 开头才报告。
    """
    found: list[tuple[str, str]] = []
    # 直接成员访问 obj._foo / obj._foo()
    code = " ".join(text for kind, text in tokens if kind == _TOKEN_CODE)
    for m in _DIRECT_MEMBER_RE.finditer(code):
        # 点号前的接收者尾部标识符：self./super. 豁免
        tail = _RECEIVER_TAIL_RE.search(code[: m.start()])
        if tail is not None and tail.group(1) in _SELF_SUPER:
            continue
        member = m.group(0)[m.group(0).find("_") :]
        kind = "engine_callback" if is_engine_callback(member) else "direct_member"
        found.append((member, kind))
    # 动态访问 get/set/call("_...")
    for idx, (kind, text) in enumerate(tokens):
        if kind != _TOKEN_CODE:
            continue
        for m in _DYNAMIC_RE.finditer(text):
            rest = text[m.end() :]
            # 跳过紧跟的纯空白 code token（允许跨行空白）
            j = idx + 1
            while (
                j < len(tokens)
                and tokens[j][0] == _TOKEN_CODE
                and not tokens[j][1].strip()
            ):
                j += 1
            if rest.strip():
                # '(' 之后还有非空白代码：首个实参不是字符串字面量
                continue
            if j >= len(tokens) or tokens[j][0] != _TOKEN_STR:
                continue
            value, _end = parse_string_at(tokens[j][1], 0)
            if value is None or not value.startswith("_"):
                continue  # 只有以 `_` 开头的字符串参数才算动态私有访问
            found.append((value, _DYNAMIC_KINDS[m.group(1)]))
    return found


def extract_accesses_from_code(code: str) -> list[tuple[str, str]]:
    """便捷函数：把一段代码当作单行解析（含字符串与注释处理）后提取访问。"""
    tokens, _state = split_line(code, _CODE)
    return extract_accesses(tokens)


def scan_file(path: Path) -> list[tuple[str, str]]:
    """扫描单个 .gd 文件，返回（member, kind）访问列表。"""
    accesses: list[tuple[str, str]] = []
    state = _CODE
    try:
        with path.open("r", encoding="utf-8", errors="replace") as fh:
            for raw in fh:
                line = raw.rstrip("\r\n")
                tokens, state = split_line(line, state)
                accesses.extend(extract_accesses(tokens))
    except OSError as exc:
        print(f"警告：无法读取 {path}：{exc}", file=sys.stderr)
    return accesses


def scan_directory(root: Path) -> tuple[Counter[tuple[str, str, str]], int]:
    """递归扫描 root 下所有 .gd 文件。

    返回（(path, member, kind) -> count 聚合, 覆盖文件数）。
    path 为相对 root 的正斜杠路径。
    """
    counter: Counter[tuple[str, str, str]] = Counter()
    file_count = 0
    for path in sorted(root.rglob("*.gd")):
        if not path.is_file():
            continue
        rel = path.relative_to(root).as_posix()
        file_count += 1
        for member, kind in scan_file(path):
            counter[(rel, member, kind)] += 1
    return counter, file_count


def baseline_to_entries(
    counter: Counter[tuple[str, str, str]],
) -> list[dict[str, object]]:
    """把聚合计数转为排序稳定的基线条目列表。"""
    entries = [
        {"path": p, "member": m, "kind": k, "count": c}
        for (p, m, k), c in counter.items()
    ]
    entries.sort(key=lambda e: (e["path"], e["member"], e["kind"]))
    return entries


def load_baseline(path: Path) -> dict[tuple[str, str, str], int]:
    """加载基线 JSON 文件为（path, member, kind）-> count 聚合字典。"""
    with path.open("r", encoding="utf-8") as fh:
        raw = json.load(fh)
    result: dict[tuple[str, str, str], int] = {}
    for item in raw:
        key = (item["path"], item["member"], item["kind"])
        result[key] = int(item["count"])
    return result


def write_baseline(path: Path, counter: Counter[tuple[str, str, str]]) -> None:
    """把当前扫描结果写出为基线 JSON（自动创建父目录）。"""
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as fh:
        json.dump(baseline_to_entries(counter), fh, ensure_ascii=False, indent=2)
        fh.write("\n")


def compare_with_baseline(
    current: Counter[tuple[str, str, str]],
    baseline: dict[tuple[str, str, str], int],
) -> tuple[
    list[tuple[tuple[str, str, str], int]],
    list[tuple[tuple[str, str, str], int, int]],
]:
    """对比当前扫描与基线。

    返回（新增条目, 次数增长条目）；基线中存在而当前减少的条目不报告。
    """
    new_entries: list[tuple[tuple[str, str, str], int]] = []
    grown: list[tuple[tuple[str, str, str], int, int]] = []
    for key, count in sorted(current.items()):
        if key not in baseline:
            new_entries.append((key, count))
        elif count > baseline[key]:
            grown.append((key, baseline[key], count))
    return new_entries, grown


def _format_entry(key: tuple[str, str, str], count: int) -> str:
    path, member, kind = key
    return f"  {path}  {member}  {kind}  共 {count} 次"


def _reconfigure_stdout() -> None:
    """Windows 控制台默认使用 GBK，中文输出会乱码；统一切到 UTF-8。

    仅在 CLI 入口调用；单元测试注入 stdout 时不触发。
    """
    for stream in (sys.stdout, sys.stderr):
        reconfigure = getattr(stream, "reconfigure", None)
        if reconfigure is not None:
            try:
                reconfigure(encoding="utf-8", errors="replace")
            except (OSError, ValueError):
                pass


def main(argv: Optional[list[str]] = None, tests_dir: Optional[Path] = None) -> int:
    """CLI 入口。tests_dir 仅供测试注入，默认为项目 tests/ 目录。"""
    parser = argparse.ArgumentParser(
        prog="audit_test_private_access",
        description="扫描 MOSS 测试对生产对象私有成员的访问，支持基线对比与零访问门禁。",
    )
    parser.add_argument("--baseline", metavar="FILE", help="基线 JSON 文件路径")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--fail-on-new",
        action="store_true",
        help="与基线对比：出现新条目或现有条目次数增长即失败（退出码 1）",
    )
    mode.add_argument(
        "--require-zero",
        action="store_true",
        help="要求当前扫描结果为空，否则失败（退出码 1）",
    )
    parser.add_argument(
        "--write-baseline",
        metavar="FILE",
        help="把当前扫描结果写出为基线 JSON（用于首次生成）",
    )
    args = parser.parse_args(argv)

    if args.fail_on_new and not args.baseline:
        parser.error("--fail-on-new 需要同时提供 --baseline <file>")

    if tests_dir is None:
        tests_dir = Path(__file__).resolve().parent.parent / "tests"
    tests_dir = Path(tests_dir)
    counter, file_count = scan_directory(tests_dir)

    if args.write_baseline:
        write_baseline(Path(args.write_baseline), counter)

    if args.require_zero:
        if counter:
            print(f"审计失败：tests/ 下发现 {len(counter)} 处私有访问条目：")
            for key, count in sorted(counter.items()):
                print(_format_entry(key, count))
            return 1
        print("审计通过：tests/ 下不存在对生产对象私有成员的访问")
        return 0

    if args.fail_on_new:
        try:
            baseline = load_baseline(Path(args.baseline))
        except (OSError, ValueError, KeyError) as exc:
            print(f"错误：无法加载基线 {args.baseline}：{exc}", file=sys.stderr)
            return 2
        new_entries, grown = compare_with_baseline(counter, baseline)
        if not new_entries and not grown:
            print(f"审计通过：未发现新增私有访问或次数增长（共 {len(counter)} 个条目）")
            return 0
        print("审计失败：发现新增私有访问或次数增长：")
        if new_entries:
            print("新增条目：")
            for key, count in new_entries:
                print(_format_entry(key, count))
        if grown:
            print("次数增长：")
            for key, old, new in grown:
                path, member, kind = key
                print(f"  {path}  {member}  {kind}  {old} -> {new}")
        return 1

    # 无参数：打印当前扫描摘要
    total = sum(counter.values())
    print(
        f"扫描完成：覆盖 {file_count} 个测试文件，"
        f"共 {len(counter)} 个私有访问条目，总访问 {total} 次"
    )
    return 0


if __name__ == "__main__":
    _reconfigure_stdout()
    sys.exit(main())
