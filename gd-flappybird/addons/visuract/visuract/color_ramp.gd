@tool
extends Control
const Lang := preload("res://addons/visuract/visuract_lang.gd")

## Click to add a color, drag a handle to move it, click a handle to change
## its color, right-click a handle to remove it.

signal value_changed

const BAR_HEIGHT := 14.0
const HANDLE := 6.0

var value: Dictionary:
	get:
		return {"offsets": _offsets.duplicate(), "colors": _colors.duplicate()}
	set(v):
		_offsets = Array(v.get("offsets", [0.0, 1.0]))
		_colors = Array(v.get("colors", [Color("ff6ec7"), Color("4a8cff")]))
		queue_redraw()

var _offsets := [0.0, 1.0]
var _colors := [Color("ff6ec7"), Color("4a8cff")]
var _dragging := -1
var _moved := false
var _editing := -1
var _popup: PopupPanel
var _picker: ColorPicker


func _ready() -> void:
	custom_minimum_size = Vector2(150, BAR_HEIGHT + HANDLE * 2)
	tooltip_text = Lang.t("Click to add a color, drag to move, click a handle to change it, right-click to remove.")
	_popup = PopupPanel.new()
	_picker = ColorPicker.new()
	_picker.color_changed.connect(_on_color_changed)
	_popup.add_child(_picker)
	add_child(_popup)


func _gradient() -> Gradient:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array(_offsets)
	gradient.colors = PackedColorArray(_colors)
	return gradient


func _draw() -> void:
	var gradient := _gradient()
	for x in int(size.x):
		draw_rect(Rect2(x, 0, 1, BAR_HEIGHT), gradient.sample(x / size.x))
	for i in _offsets.size():
		var x: float = _offsets[i] * size.x
		var handle := Rect2(x - HANDLE * 0.5, BAR_HEIGHT - 2, HANDLE, HANDLE * 2)
		draw_rect(handle, _colors[i])
		draw_rect(handle, Color.WHITE if i == _dragging else Color.BLACK, false, 1.0)


func _handle_at(x: float) -> int:
	for i in _offsets.size():
		if absf(_offsets[i] * size.x - x) <= HANDLE:
			return i
	return -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var i := _handle_at(event.position.x)
		if event.button_index == MOUSE_BUTTON_RIGHT and i >= 0 and _offsets.size() > 1:
			_offsets.remove_at(i)
			_colors.remove_at(i)
			_changed()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if i < 0:
				var t := clampf(event.position.x / size.x, 0.0, 1.0)
				_colors.append(_gradient().sample(t))
				_offsets.append(t)
				i = _offsets.size() - 1
				_changed()
			_dragging = i
			_moved = false
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and _dragging >= 0:
		if _moved:
			value_changed.emit()
		else:
			_open_picker(_dragging)
		_dragging = -1
		queue_redraw()
	elif event is InputEventMouseMotion and _dragging >= 0:
		_offsets[_dragging] = clampf(event.position.x / size.x, 0.0, 1.0)
		_moved = true
		queue_redraw()


func _open_picker(i: int) -> void:
	_editing = i
	_picker.color = _colors[i]
	_popup.popup(Rect2i(DisplayServer.mouse_get_position(), Vector2i.ZERO))


func _on_color_changed(color: Color) -> void:
	if _editing >= 0 and _editing < _colors.size():
		_colors[_editing] = color
		_changed()


func _changed() -> void:
	queue_redraw()
	value_changed.emit()
