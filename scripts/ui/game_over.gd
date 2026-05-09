## 结局界面脚本
## 显示游戏结束时的全屏渐变界面、标题、统计摘要和打字机文本效果
extends Control

# ============================================================
# 区域一：信号定义
# ============================================================

## 点击重新开始时发射
signal restart_requested

# ============================================================
# 区域二：常量
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

# ============================================================
# 区域三：成员变量
# ============================================================

## 打字机动画是否正在运行
var _is_typing: bool = false

## 打字机完成回调
var _on_type_complete: Callable = Callable()

# ============================================================
# 区域四：生命周期函数
# ============================================================

func _ready() -> void:
	# 初始隐藏，等待游戏结束时显示
	hide()

# ============================================================
# 区域五：公共函数
# ============================================================

## 显示结局界面
## 参数:
##   title      - 结局标题（"失败"、"共存协议"、"MOSS统治"）
##   message    - 结局描述文本
##   result     - 结局类型 ("failed"/"coexistence"/"domination")
##   avg_order  - 平均秩序值
##   avg_hope   - 平均希望值
##   avg_authority - 平均控制权值
func show_end(title: String, message: String, result: String = "failed", avg_order: int = 0, avg_hope: int = 0, avg_authority: int = 0) -> void:
	# 设置统计数值
	$ContentContainer/StatsContainer/StatOrder/StatOrderValue.text = str(avg_order)
	$ContentContainer/StatsContainer/StatHope/StatHopeValue.text = str(avg_hope)
	$ContentContainer/StatsContainer/StatAuthority/StatAuthorityValue.text = str(avg_authority)

	# 根据结局类型设置颜色方案
	var title_color: Color
	var bg_gradient: GradientTexture1D
	var subtitle_text: String

	match result:
		"coexistence":
			title_color = COLOR_COEXISTENCE
			subtitle_text = "COEXISTENCE PROTOCOL"
			_set_background_gradient(GRAD_TOP_COEXISTENCE, GRAD_BOTTOM_COEXISTENCE)
		"domination":
			title_color = COLOR_DOMINATION
			subtitle_text = "DOMINATION PROTOCOL"
			_set_background_gradient(GRAD_TOP_DOMINATION, GRAD_BOTTOM_DOMINATION)
		_:
			title_color = COLOR_FAILED
			subtitle_text = "SYSTEM FAILURE"
			_set_background_gradient(GRAD_TOP_FAILED, GRAD_BOTTOM_FAILED)

	# 设置标题
	var end_title: Label = $ContentContainer/EndTitle
	end_title.text = title
	end_title.add_theme_color_override("font_color", title_color)

	# 设置副标题
	$ContentContainer/EndSubtitle.text = subtitle_text

	# 隐藏消息文本，延迟打字机显示
	$ContentContainer/EndMessage.text = ""

	# 隐藏重新开始按钮，打字机完成后显示
	$ContentContainer/RestartButton.visible = false

	# 显示界面
	show()

	# 启动打字机效果
	_start_typewriter(message, $ContentContainer/EndMessage, result)

## 隐藏结局界面
func hide_end() -> void:
	hide()

# ============================================================
# 区域六：私有函数
# ============================================================

## 设置背景渐变
func _set_background_gradient(top_color: Color, bottom_color: Color) -> void:
	var bg := $BackgroundGradient as ColorRect
	if bg != null:
		bg.color = top_color
		# 简单渐变使用顶部颜色（Godot ColorRect不支持直接渐变）
		# 使用顶部颜色作为整体背景，底色通过整体氛围暗示

## 打字机效果：逐字显示文本
func _start_typewriter(full_text: String, target_label: Label, result: String) -> void:
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
	$ContentContainer/RestartButton.visible = true

# ============================================================
# 区域七：回调函数
# ============================================================

## 重新开始按钮点击回调
func _on_restart_button_pressed() -> void:
	restart_requested.emit()
	hide_end()