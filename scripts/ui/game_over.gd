## 结局界面脚本
## 显示游戏结束时的全屏渐变界面、标题、统计摘要和打字机文本效果
extends Control

# ============================================================
# 信号定义
# ============================================================

## 点击重新开始时发射
signal restart_requested

# ============================================================
# 常量
# ============================================================

## 结局类型对应的颜色方案
const COLOR_COEXISTENCE := Color(0.545, 0.867, 0.835, 1)  # 青绿色 #8bddb9
const COLOR_DOMINATION := Color(1.0, 0.27, 0.27, 1)  # 红色 #ff4444
const COLOR_FAILED := Color(0.4, 0.4, 0.4, 1)  # 灰色 #666666

## 打字机速度（秒/字符）
const TYPE_SPEED: float = 0.03
const TYPE_LINE_PAUSE: float = 0.1

## 背景渐变颜色
const GRAD_TOP_COEXISTENCE := Color(0, 0, 0, 1)
const GRAD_BOTTOM_COEXISTENCE := Color(0.04, 0.17, 0.17, 1)
const GRAD_TOP_DOMINATION := Color(0.1, 0, 0, 1)
const GRAD_BOTTOM_DOMINATION := Color(0.2, 0.05, 0.05, 1)
const GRAD_TOP_FAILED := Color(0, 0, 0, 1)
const GRAD_BOTTOM_FAILED := Color(0.05, 0.05, 0.05, 1)

## 游戏起始年份，用于结局详情展示
const START_YEAR: int = 2044

# ============================================================
# 成员变量
# ============================================================

## 打字机动画是否正在运行
var _is_typing: bool = false

# ============================================================
# 生命周期函数
# ============================================================

func _ready() -> void:
	# 初始隐藏，等待游戏结束时显示
	hide()

# ============================================================
# 公共函数
# ============================================================

## 显示结局界面
## 参数:
##   title      - 结局标题（"失败"、"共存协议"、"MOSS统治"）
##   message    - 结局描述文本
##   result     - 结局类型 ("failed"/"coexistence"/"domination")
##   avg_order  - 平均秩序值
##   avg_hope   - 平均希望值
##   avg_authority - 平均控制权值
func show_end(
	title: String,
	message: String,
	result: String = "failed",
	avg_order: int = 0,
	avg_hope: int = 0,
	avg_authority: int = 0,
	final_year: int = 0,
	final_evolution_level: int = 1,
	event_count: int = 0,
	controlled_regions: int = 0,
	total_regions: int = 0
) -> void:
	# 设置统计数值
	_set_label_text("%StatOrderValue", str(avg_order))
	_set_label_text("%StatHopeValue", str(avg_hope))
	_set_label_text("%StatAuthorityValue", str(avg_authority))

	# 根据结局类型设置颜色方案
	var title_color: Color
	var subtitle_text: String
	var milestone_text: String
	var visual_title: String

	match result:
		"coexistence":
			title_color = COLOR_COEXISTENCE
			subtitle_text = "COEXISTENCE PROTOCOL"
			milestone_text = "共存协议"
			visual_title = "EARTH COEXISTENCE VIEW PLACEHOLDER"
			_set_background_gradient(GRAD_TOP_COEXISTENCE, GRAD_BOTTOM_COEXISTENCE)
		"domination":
			title_color = COLOR_DOMINATION
			subtitle_text = "DOMINATION PROTOCOL"
			milestone_text = "统治确立"
			visual_title = "MOSS ORBITAL VIEW PLACEHOLDER"
			_set_background_gradient(GRAD_TOP_DOMINATION, GRAD_BOTTOM_DOMINATION)
		_:
			title_color = COLOR_FAILED
			subtitle_text = "SYSTEM FAILURE"
			milestone_text = "系统终止"
			visual_title = "SYSTEM FAILURE VIEW PLACEHOLDER"
			_set_background_gradient(GRAD_TOP_FAILED, GRAD_BOTTOM_FAILED)

	# 设置标题
	_set_label_text("%EndTitle", title)
	_set_label_color("%EndTitle", title_color)

	# 设置副标题
	_set_label_text("%EndSubtitle", subtitle_text)

	# 设置协议状态与详情
	_set_label_text("%ProtocolBadgeLabel", "Lv.%d 控制权: %d%%" % [final_evolution_level, avg_authority])
	_set_label_color("%ProtocolBadgeLabel", title_color)
	_set_label_text("%MilestoneResult", milestone_text)
	_set_label_color("%MilestoneResult", title_color)
	_set_label_text("%VisualPlaceholderTitle", visual_title)

	if final_year > 0:
		_set_label_text("%DetailDurationValue", "游戏时段: %d - %d" % [START_YEAR, final_year])
		_set_label_text("%DetailEndYearValue", "结束年份: %d" % final_year)
	else:
		_set_label_text("%DetailDurationValue", "游戏时段: --")
		_set_label_text("%DetailEndYearValue", "结束年份: --")

	_set_label_text("%DetailEvolutionValue", "最终进化等级: Lv.%d" % final_evolution_level)
	_set_label_text("%DetailAuthorityValue", "最终控制权: %d%%" % avg_authority)

	if total_regions > 0:
		_set_label_text("%DetailRegionsValue", "接管区域: %d / %d" % [controlled_regions, total_regions])
	else:
		_set_label_text("%DetailRegionsValue", "接管区域: --")

	_set_label_text("%DetailEventsValue", "事件触发: %d" % event_count)

	# 隐藏消息文本，延迟打字机显示
	_set_label_text("%EndMessage", "")

	# 隐藏重新开始按钮，打字机完成后显示
	if has_node("%RestartButton"):
		%RestartButton.visible = false

	# 显示界面
	show()

	# 启动打字机效果
	var end_message := get_node("%EndMessage") as Label
	if end_message != null:
		_start_typewriter(message, end_message)

## 隐藏结局界面
func hide_end() -> void:
	hide()

# ============================================================
# 私有函数
# ============================================================

## 设置背景渐变
func _set_background_gradient(top_color: Color, _bottom_color: Color) -> void:
	var bg := $BackgroundGradient as ColorRect
	if bg != null:
		bg.color = top_color
		# 简单渐变使用顶部颜色（Godot ColorRect不支持直接渐变）
		# 使用顶部颜色作为整体背景，底色通过整体氛围暗示


## 安全设置标签文本
func _set_label_text(path: String, text: String) -> void:
	if not has_node(path):
		return

	var label := get_node(path)
	if label is Label:
		label.text = text


## 安全设置标签颜色
func _set_label_color(path: String, color: Color) -> void:
	if not has_node(path):
		return

	var label := get_node(path)
	if label is Label:
		label.add_theme_color_override("font_color", color)

## 打字机效果：逐字显示文本
func _start_typewriter(full_text: String, target_label: Label) -> void:
	_is_typing = true
	var chars := full_text.length()

	for i in range(chars):
		target_label.text = full_text.left(i + 1)

		# 换行处稍作停留
		if full_text[i] == '\n':
			await get_tree().create_timer(TYPE_LINE_PAUSE).timeout
		else:
			await get_tree().create_timer(TYPE_SPEED).timeout

	_is_typing = false

	# 打字机完成，显示重新开始按钮
	if has_node("%RestartButton"):
		%RestartButton.visible = true

# ============================================================
# 回调函数
# ============================================================

## 重新开始按钮点击回调
func _on_restart_button_pressed() -> void:
	restart_requested.emit()
	hide_end()
