@tool
extends PanelContainer
const Lang := preload("res://addons/visuract/visuract_lang.gd")

## Emitted after every edit, with the whole dialogue.
signal changed(data: Dictionary)

const Slot := preload("res://addons/visuract/param_slot.gd")
const TINT := Color("4b8fe0")
## Width as a fraction of height, for a standing, card-like panel.
const ASPECT := 0.72
const FRESH := {
	"sections": [{"lines": [{"text": "", "duration": 2.0, "delay": 0.5}], "transition_delay": 1.0}],
	"defaults": [],
}

## Callable(filter: String) -> Array of res:// paths, set by the main screen.
var file_options: Callable
var _data := {}
var _list: VBoxContainer
## The Label picked on the Dialogue node, styled live in the edited scene.
var _text_label: Label
var _style_button: Button
var _style_popup: PopupPanel
var _preview_toggle: CheckBox
var _preview_box: CenterContainer
var _preview: Label
## Text of the last focused text field.
var _preview_text := ""


func _ready() -> void:
	visible = false
	resized.connect(func():
		custom_minimum_size.x = minf(size.y * ASPECT, get_parent_area_size().x))

	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.13, 0.14, 0.17, 0.98)
	box.border_color = TINT
	box.set_border_width_all(3)
	box.set_corner_radius_all(14)
	box.set_content_margin_all(16)
	add_theme_stylebox_override("panel", box)

	var root := VBoxContainer.new()
	add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = Lang.t("Dialogue")
	title.add_theme_font_size_override("font_size", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_style_button = Button.new()
	_style_button.text = Lang.t("Style\u2026")
	_style_button.pressed.connect(_open_style)
	header.add_child(_style_button)
	var done := Button.new()
	done.text = Lang.t("Done")
	done.pressed.connect(hide)
	header.add_child(done)

	_preview_toggle = CheckBox.new()
	_preview_toggle.text = Lang.t("Show Preview")
	_preview_toggle.toggled.connect(func(_on): _update_preview())
	root.add_child(_preview_toggle)

	## Beside the window rather than inside it, so it has room for real size.
	_preview_box = CenterContainer.new()
	_preview_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_box.visible = false
	_preview = Label.new()
	_preview_box.add_child(_preview)
	_add_preview_box.call_deferred()
	visibility_changed.connect(_update_preview)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)


func open(data: Dictionary, label: Label = null) -> void:
	_data = data
	_text_label = label
	_style_button.disabled = label == null
	_style_button.tooltip_text = "" if label else Lang.t("Pick a Label on the Dialogue node first.")
	_preview_text = label.text if label else ""
	_rebuild()
	show()


## Structural edits rebuild the list; typing only updates the data, so the
## text field keeps focus.
func _edited(structural: bool) -> void:
	if structural:
		_rebuild()
	changed.emit(_data)


func _rebuild() -> void:
	for child in _list.get_children():
		child.queue_free()

	var sections: Array = _data.get_or_add("sections", [])
	for i in sections.size():
		_list.add_child(_section_box(sections, i))
	_list.add_child(_add_button("+ Add Section", func():
		sections.append({"lines": [FRESH.sections[0].lines[0].duplicate()], "transition_delay": 1.0})))

	var heading := Label.new()
	heading.text = Lang.t("DEFAULT RESPONSES")
	heading.tooltip_text = Lang.t("Cycled through, one per run, once every section has been shown.")
	heading.mouse_filter = Control.MOUSE_FILTER_PASS
	heading.add_theme_color_override("font_color", TINT)
	_list.add_child(heading)
	var defaults: Array = _data.get_or_add("defaults", [])
	for i in defaults.size():
		_list.add_child(_line_row(defaults, i, false))
	_list.add_child(_add_button("+ Add Response", func():
		defaults.append({"text": "", "duration": 2.0})))


func _section_box(sections: Array, index: int) -> Control:
	var section: Dictionary = sections[index]
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(1, 1, 1, 0.05)
	box.set_corner_radius_all(8)
	box.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", box)
	var column := VBoxContainer.new()
	panel.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.text = Lang.t("Section %d") % (index + 1)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_remove_button(sections, index))

	var lines: Array = section.get_or_add("lines", [])
	for i in lines.size():
		column.add_child(_line_row(lines, i, true))
	column.add_child(_add_button("+ Add Text", func():
		lines.append(FRESH.sections[0].lines[0].duplicate())))

	var transition := HBoxContainer.new()
	transition.add_child(_label("Section Transition Delay"))
	transition.add_child(_seconds(section, "transition_delay"))
	transition.tooltip_text = Lang.t("How long before the next section can start.")
	column.add_child(transition)
	return panel


func _line_row(lines: Array, index: int, with_delay: bool) -> Control:
	var line: Dictionary = lines[index]
	var row := VBoxContainer.new()
	var top := HBoxContainer.new()
	row.add_child(top)
	var text := TextEdit.new()
	text.text = String(line.get("text", ""))
	text.placeholder_text = Lang.t("Write text here...")
	text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.ready.connect(func():
		text.custom_minimum_size.y = text.get_line_height() * 3 + text.get_theme_stylebox("normal").get_minimum_size().y)
	text.focus_entered.connect(func():
		_preview_text = text.text
		_update_preview())
	text.text_changed.connect(func():
		line["text"] = text.text
		_preview_text = text.text
		_update_preview()
		_edited(false))
	top.add_child(text)
	top.add_child(_remove_button(lines, index))

	var timing := HBoxContainer.new()
	row.add_child(timing)
	timing.add_child(_label("Duration"))
	timing.add_child(_seconds(line, "duration"))
	if with_delay:
		timing.add_child(_label("Delay"))
		timing.add_child(_seconds(line, "delay"))
	return row


func _seconds(target: Dictionary, key: String) -> SpinBox:
	var spin := SpinBox.new()
	spin.max_value = 600.0
	spin.step = 0.1
	spin.suffix = "s"
	spin.custom_minimum_size.x = 80
	spin.value = target.get(key, 0.0)
	spin.value_changed.connect(func(v):
		target[key] = v
		_edited(false))
	return spin


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = Lang.t(text)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	return label


func _add_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = Lang.t(text)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.pressed.connect(func():
		action.call()
		_edited(true))
	return button


func _remove_button(owner_list: Array, index: int) -> Button:
	var button := Button.new()
	button.text = "\u2715"
	button.flat = true
	button.tooltip_text = Lang.t("Remove")
	button.pressed.connect(func():
		owner_list.remove_at(index)
		_edited(true))
	return button


## Styles the picked Label itself, so the scene view already shows how the
## text will look in the game.
func _open_style() -> void:
	if _style_popup:
		_style_popup.queue_free()
	_style_popup = PopupPanel.new()
	add_child(_style_popup)
	var grid := GridContainer.new()
	grid.columns = 2
	_style_popup.add_child(grid)

	## Own copies, so restyling one placed prefab never restyles the others.
	var settings := LabelSettings.new()
	if _text_label.label_settings:
		settings = _text_label.label_settings.duplicate() as LabelSettings
	_text_label.label_settings = settings
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0, 0, 0, 0.6)
	panel.set_corner_radius_all(8)
	panel.set_content_margin_all(10)
	var has_panel := _text_label.has_theme_stylebox_override("normal")
	if has_panel and _text_label.get_theme_stylebox("normal") is StyleBoxFlat:
		panel = _text_label.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
		_text_label.add_theme_stylebox_override("normal", panel)

	_style_row(grid, "Text Size", _style_number(settings.font_size, func(v): settings.font_size = maxi(1, int(v))))
	_style_row(grid, "Text Color", _style_color(settings.font_color, func(c): settings.font_color = c))
	_style_row(grid, "Outline Size", _style_number(settings.outline_size, func(v): settings.outline_size = int(v)))
	_style_row(grid, "Outline Color", _style_color(settings.outline_color, func(c): settings.outline_color = c))
	_style_row(grid, "Shadow Size", _style_number(settings.shadow_size, func(v): settings.shadow_size = int(v)))
	_style_row(grid, "Shadow Offset", _style_number(settings.shadow_offset.x, func(v): settings.shadow_offset = Vector2(v, v)))
	_style_row(grid, "Shadow Color", _style_color(settings.shadow_color, func(c): settings.shadow_color = c))

	var toggle := CheckBox.new()
	toggle.button_pressed = has_panel
	toggle.toggled.connect(func(on):
		if on:
			_text_label.add_theme_stylebox_override("normal", panel)
		else:
			_text_label.remove_theme_stylebox_override("normal")
		_style_changed())
	_style_row(grid, "Panel Behind Text", toggle)
	_style_row(grid, "Panel Color", _style_color(panel.bg_color, func(c): panel.bg_color = c))

	var font := Slot.new()
	font.kind = "file"
	font.value = settings.font.resource_path if settings.font else ""
	font.options = ["(default font)"] + file_options.call("ttf,otf,woff,woff2,fnt")
	font.custom_minimum_size.x = 150
	font.value_changed.connect(func():
		settings.font = load(font.value) if font.value.begins_with("res://") else null
		_style_changed())
	_style_row(grid, "Font", font)

	var at := _style_button.get_screen_position() + Vector2(0, _style_button.size.y)
	_style_popup.popup(Rect2i(Vector2i(at), Vector2i.ZERO))
	_update_preview()


func _style_row(grid: GridContainer, text: String, field: Control) -> void:
	grid.add_child(_label(text))
	grid.add_child(field)


func _style_number(value: float, apply: Callable) -> SpinBox:
	var spin := SpinBox.new()
	spin.max_value = 128
	spin.value = value
	spin.value_changed.connect(func(v):
		apply.call(v)
		_style_changed())
	return spin


func _style_color(value: Color, apply: Callable) -> ColorPickerButton:
	var swatch := ColorPickerButton.new()
	swatch.custom_minimum_size.x = 80
	swatch.color = value

	## Just the colour square, hex field and an alpha slider. The built-in
	## sliders are hidden as a group, so alpha gets its own.
	var picker := swatch.get_picker()
	picker.sliders_visible = false
	picker.color_modes_visible = false
	picker.sampler_visible = false
	picker.presets_visible = false
	var alpha_row := HBoxContainer.new()
	alpha_row.add_child(_label("Alpha"))
	var alpha := HSlider.new()
	alpha.max_value = 1.0
	alpha.step = 0.01
	alpha.value = value.a
	alpha.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	alpha_row.add_child(alpha)
	picker.add_child(alpha_row)

	var changed := func(c: Color):
		apply.call(c)
		_style_changed()
	swatch.color_changed.connect(func(c):
		alpha.set_value_no_signal(c.a)
		changed.call(c))
	alpha.value_changed.connect(func(a):
		var c := swatch.color
		c.a = a
		swatch.color = c
		changed.call(c))
	return swatch


func _style_changed() -> void:
	EditorInterface.mark_scene_as_unsaved()
	_update_preview()


func _add_preview_box() -> void:
	get_parent().add_child(_preview_box)
	get_parent().move_child(_preview_box, get_index())


## Shows the focused text with the picked Label's own style, at real size.
func _update_preview() -> void:
	_preview_box.visible = visible and _preview_toggle.button_pressed
	if not _preview_box.visible:
		return
	_preview.text = _preview_text
	_preview.remove_theme_stylebox_override("normal")
	if _text_label == null:
		_preview.label_settings = null
		return
	_preview.label_settings = _text_label.label_settings
	if _text_label.has_theme_stylebox_override("normal"):
		_preview.add_theme_stylebox_override("normal", _text_label.get_theme_stylebox("normal"))
	_preview.custom_minimum_size.x = _text_label.size.x
	_preview.autowrap_mode = _text_label.autowrap_mode
	_preview.horizontal_alignment = _text_label.horizontal_alignment
	_preview.vertical_alignment = _text_label.vertical_alignment
