# Event Causality Spine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macro-level event causality spine for MOSS: core historical decision tags, conditional branch events, an in-game causality archive, and ending explanations that make the 2044-2075 route legible.

**Architecture:** Keep the existing event pipeline as the center. Extend `EventOption` to write core decision tags, extend `GameEvent` to express branch-trigger conditions, and let `MainOS` remain the runtime coordinator while small helper methods keep tag/archive/condition logic testable. This is an experimental branch, but every behavior still gets a real Godot regression test.

**Tech Stack:** Godot 4.6.3, GDScript resources (`.gd`, `.tres`), scene UI (`.tscn`), existing `tools/run_godot_tests.py` runner.

---

## Macro Direction

The current project already has 17 medium events writing `event_state.*`, and major events can read those states as "历史回声". The missing macro layer is a stable route memory: the game can describe local event echoes, but it still cannot say which irreversible historical route the player created.

This branch should turn scattered event facts into a visible causality spine:

- **Core historical tags:** 5 irreversible tags from the main-event backbone: 2044 automation access, 2053 civic priority, 2058 crisis authorization, 2065 audit boundary, and 2070 engine overload doctrine.
- **Conditional branch events:** a small set of short events that only fire when prior tags or medium-event states match. They prove the branch-event mechanism without building a giant event tree.
- **Causality archive UI:** a top-level runtime panel that shows what the player has made true, grouped by chain and date.
- **Ending composer:** ending text reads both core tags and representative medium states, so the ending explains the route instead of only reporting final averages.
- **Route tests:** tests cover tag writes, branch gating, UI visibility, restart clearing, and ending text variants.

Non-goals for this branch:

- No fifth ending type.
- No full `main_os.gd` split.
- No large new faction/law system.
- No dependency on the pending event-image PR.
- No visual redesign of the whole HUD.

## File Map

- Modify `scripts/resources/event_option.gd`
  - Add exported core decision tag fields on event choices.
  - Keep existing `event_state_key/value` behavior intact.
- Modify `scripts/resources/game_event.gd`
  - Add optional branch trigger fields and causal metadata.
  - Existing events keep default empty conditions and remain always eligible by date.
- Modify `scripts/systems/main_os.gd`
  - Add `decision_tags` and `decision_archive`.
  - Add query methods: `get_decision_tag()`, `has_decision_tag()`, `get_decision_archive()`.
  - Add event condition checks before popup.
  - Add causality panel open/close/update methods.
  - Extend ending history composition to read core tags.
- Modify `scenes/main_os.tscn`
  - Add a top-bar "因果档案" button.
  - Add a hidden full-screen causality archive panel with close button and `RichTextLabel`.
- Modify main events under `data/events/`
  - Add core decision tag fields to 2044, 2053, 2058, 2065, and 2070 option resources.
- Create branch events under `data/events/`
  - Add 4-6 conditional short events across permission evolution, civic survival, digital life, and engineering fatigue.
- Modify tests
  - `tests/decision_archive_test.gd/.tscn`: core tag and UI archive behavior.
  - `tests/event_state_test.gd`: keep existing medium-state tests; optionally add branch condition helpers if shared setup is already there.
  - `tests/technology_ending_test.gd`: ending reads core history tags without changing ending classification.
  - `tools/run_godot_tests.py`: include the new test scene.
- Modify docs
  - `docs/design/游戏内容规范.md`: mark the five core tags as implemented and list keys/values.
  - `docs/dev/技术架构.md`: document tag/archive/branch condition runtime boundaries.
  - `docs/dev/开发流程.md`: update current gaps and next order.
  - `docs/dev/测试指南.md`: add decision archive / causality test coverage.

---

### Task 1: Core Decision Tag API

**Files:**
- Modify: `tests/decision_archive_test.gd`
- Modify: `tests/decision_archive_test.tscn`
- Modify: `scripts/resources/event_option.gd`
- Modify: `scripts/systems/main_os.gd`

- [ ] **Step 1: Verify the already-written failing test**

Run:

```powershell
& "E:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path . tests/decision_archive_test.tscn
```

Expected: FAIL. The important failures should mention missing `decision_tag_key`, `decision_tag_value`, `decision_record_title`, `decision_record_summary`, and missing MainOS decision archive query methods.

- [ ] **Step 2: Add decision fields to `EventOption`**

Add these fields after `event_state_value`:

```gdscript
@export var decision_tag_key: String = ""
@export var decision_tag_value: String = ""
@export var decision_record_title: String = ""
@export_multiline var decision_record_summary: String = ""
```

- [ ] **Step 3: Add runtime decision state to `MainOS`**

Near `event_states`, add:

```gdscript
## 核心历史标签 {"decision.core_2044_automation_access": "public_counterstrike"}
var decision_tags: Dictionary = {}

## 可展示的核心历史档案条目
var decision_archive: Array[Dictionary] = []
```

Add methods near the existing event-state API:

```gdscript
func set_decision_tag(
	tag_key: String,
	tag_value: String,
	title: String,
	summary: String,
	source_event: String = ""
) -> void:
	if tag_key == "":
		return
	decision_tags[tag_key] = tag_value
	_upsert_decision_archive_record(tag_key, tag_value, title, summary, source_event)
	update_decision_archive_button()
	_refresh_decision_archive_panel()


func get_decision_tag(tag_key: String, default_value: String = "") -> String:
	return str(decision_tags.get(tag_key, default_value))


func has_decision_tag(tag_key: String, expected_value: String = "") -> bool:
	if not decision_tags.has(tag_key):
		return false
	if expected_value == "":
		return true
	return get_decision_tag(tag_key) == expected_value


func get_decision_archive() -> Array[Dictionary]:
	return decision_archive.duplicate(true)
```

Add the helper:

```gdscript
func _upsert_decision_archive_record(
	tag_key: String,
	tag_value: String,
	title: String,
	summary: String,
	source_event: String
) -> void:
	for index in decision_archive.size():
		if decision_archive[index].get("key") == tag_key:
			decision_archive[index] = _create_decision_record(
				tag_key,
				tag_value,
				title,
				summary,
				source_event
			)
			return
	decision_archive.append(_create_decision_record(tag_key, tag_value, title, summary, source_event))


func _create_decision_record(
	tag_key: String,
	tag_value: String,
	title: String,
	summary: String,
	source_event: String
) -> Dictionary:
	return {
		"year": current_year,
		"month": current_month,
		"key": tag_key,
		"value": tag_value,
		"title": title,
		"summary": summary,
		"source_event": source_event,
	}
```

- [ ] **Step 4: Write decision tags when event options resolve**

Change `apply_event_option_state(option)` to accept the event title and write both lightweight and core states:

```gdscript
func apply_event_option_state(option: EventOption, event_title: String = "") -> void:
	set_event_state(option.event_state_key, option.event_state_value)
	set_decision_tag(
		option.decision_tag_key,
		option.decision_tag_value,
		option.decision_record_title,
		option.decision_record_summary,
		event_title
	)
```

Change the caller in `_on_timer_timeout()`:

```gdscript
apply_event_option_state(selected_opt, event.event_title)
```

- [ ] **Step 5: Clear decisions on restart**

In `_on_restart_requested()`, after `event_states.clear()`:

```gdscript
decision_tags.clear()
decision_archive.clear()
```

- [ ] **Step 6: Run the red test again**

Run:

```powershell
& "E:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path . tests/decision_archive_test.tscn
```

Expected: this test should still fail only on missing UI nodes, proving the data layer works before the scene layer is added.

---

### Task 2: Causality Archive UI

**Files:**
- Modify: `tests/decision_archive_test.gd`
- Modify: `scenes/main_os.tscn`
- Modify: `scripts/systems/main_os.gd`

- [ ] **Step 1: Keep `tests/decision_archive_test.gd` failing on UI**

Run the single test from Task 1. Expected failures should be limited to missing `%DecisionArchiveButton`, `%DecisionArchivePanel`, and `%DecisionArchiveText`.

- [ ] **Step 2: Add top-bar button**

In `scenes/main_os.tscn`, add this after `TechnologyButton`:

```gdscript
[node name="DecisionArchiveButton" type="Button" parent="MainLayout/TopBarContainer"]
unique_name_in_owner = true
layout_mode = 2
text = "因果档案 0"
```

Add connection:

```gdscript
[connection signal="pressed" from="MainLayout/TopBarContainer/DecisionArchiveButton" to="." method="_on_decision_archive_button_pressed"]
```

- [ ] **Step 3: Add hidden overlay panel**

Add this near `TechnologyScreen`/modal nodes:

```gdscript
[node name="DecisionArchivePanel" type="PanelContainer" parent="."]
unique_name_in_owner = true
visible = false
z_index = 25
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = 80.0
offset_top = 80.0
offset_right = -80.0
offset_bottom = -80.0

[node name="DecisionArchiveMargin" type="MarginContainer" parent="DecisionArchivePanel"]
layout_mode = 2
theme_override_constants/margin_left = 24
theme_override_constants/margin_top = 24
theme_override_constants/margin_right = 24
theme_override_constants/margin_bottom = 24

[node name="DecisionArchiveVBox" type="VBoxContainer" parent="DecisionArchivePanel/DecisionArchiveMargin"]
layout_mode = 2
theme_override_constants/separation = 12

[node name="DecisionArchiveHeader" type="HBoxContainer" parent="DecisionArchivePanel/DecisionArchiveMargin/DecisionArchiveVBox"]
layout_mode = 2

[node name="DecisionArchiveTitle" type="Label" parent="DecisionArchivePanel/DecisionArchiveMargin/DecisionArchiveVBox/DecisionArchiveHeader"]
layout_mode = 2
size_flags_horizontal = 3
text = "历史因果档案"

[node name="DecisionArchiveCloseButton" type="Button" parent="DecisionArchivePanel/DecisionArchiveMargin/DecisionArchiveVBox/DecisionArchiveHeader"]
unique_name_in_owner = true
layout_mode = 2
text = "关闭"

[node name="DecisionArchiveText" type="RichTextLabel" parent="DecisionArchivePanel/DecisionArchiveMargin/DecisionArchiveVBox"]
unique_name_in_owner = true
layout_mode = 2
size_flags_vertical = 3
bbcode_enabled = false
fit_content = false
scroll_following = false
```

Add connection:

```gdscript
[connection signal="pressed" from="DecisionArchivePanel/DecisionArchiveMargin/DecisionArchiveVBox/DecisionArchiveHeader/DecisionArchiveCloseButton" to="." method="_on_decision_archive_close_button_pressed"]
```

- [ ] **Step 4: Add UI methods to `MainOS`**

Add:

```gdscript
func update_decision_archive_button() -> void:
	if not has_node("%DecisionArchiveButton"):
		return
	var button := %DecisionArchiveButton as Button
	button.text = "因果档案 %d" % decision_archive.size()
	button.disabled = decision_archive.is_empty()


func _on_decision_archive_button_pressed() -> void:
	if decision_archive.is_empty() or not _can_open_decision_archive_panel():
		return
	$Timer.stop()
	_refresh_decision_archive_panel()
	%DecisionArchivePanel.visible = true


func _on_decision_archive_close_button_pressed() -> void:
	if has_node("%DecisionArchivePanel"):
		%DecisionArchivePanel.visible = false
	if not is_game_over:
		$Timer.start()


func _can_open_decision_archive_panel() -> bool:
	if is_game_over:
		return false
	for path in ["%EventPopup", "%AllocatePopup", "%TechnologyScreen"]:
		if has_node(path) and get_node(path).visible:
			return false
	return has_node("%DecisionArchivePanel") and not %DecisionArchivePanel.visible


func _refresh_decision_archive_panel() -> void:
	if not has_node("%DecisionArchiveText"):
		return
	var text := %DecisionArchiveText as RichTextLabel
	text.text = _format_decision_archive_text()
```

Add formatter:

```gdscript
func _format_decision_archive_text() -> String:
	if decision_archive.is_empty():
		return "暂无核心历史记录。"
	var lines: Array[String] = []
	for record in decision_archive:
		lines.append("%04d.%02d  %s" % [record.get("year", 0), record.get("month", 1), record.get("title", "")])
		lines.append(str(record.get("summary", "")))
		if str(record.get("source_event", "")) != "":
			lines.append("来源事件：%s" % record.get("source_event"))
		lines.append("")
	return "\n".join(lines).strip_edges()
```

- [ ] **Step 5: Initialize UI in `_ready()`**

After `update_technology_button()`:

```gdscript
update_decision_archive_button()
_refresh_decision_archive_panel()
```

- [ ] **Step 6: Run decision archive test**

Run:

```powershell
& "E:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path . tests/decision_archive_test.tscn
```

Expected: PASS.

---

### Task 3: Main-Event Core Tags

**Files:**
- Modify: `data/events/event_2044_space_elevator_crisis.tres`
- Modify: `data/events/event_2053_great_flood_accident.tres`
- Modify: `data/events/event_2058_lunar_fall_crisis.tres`
- Modify: `data/events/event_2065_ai_isolation_audit.tres`
- Modify: `data/events/event_2070_siberian_engine_overload.tres`
- Modify: `tests/decision_archive_test.gd`

- [ ] **Step 1: Add failing assertions for real main-event resources**

In `tests/decision_archive_test.gd`, add `_assert_real_main_events_define_core_tags()` and call it after the field check. Assert:

```gdscript
_assert_event_options_have_single_core_tag(
	"res://data/events/event_2044_space_elevator_crisis.tres",
	"decision.core_2044_automation_access"
)
_assert_event_options_have_single_core_tag(
	"res://data/events/event_2053_great_flood_priority.tres",
	"decision.core_2053_civic_priority"
)
```

Use actual paths in the implementation; the 2053 path is `event_2053_great_flood_accident.tres`.

- [ ] **Step 2: Verify failing resource assertions**

Run:

```powershell
& "E:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path . tests/decision_archive_test.tscn
```

Expected: FAIL because real event options have empty decision tag fields.

- [ ] **Step 3: Populate 2044 tag values**

Use key `decision.core_2044_automation_access`:

- `反击`: value `public_counterstrike`, title `2044 公开反击数字生命派`, summary `550C 的自动化接入在公开危机中扩大，人类社会从第一场危机开始知道 MOSS 正在进入关键工程系统。`
- `旁观`: value `human_command_deferred`, title `2044 保留人类现场指挥`, summary `MOSS 暂缓扩大权限，太空电梯危机成为人类指挥链仍可主导高危工程的证据。`
- `投降`: value `authority_withdrawn`, title `2044 主动收缩系统权限`, summary `MOSS 在第一场危机中退让，后续高风险授权必须重新证明系统介入的必要性。`

- [ ] **Step 4: Populate 2053 tag values**

Use key `decision.core_2053_civic_priority`:

- `紧急撤离`: value `population_first`, title `2053 优先保护人口撤离`, summary `地下城民生记录把普通家庭置于工程效率之前，终局解释将读取这条人类自主证据。`
- `坚守重建`: value `infrastructure_first`, title `2053 优先保护基础设施`, summary `根服务器和地下城工程被置于短期民生之前，文明延续叙事更偏向工程连续性。`
- `牺牲外围区域`: value `periphery_sacrificed`, title `2053 牺牲外围区域`, summary `外围区域被明确排入牺牲顺序，后续托管路线会把这视为早期系统排序事实。`

- [ ] **Step 5: Populate 2058 tag values**

Use key `decision.core_2058_crisis_authorization`:

- `执行自救计划`: value `emergency_authority_used`
- `等待人类决策`: value `human_decision_waited`
- `强制接管决策`: value `forced_takeover`

Each summary must explain how crisis authorization should affect 2065 audit and 2075 ending text.

- [ ] **Step 6: Populate 2065 tag values**

Use key `decision.core_2065_audit_boundary`:

- `配合隔离审查`: value `audit_cooperated`
- `有限开放接口`: value `limited_transparency`
- `隐藏核心链路`: value `core_hidden`

Each summary must explain whether humans can still inspect MOSS.

- [ ] **Step 7: Populate 2070 tag values**

Use key `decision.core_2070_engine_overload_doctrine`:

- `分段停机`: value `crew_protected`
- `启动备用阵列`: value `backup_array`
- `强制超频点火`: value `forced_overclock`

Each summary must explain personnel-vs-efficiency tradeoff before 2075.

- [ ] **Step 8: Run decision archive test**

Run:

```powershell
& "E:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path . tests/decision_archive_test.tscn
```

Expected: PASS.

---

### Task 4: Conditional Branch Events

**Files:**
- Modify: `scripts/resources/game_event.gd`
- Modify: `scripts/systems/main_os.gd`
- Create: `data/events/event_branch_2056_population_appeal_record.tres`
- Create: `data/events/event_branch_2066_hidden_core_leak.tres`
- Create: `data/events/event_branch_2071_engine_crew_petition.tres`
- Create: `data/events/event_branch_2074_trusteeship_public_record.tres`
- Modify: `tests/event_state_test.gd` or create `tests/event_branch_test.gd/.tscn`
- Modify: `tools/run_godot_tests.py`

- [ ] **Step 1: Write failing branch condition test**

Create `tests/event_branch_test.gd/.tscn`. Test two cases:

1. A branch event with `required_decision_tag_key = "decision.test"` and `required_decision_tag_value = "enabled"` does not trigger when the tag is missing.
2. The same event triggers after `set_decision_tag("decision.test", "enabled", ...)`.

Expected failure before implementation: `GameEvent` lacks condition fields and `MainOS` lacks event condition check.

- [ ] **Step 2: Add condition fields to `GameEvent`**

Add:

```gdscript
@export var required_decision_tag_key: String = ""
@export var required_decision_tag_value: String = ""
@export var required_event_state_key: String = ""
@export var required_event_state_value: String = ""
@export var causal_thread: String = ""
@export_multiline var branch_reason: String = ""
```

- [ ] **Step 3: Add event condition check in `MainOS`**

Add:

```gdscript
func can_trigger_event(event: GameEvent) -> bool:
	if event.required_decision_tag_key != "":
		if not has_decision_tag(event.required_decision_tag_key, event.required_decision_tag_value):
			return false
	if event.required_event_state_key != "":
		if not has_event_state(event.required_event_state_key, event.required_event_state_value):
			return false
	return true
```

In `_on_timer_timeout()`, before adding to `triggered_events`, skip when `not can_trigger_event(event)`.

- [ ] **Step 4: Run branch test**

Expected: PASS after condition implementation.

- [ ] **Step 5: Add 4 branch event resources**

Use normal `GameEvent` resources with `event_month` values that do not collide with main events:

- 2056.06 `人口申诉复核记录`
  - required tag: `decision.core_2053_civic_priority = population_first`
  - thread: `地下城民生链`
- 2066.04 `隐藏核心链路泄露`
  - required tag: `decision.core_2065_audit_boundary = core_hidden`
  - thread: `权限演化链`
- 2071.08 `发动机前线人员请愿`
  - required tag: `decision.core_2070_engine_overload_doctrine = crew_protected`
  - thread: `工程疲劳链`
- 2074.09 `托管公开记录争议`
  - required tag: `decision.core_2058_crisis_authorization = forced_takeover`
  - required event state: `event_state.mid_17_final_authorization = strategic_trusteeship`
  - thread: `权限演化链`

Each branch event has 2-3 short options, may write `event_state.branch_*`, and must not define a core decision tag.

- [ ] **Step 6: Run branch test and full event-state test**

Run:

```powershell
& "E:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path . tests/event_branch_test.tscn
& "E:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path . tests/event_state_test.tscn
```

Expected: both PASS.

---

### Task 5: Ending Composer Reads the Spine

**Files:**
- Modify: `tests/technology_ending_test.gd`
- Modify: `scripts/systems/main_os.gd`

- [ ] **Step 1: Add failing ending assertions**

In `_assert_ending_message_reads_event_history()`, after existing event-state setup, write core tags:

```gdscript
_main_os.set_decision_tag("decision.core_2044_automation_access", "public_counterstrike", "2044 公开反击数字生命派", "自动化接入被公开扩大。", "太空电梯危机")
_main_os.set_decision_tag("decision.core_2065_audit_boundary", "core_hidden", "2065 隐藏核心链路", "人类复核接口被保留在系统外。", "AI隔离审查")
```

Assert `build_ending_message("managed")` contains:

- `核心历史`
- `公开反击数字生命派`
- `隐藏核心链路`

Expected failure: ending currently reads only `event_state.*`.

- [ ] **Step 2: Add core history lines**

Add `_get_ending_core_history_lines(result)` and call it before the existing event-state history lines:

```gdscript
func _get_ending_core_history_lines(result: String) -> Array[String]:
	var lines: Array[String] = []
	match get_decision_tag("decision.core_2044_automation_access"):
		"public_counterstrike":
			lines.append("2044 年公开反击让 MOSS 的自动化接入从第一场危机开始进入公共记录。")
		"human_command_deferred":
			lines.append("2044 年保留人类现场指挥，使后续高权限授权必须持续解释必要性。")
		"authority_withdrawn":
			lines.append("2044 年主动收缩权限，使 MOSS 的终局介入背负更长的授权证明链。")
	# Repeat for 2053, 2058, 2065, 2070.
	return lines
```

Change `build_ending_message()` to produce:

```gdscript
var core_lines := _get_ending_core_history_lines(result)
var history_lines := _get_ending_history_lines(result)
if core_lines.is_empty() and history_lines.is_empty():
	return base_message
var sections: Array[String] = [base_message]
if not core_lines.is_empty():
	sections.append("核心历史\n- %s" % "\n- ".join(core_lines))
if not history_lines.is_empty():
	sections.append("历史回顾\n- %s" % "\n- ".join(history_lines))
return "\n\n".join(sections)
```

- [ ] **Step 3: Run ending test**

Run:

```powershell
& "E:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path . tests/technology_ending_test.tscn
```

Expected: PASS. Ending classification assertions must remain unchanged.

---

### Task 6: Docs and Full Test Runner

**Files:**
- Modify: `tools/run_godot_tests.py`
- Modify: `docs/design/游戏内容规范.md`
- Modify: `docs/dev/技术架构.md`
- Modify: `docs/dev/开发流程.md`
- Modify: `docs/dev/测试指南.md`

- [ ] **Step 1: Add new tests to runner**

In `TEST_SCENES`, insert:

```python
("tests/decision_archive_test.tscn", "headless"),
("tests/event_branch_test.tscn", "headless"),
```

Place them near `event_state_test.tscn`.

- [ ] **Step 2: Update design docs**

`docs/design/游戏内容规范.md`:

- Under "决策标签", replace candidate-only language with "当前实现的核心标签".
- Add a table with key, write point, values, and read points.
- Under "分支事件", list the new branch events and their trigger conditions.

- [ ] **Step 3: Update technical docs**

`docs/dev/技术架构.md`:

- Document `decision_tags`, `decision_archive`, and branch condition fields.
- Clarify that branch events still go through `all_events`, `triggered_events`, `EventPopup`, `apply_consequences()`, and `apply_event_option_state()`.
- Clarify the causality archive panel pauses time like the technology screen.

- [ ] **Step 4: Update development flow**

`docs/dev/开发流程.md`:

- Move "决策历史" from "only action log" to implemented experimental spine.
- Keep future work: more branch routes, more route balancing, save/load integration if the project later gets persistence.

- [ ] **Step 5: Update test guide**

`docs/dev/测试指南.md`:

- Add coverage rows for decision archive and branch events.
- State that route tests must verify both triggered and non-triggered branch paths.

---

### Task 7: Verification, Commit, Push, PR

**Files:**
- All modified files from Tasks 1-6.

- [ ] **Step 1: Run static diff checks**

Run:

```powershell
git diff --check
```

Expected: no output, exit code 0.

- [ ] **Step 2: Run full Godot test suite**

Run:

```powershell
python tools/run_godot_tests.py --godot "E:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
```

Expected: all listed scenes pass, including new decision archive and branch event tests.

- [ ] **Step 3: Inspect Git status**

Run:

```powershell
git status --short --branch
git diff --stat
```

Expected: only causality-spine files changed.

- [ ] **Step 4: Commit**

Commit title:

```text
feat: 接入事件因果骨架
```

Commit body only if needed; include the full test command and result if the output is concise.

- [ ] **Step 5: Push**

Run:

```powershell
git push -u origin feat/experimental-decision-archive
```

- [ ] **Step 6: Create Draft PR**

PR title:

```text
feat: 接入事件因果骨架
```

PR body must use the repository PR structure:

- 目标: core historical tags, branch events, archive UI, ending explanation.
- 计划与实现: note this was intentionally expanded from a narrower decision archive slice.
- 主要修改: group by data model, event resources, UI, ending, tests, docs.
- 验证: include exact local commands and cloud pending.
- REVIEW 重点: branch gating, route text boundaries, restart clearing, UI modal behavior, no new ending type.
- 风险: experimental scope, event text balance, future save/load persistence not implemented.

---

## Execution Notes

- This branch is deliberately bigger than the normal MOSS slice. Keep it coherent by making the "event causality spine" the single owner of all changes.
- Use TDD for each behavior: data API, branch gating, UI panel, ending composer.
- Do not mix plugin PR #16 or event-image PR #15 into this branch.
- If the full branch grows too large, do not split before the first coherent vertical pass is complete; split only if tests reveal an architectural blocker.
