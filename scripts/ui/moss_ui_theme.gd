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


static func panel_style(
	background: Color = PANEL_BACKGROUND,
	border: Color = BORDER,
	border_width: int = 1,
	corner_radius: int = 2
) -> StyleBoxFlat:
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
) -> StyleBoxFlat:
	var style := panel_style(background, border, 1, 1)
	style.border_width_left = left_border_width
	style.content_margin_left = 16.0
	style.content_margin_top = 10.0
	style.content_margin_right = 16.0
	style.content_margin_bottom = 10.0
	return style


static func progress_background_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.085, 1.0)
	style.set_corner_radius_all(1)
	return style


static func progress_fill_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(1)
	return style
