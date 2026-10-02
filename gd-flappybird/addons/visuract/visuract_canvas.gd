@tool
extends GraphEdit

signal node_dropped(type: String, graph_position: Vector2)
signal node_right_clicked(node: GraphNode)
signal empty_area_clicked(at_position: Vector2)


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("visuract_type")


func _drop_data(at_position: Vector2, data: Variant) -> void:
	node_dropped.emit(data.visuract_type, (at_position + scroll_offset) / zoom)


## GraphEdit intercepts mouse events for its GraphNodes, so right-clicks are
## caught here at _input level and hit-tested manually.
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventKey:
		_copy_paste_keys(event)
		return
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed):
		return
	if not get_global_rect().has_point(event.global_position):
		return

	for child in get_children():
		if child is GraphNode and child.get_global_rect().has_point(event.global_position):
			node_right_clicked.emit(child)
			get_viewport().set_input_as_handled()
			return

	empty_area_clicked.emit(event.global_position - global_position)
	get_viewport().set_input_as_handled()


## GraphEdit only sees Ctrl+C / Ctrl+V while it has focus, which it loses
## when you switch node or scene tab. So catch them whenever the mouse is over
## the canvas and you aren't typing in a field.
func _copy_paste_keys(event: InputEventKey) -> void:
	if not event.pressed or event.echo or not event.is_command_or_control_pressed():
		return
	if not get_global_rect().has_point(get_global_mouse_position()):
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	match event.keycode:
		KEY_C:
			copy_nodes_request.emit()
		KEY_V:
			paste_nodes_request.emit()
		_:
			return
	get_viewport().set_input_as_handled()


## Zooms and scrolls so every block is in view. Never zooms in past 100%.
func frame_nodes() -> void:
	await get_tree().process_frame
	var bounds := Rect2()
	var found := false
	for child in get_children():
		if child is GraphNode:
			var rect := Rect2(child.position_offset, child.get_combined_minimum_size())
			bounds = bounds.merge(rect) if found else rect
			found = true
	if not found or size == Vector2.ZERO:
		return
	bounds = bounds.grow(40.0)
	var fit := size / bounds.size
	zoom = clampf(minf(fit.x, fit.y), zoom_min, 1.0)
	## Wait for the scroll range to catch up with the new zoom.
	await get_tree().process_frame
	scroll_offset = bounds.get_center() * zoom - size / 2.0
