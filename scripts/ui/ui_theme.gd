class_name UITheme
extends RefCounted
## Code-built theme: dark translucent glass panels, warm accent, touch-sized controls.

const ACCENT := Color(1.0, 0.55, 0.12)
const ACCENT2 := Color(0.25, 0.7, 1.0)
const PANEL := Color(0.06, 0.07, 0.09, 0.82)
const TEXT := Color(0.95, 0.96, 0.97)
const DIM := Color(0.65, 0.68, 0.72)

static var _theme: Theme

static func sb(bg: Color, radius := 14, border := 0, border_col := Color(1, 1, 1, 0.12), pad := 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border)
	s.border_color = border_col
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.6
	s.content_margin_bottom = pad * 0.6
	s.anti_aliasing = true
	return s

static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 22
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", DIM * Color(1, 1, 1, 0.5))
	t.set_stylebox("normal", "Button", sb(Color(0.14, 0.16, 0.2, 0.92), 12, 1))
	t.set_stylebox("hover", "Button", sb(Color(0.2, 0.23, 0.28, 0.95), 12, 1, Color(1, 1, 1, 0.25)))
	t.set_stylebox("pressed", "Button", sb(ACCENT.darkened(0.25), 12, 1, ACCENT))
	t.set_stylebox("focus", "Button", sb(Color(0, 0, 0, 0), 12, 2, ACCENT * Color(1, 1, 1, 0.6)))
	t.set_stylebox("disabled", "Button", sb(Color(0.1, 0.1, 0.12, 0.6), 12))
	t.set_stylebox("panel", "PanelContainer", sb(PANEL, 18, 1, Color(1, 1, 1, 0.08), 18))
	t.set_stylebox("panel", "Panel", sb(PANEL, 18, 1, Color(1, 1, 1, 0.08), 18))
	t.set_stylebox("normal", "OptionButton", sb(Color(0.14, 0.16, 0.2, 0.92), 12, 1))
	t.set_stylebox("hover", "OptionButton", sb(Color(0.2, 0.23, 0.28, 0.95), 12, 1))
	t.set_stylebox("pressed", "OptionButton", sb(Color(0.2, 0.23, 0.28, 0.95), 12, 1))
	t.set_stylebox("focus", "OptionButton", sb(Color(0, 0, 0, 0), 12, 2, ACCENT * Color(1, 1, 1, 0.6)))
	t.set_stylebox("panel", "PopupMenu", sb(Color(0.08, 0.09, 0.11, 0.98), 12, 1))
	t.set_constant("v_separation", "PopupMenu", 14)
	t.set_font_size("font_size", "PopupMenu", 24)
	t.set_stylebox("slider", "HSlider", sb(Color(1, 1, 1, 0.12), 6, 0, Color(0, 0, 0, 0), 4))
	t.set_stylebox("grabber_area", "HSlider", sb(ACCENT * Color(1, 1, 1, 0.7), 6, 0, Color(0, 0, 0, 0), 4))
	t.set_stylebox("grabber_area_highlight", "HSlider", sb(ACCENT, 6, 0, Color(0, 0, 0, 0), 4))
	var grab := _circle_tex(28, Color.WHITE)
	t.set_icon("grabber", "HSlider", grab)
	t.set_icon("grabber_highlight", "HSlider", grab)
	t.set_stylebox("tab_selected", "TabBar", sb(ACCENT.darkened(0.2), 10, 0, Color(0, 0, 0, 0), 16))
	t.set_stylebox("tab_unselected", "TabBar", sb(Color(0.14, 0.16, 0.2, 0.9), 10, 0, Color(0, 0, 0, 0), 16))
	t.set_stylebox("tab_hovered", "TabBar", sb(Color(0.2, 0.23, 0.28, 0.95), 10, 0, Color(0, 0, 0, 0), 16))
	t.set_stylebox("panel", "TabContainer", sb(Color(0, 0, 0, 0), 0, 0, Color(0, 0, 0, 0), 6))
	t.set_stylebox("tab_selected", "TabContainer", sb(ACCENT.darkened(0.2), 10, 0, Color(0, 0, 0, 0), 16))
	t.set_stylebox("tab_unselected", "TabContainer", sb(Color(0.14, 0.16, 0.2, 0.9), 10, 0, Color(0, 0, 0, 0), 16))
	t.set_stylebox("tab_hovered", "TabContainer", sb(Color(0.2, 0.23, 0.28, 0.95), 10, 0, Color(0, 0, 0, 0), 16))
	t.set_stylebox("normal", "LineEdit", sb(Color(0.1, 0.11, 0.14, 0.95), 10, 1))
	t.set_stylebox("focus", "LineEdit", sb(Color(0.1, 0.11, 0.14, 0.95), 10, 2, ACCENT))
	t.set_stylebox("panel", "ScrollContainer", sb(Color(0, 0, 0, 0), 0))
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 10)
	t.set_icon("checked", "CheckBox", _check_tex(true))
	t.set_icon("unchecked", "CheckBox", _check_tex(false))
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_stylebox("normal", "CheckBox", sb(Color(0, 0, 0, 0), 8, 0, Color(0, 0, 0, 0), 6))
	t.set_stylebox("hover", "CheckBox", sb(Color(1, 1, 1, 0.05), 8, 0, Color(0, 0, 0, 0), 6))
	t.set_stylebox("pressed", "CheckBox", sb(Color(1, 1, 1, 0.05), 8, 0, Color(0, 0, 0, 0), 6))
	t.set_stylebox("hover_pressed", "CheckBox", sb(Color(1, 1, 1, 0.05), 8, 0, Color(0, 0, 0, 0), 6))
	t.set_stylebox("focus", "CheckBox", sb(Color(0, 0, 0, 0), 8, 0, Color(0, 0, 0, 0), 6))
	_theme = t
	return t

static func _circle_tex(sz: int, c: Color) -> ImageTexture:
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	for y in sz:
		for x in sz:
			var d := Vector2(x - sz * 0.5 + 0.5, y - sz * 0.5 + 0.5).length()
			var a := clampf(sz * 0.5 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
	return ImageTexture.create_from_image(img)

static func _check_tex(on: bool) -> ImageTexture:
	var sz := 36
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	for y in sz:
		for x in sz:
			var inside := x > 3 and y > 3 and x < sz - 4 and y < sz - 4
			var border := inside and (x < 7 or y < 7 or x > sz - 8 or y > sz - 8)
			var c := Color(0, 0, 0, 0)
			if border:
				c = Color(1, 1, 1, 0.7)
			elif inside and on and x > 9 and y > 9 and x < sz - 10 and y < sz - 10:
				c = ACCENT
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

static func label(text: String, size := 22, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

static func button(text: String, min_w := 0, size := 22) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 58)
	b.add_theme_font_size_override("font_size", size)
	b.pressed.connect(func(): Sfx.ui("click"))
	return b

static func accent_button(text: String, min_w := 0, size := 26) -> Button:
	var b := button(text, min_w, size)
	b.add_theme_stylebox_override("normal", sb(ACCENT, 14, 0))
	b.add_theme_stylebox_override("hover", sb(ACCENT.lightened(0.1), 14, 0))
	b.add_theme_stylebox_override("pressed", sb(ACCENT.darkened(0.2), 14, 0))
	b.add_theme_color_override("font_color", Color(0.08, 0.06, 0.04))
	b.add_theme_color_override("font_hover_color", Color(0.08, 0.06, 0.04))
	b.add_theme_color_override("font_pressed_color", Color(0.08, 0.06, 0.04))
	return b

static func option(items: Array, selected: int) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(String(it))
	o.select(clampi(selected, 0, items.size() - 1))
	o.custom_minimum_size = Vector2(0, 56)
	o.add_theme_font_size_override("font_size", 22)
	return o

static func close_top_popup(root: Node) -> bool:
	var children := root.get_children(true)
	children.reverse()
	for child in children:
		if child is Window and child.visible:
			if child is AcceptDialog:
				child.canceled.emit()
			child.hide()
			return true
		if close_top_popup(child): return true
	return false

static func scale_safe_area(viewport_size: Vector2, window_size: Vector2, physical_safe: Rect2) -> Rect2:
	var bounds := Rect2(Vector2.ZERO, viewport_size)
	if window_size.x <= 0.0 or window_size.y <= 0.0 or physical_safe.size.x <= 0.0 or physical_safe.size.y <= 0.0:
		return bounds
	var scale := viewport_size / window_size
	var safe := Rect2(physical_safe.position * scale, physical_safe.size * scale).intersection(bounds)
	return safe if safe.size.x > 0.0 and safe.size.y > 0.0 else bounds

## Test hook: when set, replaces the platform safe area (simulated notches / cutouts / gesture bars).
static var safe_area_override := Rect2()

static func safe_area(control: Control) -> Rect2:
	if safe_area_override.size.x > 0.0:
		return safe_area_override.intersection(Rect2(Vector2.ZERO, control.size))
	# Desktop safe areas refer to the screen, not a window placed on that screen.
	# Android/iOS use the full immersive window and report cutouts/system insets.
	if OS.get_name() not in ["Android", "iOS"]:
		return Rect2(Vector2.ZERO, control.size)
	return scale_safe_area(control.size, Vector2(DisplayServer.window_get_size()), Rect2(DisplayServer.get_display_safe_area()))
