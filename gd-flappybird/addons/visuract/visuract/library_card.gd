@tool
extends Button

var node_type := ""
## Set on Scene Library cards. Dragged as a file, so the Scene dock
## instances it just like a drop from the FileSystem dock.
var scene_path := ""

var _tween: Tween


func _ready() -> void:
	resized.connect(_center_pivot)
	_center_pivot()
	mouse_entered.connect(_wiggle)
	mouse_exited.connect(_settle)


## Scale and rotation both pivot from the middle of the card.
func _center_pivot() -> void:
	pivot_offset = size / 2.0


func _wiggle() -> void:
	if disabled:
		return
	z_index = 1
	if _tween:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", Vector2(1.07, 1.07), 0.12)
	_tween.parallel().tween_property(self, "rotation", deg_to_rad(3.0), 0.08)
	_tween.tween_property(self, "rotation", deg_to_rad(-3.0), 0.10)
	_tween.tween_property(self, "rotation", deg_to_rad(1.5), 0.08)
	_tween.tween_property(self, "rotation", 0.0, 0.08)


func _settle() -> void:
	z_index = 0
	if _tween:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", Vector2.ONE, 0.10)
	_tween.parallel().tween_property(self, "rotation", 0.0, 0.10)


func _get_drag_data(_at_position: Vector2) -> Variant:
	if disabled:
		return null
	set_drag_preview(_make_ghost())
	if scene_path != "":
		return {"type": "files", "files": [scene_path]}
	return {"visuract_type": node_type}


## A see-through copy of this card, centred on the cursor.
func _make_ghost() -> Control:
	var ghost := Button.new()
	ghost.text = text
	ghost.alignment = alignment
	ghost.icon = icon
	ghost.expand_icon = expand_icon
	ghost.icon_alignment = icon_alignment
	ghost.vertical_icon_alignment = vertical_icon_alignment
	ghost.custom_minimum_size = size
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE

	for state in ["normal", "hover", "pressed"]:
		if has_theme_stylebox_override(state):
			ghost.add_theme_stylebox_override(state, get_theme_stylebox(state))
	for item in ["font_color", "font_hover_color", "font_pressed_color"]:
		if has_theme_color_override(item):
			ghost.add_theme_color_override(item, get_theme_color(item))
	if has_theme_font_override("font"):
		ghost.add_theme_font_override("font", get_theme_font("font"))
	if has_theme_font_size_override("font_size"):
		ghost.add_theme_font_size_override("font_size", get_theme_font_size("font_size"))

	ghost.modulate = Color(1.0, 1.0, 1.0, 0.65)
	ghost.position = -size / 2.0

	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(ghost)
	return holder
