class_name MossUITheme
extends RefCounted

const BACKGROUND: Color = Color("#03070c")
const PANEL_BACKGROUND: Color = Color(0.025, 0.055, 0.082, 0.94)
const PANEL_BACKGROUND_HOVER: Color = Color(0.04, 0.09, 0.12, 0.97)
const BORDER: Color = Color("#1e3444")
const BORDER_BRIGHT: Color = Color("#3a7180")
const TEXT_PRIMARY: Color = Color("#b8c7d6")
const TEXT_SECONDARY: Color = Color("#6e8294")
const ACCENT_CYAN: Color = Color("#73c9d3")
const ACCENT_GOLD: Color = Color("#bda66a")
const DANGER: Color = Color("#9d4d53")
const ORDER: Color = Color("#416fa3")
const HOPE: Color = Color("#71858b")
const AUTHORITY: Color = Color("#7e3f47")

const PANEL_TEXTURE: Texture2D = preload("res://assets/ui/texture_pack_01/panel_frame.svg")
const BUTTON_NORMAL_TEXTURE: Texture2D = preload("res://assets/ui/texture_pack_01/button_normal.svg")
const BUTTON_HOVER_TEXTURE: Texture2D = preload("res://assets/ui/texture_pack_01/button_hover.svg")
const BUTTON_PRESSED_TEXTURE: Texture2D = preload("res://assets/ui/texture_pack_01/button_pressed.svg")
const BUTTON_ACCENT_TEXTURE: Texture2D = preload("res://assets/ui/texture_pack_01/button_accent.svg")
const BUTTON_DISABLED_TEXTURE: Texture2D = preload("res://assets/ui/texture_pack_01/button_disabled.svg")
const METER_TRACK_TEXTURE: Texture2D = preload("res://assets/ui/texture_pack_01/meter_track.svg")


static func panel_style(
	background: Color = PANEL_BACKGROUND,
	border: Color = BORDER,
	border_width: int = 1,
	corner_radius: int = 2
) -> StyleBox:
	if background == PANEL_BACKGROUND and border == BORDER and border_width == 1 and corner_radius == 2:
		return _panel_texture_style()
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(corner_radius)
	style.content_margin_left = 10.0
	style.content_margin_top = 8.0
	style.content_margin_right = 10.0
	style.content_margin_bottom = 8.0
	return style


static func button_style(
	background: Color,
	border: Color,
	left_border_width: int = 1
) -> StyleBox:
	var texture: Texture2D = null
	if border == BORDER_BRIGHT:
		texture = BUTTON_ACCENT_TEXTURE
	elif border == ACCENT_CYAN:
		texture = BUTTON_PRESSED_TEXTURE if background.r < 0.025 else BUTTON_HOVER_TEXTURE
	elif border == BORDER:
		texture = BUTTON_NORMAL_TEXTURE
	elif background.r < 0.02 and background.g < 0.04 and background.b < 0.05:
		texture = BUTTON_DISABLED_TEXTURE
	if texture != null:
		return _button_texture_style(texture)
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(1)
	style.border_width_left = left_border_width
	style.content_margin_left = 16.0
	style.content_margin_top = 10.0
	style.content_margin_right = 16.0
	style.content_margin_bottom = 10.0
	return style



static func progress_background_style() -> StyleBox:
	var style := _texture_style(METER_TRACK_TEXTURE, 5.0, 0.0, 0.0)
	return style


static func progress_fill_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(1)
	return style


static func _panel_texture_style() -> StyleBoxTexture:
	return _texture_style(PANEL_TEXTURE, 18.0, 10.0, 8.0)


static func _button_texture_style(texture: Texture2D) -> StyleBoxTexture:
	return _texture_style(texture, 12.0, 16.0, 10.0)


static func _texture_style(
	texture: Texture2D,
	texture_margin: float,
	content_margin: float,
	content_margin_vertical: float
) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.texture_margin_left = texture_margin
	style.texture_margin_top = texture_margin
	style.texture_margin_right = texture_margin
	style.texture_margin_bottom = texture_margin
	style.draw_center = true
	style.content_margin_left = content_margin
	style.content_margin_top = content_margin_vertical
	style.content_margin_right = content_margin
	style.content_margin_bottom = content_margin_vertical
	return style
