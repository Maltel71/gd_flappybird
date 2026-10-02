@tool
extends Control

const Library := preload("res://addons/visuract/node_library.gd")
const RUNTIME := preload("res://addons/visuract/visuract_runtime.gd")
const Canvas := preload("res://addons/visuract/visuract_canvas.gd")
const Card := preload("res://addons/visuract/library_card.gd")
const Slot := preload("res://addons/visuract/param_slot.gd")
const ColorRamp := preload("res://addons/visuract/color_ramp.gd")
const SceneLibrary := preload("res://addons/visuract/scene_library.gd")
const Lang := preload("res://addons/visuract/visuract_lang.gd")
const DialogueEditor := preload("res://addons/visuract/dialogue_editor.gd")
const GRAPH_DIR := "res://visuract/graphs"
const LIBRARY_WIDTH := 260
const HIGHLIGHT := Color(0.75, 0.45, 1.0)
const REMOVE_TINT := Color("a05c5c")
const SAVE_TINT := Color("5c7ca0")
const GREY_TINT := Color("5a5a5a")
const TAB_BORDER := Color(0.85, 0.85, 0.85)
const TAB_GROW := Vector2(1.08, 1.08)
const NO_ACTIONS := "(no input actions yet)"
const NO_SIGNALS := "(no signal names yet)"
const NO_ANIMATIONS := "(no animations found)"
const NONE_OPTION := "(none)"
const TOUCHER_OPTION := "(what touched me)"
const NO_VARIABLES := "(nothing remembered yet)"
const SCENE_PLACEMENT := ["offset_x", "offset_y", "random_x", "random_y"]
const SECTION_BORDER := Color(1, 1, 1, 0.18)

enum { MENU_DUPLICATE, MENU_DELETE, MENU_COPY, MENU_PASTE = 100, MENU_NOTE }

const NOTE_TYPE := "Note"
const NOTE_COLOR := Color("f5db52")
const NOTE_FONT_SIZE := 52
const NOTE_EDGE := 16.0
const NOTE_MIN_SIZE := Vector2(180, 90)

var _graph: Control
var _library_list: VBoxContainer
var _library_hint: Label
var _target_label: Label
var _attach_button: Button
var _attach_tween: Tween
var _save_button: Button
var _language_button: MenuButton
var _save_tween: Tween
var _confirm: ConfirmationDialog
var _scene_library: Control
var _library_panel: Control
var _status := "No node attached."
var _highlighted_item: TreeItem
var _shimmer_time := 0.0
var _node_menu: PopupMenu
var _add_menu: PopupMenu
var _menu_types := {}
var _spawn_position := Vector2.ZERO
var _target: Node
var _graph_res: VisuractGraph
var _graph_path := ""
var _loading := false
var _spawn_offset := Vector2(40, 40)
var _next_id := 0
var _dialogue_editor: PanelContainer
## Copied blocks, kept while switching nodes so they can be pasted into
## another graph. Links are [from_index, to_index] into the clipboard.
var _clipboard: Array = []
var _clipboard_links: Array = []
## The Edit Dialogue button whose node the editor is showing.
var _dialogue_button: Button
var undo_redo: EditorUndoRedoManager
## The graph as it was after the last recorded change.
var _last_state := {}


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	## Godot would otherwise run our labels through the editor translations.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	Lang.language = String(EditorInterface.get_editor_settings().get_project_metadata("visuract", "language", Lang.ENGLISH))
	_build_ui()

	EditorInterface.get_selection().selection_changed.connect(_on_selection_changed)
	get_tree().node_added.connect(_on_scene_tree_changed)
	get_tree().node_removed.connect(_on_scene_tree_changed)
	visibility_changed.connect(_on_selection_changed)


## Remembers the choice and builds the whole panel again in that language.
func _set_language(language: String) -> void:
	if language == Lang.language:
		return
	Lang.language = language
	EditorInterface.get_editor_settings().set_project_metadata("visuract", "language", language)
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_target = null
	_graph_res = null
	_graph_path = ""
	_build_ui()
	_on_selection_changed()


func _build_ui() -> void:
	_status = Lang.t("No node attached.")

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	root.add_child(_build_toolbar())
	_style_save_button(false)
	var font := _save_button.get_theme_font("font")
	var font_size := _save_button.get_theme_font_size("font_size")
	_save_button.custom_minimum_size.x = font.get_string_size(Lang.t("\u2715  Remove from Selected Node"), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 20

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	_graph = Canvas.new()
	_graph.right_disconnects = true
	_graph.show_grid = true
	_graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_graph)
	_graph.node_dropped.connect(_make_graph_node)
	_graph.delete_nodes_request.connect(_delete_nodes)
	_graph.duplicate_nodes_request.connect(_duplicate_selected)
	_graph.copy_nodes_request.connect(_copy_selected)
	_graph.paste_nodes_request.connect(func(): _paste((_graph.get_local_mouse_position() + _graph.scroll_offset) / _graph.zoom))
	_graph.empty_area_clicked.connect(_on_empty_area_clicked)
	_graph.node_right_clicked.connect(_on_node_right_clicked)
	_graph.end_node_move.connect(_autosave)
	_graph.connection_request.connect(_on_connection_request)
	_graph.disconnection_request.connect(_on_disconnection_request)

	_scene_library = SceneLibrary.new()
	_scene_library.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scene_library.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scene_library.visible = false
	body.add_child(_scene_library)

	_build_library_panel(body)
	_populate_library()

	## Takes over the workspace while open, like the scene library.
	_dialogue_editor = DialogueEditor.new()
	_dialogue_editor.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_CENTER
	_dialogue_editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dialogue_editor.changed.connect(_on_dialogue_changed)
	_dialogue_editor.file_options = _file_options
	body.add_child(_dialogue_editor)
	_dialogue_editor.visibility_changed.connect(_on_dialogue_visibility_changed)
	_build_menus()

	_confirm = ConfirmationDialog.new()
	_confirm.title = Lang.t("Remove Visuract")
	_confirm.ok_button_text = Lang.t("Remove")
	_confirm.confirmed.connect(_detach)
	add_child(_confirm)


## Follow the Scene dock: show the selected node's graph, or nothing at all
## when it has no Visuract script.
func _on_selection_changed() -> void:
	if not is_visible_in_tree():
		return


	var selected := EditorInterface.get_selection().get_selected_nodes()
	if selected.is_empty():
		_target = null
		_clear_canvas()
		_set_status(Lang.t("Select a node in the scene."))
		_populate_library()
		_refresh_attach_button()
		return

	var node: Node = selected[0]
	if is_instance_valid(_target) and node == _target:
		_refresh_attach_button()
		return

	## Write whatever is on the canvas before letting go of it.
	if _graph_res != null and not _loading:
		_on_save_pressed()

	_target = node
	var existing = node.get("graph") if node.get_script() == RUNTIME else null
	if existing is VisuractGraph:
		_graph_res = existing
		_graph_path = existing.resource_path
		_load_into_canvas()
		_set_status(Lang.t("Showing: %s  (%d blocks)") % [node.name, _graph_res.nodes.size()])
		if _is_instance(node) and _source_graph(node) != existing:
			_set_status(Lang.t("%s  \u26a0 overrides %s - revert Graph in the Inspector") % [_status, node.scene_file_path.get_file()])
	else:
		_clear_canvas()
		_set_status(Lang.t("%s has no Visuract script yet.") % node.name)
	_populate_library()
	_refresh_attach_button()


## Faint blue at rest, full blue while hovered.
func _style_save_button(hovering: bool) -> void:
	var tint := SAVE_TINT if hovering else SAVE_TINT.darkened(0.45)
	for state in ["normal", "hover", "pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color = tint if state == "normal" else tint.lightened(0.12)
		box.set_corner_radius_all(4)
		box.content_margin_left = 10
		box.content_margin_right = 10
		box.content_margin_top = 4
		box.content_margin_bottom = 4
		_save_button.add_theme_stylebox_override(state, box)
	for item in ["font_color", "font_hover_color", "font_pressed_color"]:
		if hovering:
			_save_button.add_theme_color_override(item, Color(0.07, 0.10, 0.14))
		else:
			_save_button.remove_theme_color_override(item)


## Plain grey, so it sits quietly next to the colored buttons.
func _style_language_button() -> void:
	for state in ["normal", "hover", "pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color = GREY_TINT if state == "normal" else GREY_TINT.lightened(0.12)
		box.set_corner_radius_all(4)
		box.content_margin_left = 10
		box.content_margin_right = 10
		box.content_margin_top = 4
		box.content_margin_bottom = 4
		_language_button.add_theme_stylebox_override(state, box)


## Same grow-and-wiggle as the attach button.
func _animate_save_button(hovering: bool) -> void:
	_save_button.pivot_offset = _save_button.size / 2.0
	if _save_tween:
		_save_tween.kill()
	_save_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_style_save_button(hovering)
	if not hovering:
		_save_tween.tween_property(_save_button, "scale", Vector2.ONE, 0.10)
		_save_tween.parallel().tween_property(_save_button, "rotation", 0.0, 0.10)
		return

	_save_tween.tween_property(_save_button, "scale", Vector2(1.07, 1.07), 0.12)
	_save_tween.parallel().tween_property(_save_button, "rotation", deg_to_rad(3.0), 0.08)
	_save_tween.tween_property(_save_button, "rotation", deg_to_rad(-3.0), 0.10)
	_save_tween.tween_property(_save_button, "rotation", deg_to_rad(1.5), 0.08)
	_save_tween.tween_property(_save_button, "rotation", 0.0, 0.08)


## Squash on click, then spring back past its size and settle.
func _punch_save_button() -> void:
	_save_button.pivot_offset = _save_button.size / 2.0
	if _save_tween:
		_save_tween.kill()
	_save_tween = create_tween()
	_save_tween.tween_property(_save_button, "scale", Vector2(0.88, 0.88), 0.06).set_trans(Tween.TRANS_SINE)
	_save_tween.tween_property(_save_button, "scale", Vector2(1.07, 1.07), 0.18).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## Grows and wiggles to add, shrinks to remove - and removing is red.
func _animate_attach_button(hovering: bool, attached: bool) -> void:
	_attach_button.pivot_offset = _attach_button.size / 2.0
	if _attach_tween:
		_attach_tween.kill()
	_attach_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	if not hovering:
		_attach_tween.tween_property(_attach_button, "scale", Vector2.ONE, 0.10)
		_attach_tween.parallel().tween_property(_attach_button, "rotation", 0.0, 0.10)
		return

	if attached:
		_attach_tween.tween_property(_attach_button, "scale", Vector2(0.92, 0.92), 0.12)
		return

	_attach_tween.tween_property(_attach_button, "scale", Vector2(1.07, 1.07), 0.12)
	_attach_tween.parallel().tween_property(_attach_button, "rotation", deg_to_rad(3.0), 0.08)
	_attach_tween.tween_property(_attach_button, "rotation", deg_to_rad(-3.0), 0.10)
	_attach_tween.tween_property(_attach_button, "rotation", deg_to_rad(1.5), 0.08)
	_attach_tween.tween_property(_attach_button, "rotation", 0.0, 0.08)


## Adding or deleting a child of the attached node can enable or disable
## cards, so rebuild the list when that happens.
func _on_scene_tree_changed(node: Node) -> void:
	if not is_visible_in_tree() or not is_instance_valid(_target):
		return
	if node.get_parent() == _target:
		_populate_library.call_deferred()


func _refresh_attach_button() -> void:
	var attached: bool = is_instance_valid(_target) and _target.get_script() == RUNTIME
	_attach_button.text = Lang.t("\u2715  Remove from Selected Node") if attached else Lang.t("Attach to Selected Node")

	if not attached:
		for state in ["normal", "hover", "pressed"]:
			_attach_button.remove_theme_stylebox_override(state)
		for item in ["font_color", "font_hover_color", "font_pressed_color"]:
			_attach_button.remove_theme_color_override(item)
		return

	for state in ["normal", "hover", "pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color = REMOVE_TINT if state == "normal" else REMOVE_TINT.lightened(0.12)
		box.set_corner_radius_all(4)
		box.content_margin_left = 10
		box.content_margin_right = 10
		box.content_margin_top = 4
		box.content_margin_bottom = 4
		_attach_button.add_theme_stylebox_override(state, box)
	for item in ["font_color", "font_hover_color", "font_pressed_color"]:
		_attach_button.add_theme_color_override(item, Color(0.14, 0.07, 0.07))


func _clear_canvas() -> void:
	_loading = true
	_dialogue_editor.hide()
	_graph.clear_connections()
	for child in _graph.get_children():
		if child is GraphNode:
			_graph.remove_child(child)
			child.free()
	_graph_res = null
	_graph_path = ""
	_loading = false


func _autosave() -> void:
	if _loading or _graph_res == null:
		return
	_refresh_conditional_params()
	_refresh_run_order()
	_on_save_pressed()
	_record_undo()


## Every change becomes an editor undo step. Quick bursts (typing, dragging
## a slider) merge into one.
func _record_undo() -> void:
	var state := _snapshot()
	if undo_redo == null or state == _last_state:
		return
	undo_redo.create_action("Visuract: Edit Graph", UndoRedo.MERGE_ENDS)
	undo_redo.add_do_method(self, "_restore_graph", _graph_res, state)
	undo_redo.add_undo_method(self, "_restore_graph", _graph_res, _last_state)
	undo_redo.commit_action(false)
	_last_state = state


func _snapshot() -> Dictionary:
	return {"nodes": _graph_res.nodes.duplicate(true), "connections": _graph_res.connections.duplicate(true)}


func _restore_graph(res: VisuractGraph, state: Dictionary) -> void:
	res.nodes = state.nodes.duplicate(true)
	res.connections = state.connections.duplicate(true)
	ResourceSaver.save(res, res.resource_path)
	if res == _graph_res:
		_load_into_canvas(false)


func _build_menus() -> void:
	_node_menu = PopupMenu.new()
	_node_menu.add_item(Lang.t("Copy"), MENU_COPY)
	_node_menu.add_item(Lang.t("Duplicate"), MENU_DUPLICATE)
	_node_menu.add_separator()
	_node_menu.add_item(Lang.t("Delete"), MENU_DELETE)
	_node_menu.id_pressed.connect(_on_menu_pressed)
	add_child(_node_menu)

	_add_menu = PopupMenu.new()
	var id := 0
	for category in Library.NODES:
		var sub := PopupMenu.new()
		sub.name = category
		for entry in Library.NODES[category]:
			sub.add_item(Lang.t(entry.name), id)
			_menu_types[id] = entry.name
			id += 1
		sub.id_pressed.connect(_on_add_menu_pressed)
		_add_menu.add_child(sub)
		_add_menu.add_submenu_item(Lang.t("Add %s") % Lang.t(category), category)
	_add_menu.add_separator()
	_add_menu.add_item(Lang.t("Add Note"), MENU_NOTE)
	_add_menu.add_item(Lang.t("Paste"), MENU_PASTE)
	_add_menu.id_pressed.connect(func(id):
		if id == MENU_PASTE:
			_paste(_spawn_position)
		elif id == MENU_NOTE:
			_make_note(_spawn_position))
	add_child(_add_menu)


func _on_empty_area_clicked(at_position: Vector2) -> void:
	_spawn_position = (at_position + _graph.scroll_offset) / _graph.zoom
	_add_menu.set_item_disabled(_add_menu.get_item_index(MENU_PASTE), _clipboard.is_empty())
	_add_menu.popup(Rect2i(DisplayServer.mouse_get_position(), Vector2i.ZERO))


func _on_add_menu_pressed(id: int) -> void:
	_make_graph_node(_menu_types[id], _spawn_position)


func _on_node_right_clicked(gn: GraphNode) -> void:
	if not gn.selected:
		for other in _selected_nodes():
			other.selected = false
		gn.selected = true
	_node_menu.popup(Rect2i(DisplayServer.mouse_get_position(), Vector2i.ZERO))


func _on_menu_pressed(id: int) -> void:
	match id:
		MENU_COPY:
			_copy_selected()
		MENU_DUPLICATE:
			_duplicate_selected()
		MENU_DELETE:
			_delete_nodes(_selected_names())


## The English node type, whatever language its header is showing.
func _type_of(gn: GraphNode) -> String:
	return String(gn.get_meta("type", gn.title))


func _selected_nodes() -> Array:
	var result := []
	for child in _graph.get_children():
		if child is GraphNode and child.selected:
			result.append(child)
	return result


func _selected_names() -> Array:
	var names := []
	for gn in _selected_nodes():
		names.append(gn.name)
	return names


func _duplicate_selected() -> void:
	var copies := []
	for gn in _selected_nodes():
		var copy := _make_graph_node(_type_of(gn), gn.position_offset + Vector2(30, 30), "", _read_params(gn))
		if copy != null:
			copies.append(copy)
			gn.selected = false
	for copy in copies:
		copy.selected = true


func _copy_selected() -> void:
	var picked := _selected_nodes()
	if picked.is_empty():
		return
	_clipboard.clear()
	_clipboard_links.clear()
	var index := {}
	for gn in picked:
		index[String(gn.name)] = _clipboard.size()
		_clipboard.append({"type": _type_of(gn), "position": gn.position_offset, "params": _read_params(gn).duplicate(true)})
	for c in _graph.get_connection_list():
		var from := String(c.get("from_node", c.get("from", "")))
		var to := String(c.get("to_node", c.get("to", "")))
		if index.has(from) and index.has(to):
			_clipboard_links.append([index[from], index[to]])
	_set_status(Lang.t("Copied %d blocks - select another node and paste.") % picked.size())


## Places the copied blocks with their top-left corner at the given spot,
## keeping the cables between them. Saved as one undo step.
func _paste(at: Vector2) -> void:
	if _clipboard.is_empty():
		return
	var corner: Vector2 = _clipboard[0].position
	for item in _clipboard:
		corner = corner.min(item.position)
	for other in _selected_nodes():
		other.selected = false

	_loading = true
	var made := []
	for item in _clipboard:
		made.append(_make_graph_node(item.type, at + item.position - corner, "", item.params.duplicate(true)))
	if made.has(null):
		_loading = false
		return
	for link in _clipboard_links:
		_graph.connect_node(made[link[0]].name, 0, made[link[1]].name, 0)
	for gn in made:
		gn.selected = true
	_loading = false
	_refresh_conditional_params()
	_autosave()


func _delete_nodes(node_names: Array) -> void:
	for n in node_names:
		var gn := _graph.get_node_or_null(NodePath(n))
		if gn == null:
			continue
		for c in _graph.get_connection_list():
			var from := String(c.get("from_node", c.get("from", "")))
			var to := String(c.get("to_node", c.get("to", "")))
			if from == String(n) or to == String(n):
				_graph.disconnect_node(from, c.from_port, to, c.to_port)
		_graph.remove_child(gn)
		gn.free()
	_refresh_conditional_params()
	_autosave()


func _build_toolbar() -> Control:
	var bar := HBoxContainer.new()

	_attach_button = Button.new()
	_attach_button.text = Lang.t("Attach to Selected Node")
	_attach_button.pressed.connect(_on_attach_pressed)
	_attach_button.mouse_entered.connect(_on_attach_hover.bind(true))
	_attach_button.mouse_exited.connect(_on_attach_hover.bind(false))
	bar.add_child(_attach_button)

	_save_button = Button.new()
	_save_button.text = Lang.t("Save Graph")
	_save_button.pressed.connect(_on_save_pressed)
	_save_button.pressed.connect(_punch_save_button)
	_save_button.mouse_entered.connect(_animate_save_button.bind(true))
	_save_button.mouse_exited.connect(_animate_save_button.bind(false))
	bar.add_child(_save_button)

	_language_button = MenuButton.new()
	_language_button.text = Lang.t("Language")
	_style_language_button()
	var languages := _language_button.get_popup()
	for language in Lang.LANGUAGES:
		languages.add_item(Lang.t(language))
	languages.id_pressed.connect(func(id): _set_language(Lang.LANGUAGES[id]))
	bar.add_child(_language_button)

	## The status text lives in the spacer and gets cut off when space runs out,
	## so it can never push the view tabs off screen.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.clip_contents = true
	bar.add_child(spacer)

	_target_label = Label.new()
	_target_label.text = _status
	_target_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_target_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	spacer.add_child(_target_label)

	## Swaps what the big area shows: the node graph or the scene library.
	var views := HBoxContainer.new()
	views.custom_minimum_size = Vector2(LIBRARY_WIDTH, 0)
	bar.add_child(views)
	var group := ButtonGroup.new()
	for view in ["Node Graph", "Scene Library"]:
		var tab := Button.new()
		tab.text = Lang.t(view)
		tab.toggle_mode = true
		tab.button_group = group
		tab.button_pressed = view == "Node Graph"
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(_show_scene_library.bind(view == "Scene Library"))
		_style_view_tab(tab)
		views.add_child(tab)

	## Room for the enlarged active tab, so its right edge isn't cut off.
	var end_gap := Control.new()
	end_gap.custom_minimum_size = Vector2(8, 0)
	bar.add_child(end_gap)
	return bar


## The active tab gets a thick bright border and sits a little bigger.
func _style_view_tab(tab: Button) -> void:
	for state in ["pressed", "hover_pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.3, 0.3, 0.3)
		box.border_color = TAB_BORDER
		box.set_border_width_all(3)
		box.set_corner_radius_all(4)
		box.set_content_margin_all(6)
		tab.add_theme_stylebox_override(state, box)
	tab.scale = TAB_GROW if tab.button_pressed else Vector2.ONE
	tab.resized.connect(func(): tab.pivot_offset = tab.size / 2.0)
	tab.toggled.connect(func(on: bool):
		create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT) \
			.tween_property(tab, "scale", TAB_GROW if on else Vector2.ONE, 0.12))


func _show_scene_library(on: bool) -> void:
	_dialogue_editor.hide()
	_graph.visible = not on
	_scene_library.visible = on
	_library_panel.visible = not on
	_attach_button.visible = not on
	_target_label.visible = not on
	_save_button.visible = not on and is_instance_valid(_target) and _target.get_script() == RUNTIME
	if on:
		_scene_library.refresh()


func _set_status(text: String) -> void:
	_status = text
	_target_label.text = text
	_target_label.modulate = Color.WHITE


func _on_attach_hover(hovering: bool) -> void:
	var attached: bool = is_instance_valid(_target) and _target.get_script() == RUNTIME
	_attach_button.modulate = HIGHLIGHT if hovering and not attached else Color.WHITE
	_animate_attach_button(hovering, attached)
	if not hovering:
		_target_label.text = _status
		_target_label.modulate = Color.WHITE
		_clear_highlight()
		return

	var selected := EditorInterface.get_selection().get_selected_nodes()
	_target_label.modulate = HIGHLIGHT
	if selected.is_empty():
		_target_label.text = Lang.t("Select a node in the scene first.")
	else:
		var verb := Lang.t("Will remove from") if selected[0].get_script() == RUNTIME else Lang.t("Will attach to")
		_target_label.text = "%s:  %s  (%s)" % [verb, selected[0].name, selected[0].get_class()]
		_highlight_in_hierarchy(selected[0])


## Tints the node's row in the Scene dock. Uses editor internals, so it
## fails quietly if Godot's layout changes.
func _highlight_in_hierarchy(node: Node) -> void:
	_clear_highlight()
	var tree := _find_scene_tree(EditorInterface.get_base_control())
	if tree == null or tree.get_root() == null:
		return
	_highlighted_item = _find_item(tree.get_root(), node.name)
	if _highlighted_item:
		_shimmer_time = 0.0
		set_process(true)


func _clear_highlight() -> void:
	set_process(false)
	if is_instance_valid(_highlighted_item):
		_highlighted_item.clear_custom_bg_color(0)
		_highlighted_item.clear_custom_color(0)
	_highlighted_item = null


func _process(delta: float) -> void:
	if not is_instance_valid(_highlighted_item):
		set_process(false)
		return
	_shimmer_time += delta
	var hue := fmod(_shimmer_time * 0.4, 1.0)
	_highlighted_item.set_custom_bg_color(0, Color.from_hsv(hue, 0.55, 1.0, 0.35))
	_highlighted_item.set_custom_color(0, Color.from_hsv(hue, 0.35, 1.0))


func _find_scene_tree(from: Node) -> Tree:
	if from.get_class() == "SceneTreeEditor" and from.is_visible_in_tree():
		for child in from.get_children():
			if child is Tree:
				return child
	for child in from.get_children():
		var found := _find_scene_tree(child)
		if found:
			return found
	return null


func _find_item(item: TreeItem, node_name: String) -> TreeItem:
	if item.get_text(0) == node_name:
		return item
	var child := item.get_first_child()
	while child:
		var found := _find_item(child, node_name)
		if found:
			return found
		child = child.get_next()
	return null


func _build_library_panel(parent: Control) -> void:
	var panel := PanelContainer.new()
	_library_panel = panel
	panel.custom_minimum_size = Vector2(LIBRARY_WIDTH, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	margin.add_child(column)

	var title := Label.new()
	title.text = Lang.t("Node Library")
	column.add_child(title)

	_library_hint = Label.new()
	_library_hint.text = Lang.t("all nodes")
	_library_hint.add_theme_font_size_override("font_size", 11)
	_library_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	column.add_child(_library_hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	_library_list = VBoxContainer.new()
	_library_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_library_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_library_list)


func _populate_library() -> void:
	for child in _library_list.get_children():
		child.queue_free()

	var attached: bool = is_instance_valid(_target) and _target.get_script() == RUNTIME
	_save_button.visible = attached and _graph.visible
	if not attached:
		_library_hint.text = Lang.t("attach Visuract to use these")
	else:
		_library_hint.text = Lang.t("for %s") % _target.get_class()

	for category in Library.NODES:
		var usable := []
		for entry in Library.NODES[category]:
			if _fits_target(entry):
				usable.append(entry)
		if usable.is_empty():
			continue

		var color: Color = Library.CATEGORY_COLORS.get(category, Color.GRAY)
		var header := Label.new()
		header.text = Lang.t(category).to_upper()
		header.add_theme_color_override("font_color", color)
		_library_list.add_child(header)

		for entry in usable:
			var card := Card.new()
			card.node_type = entry.name
			card.text = Lang.t(entry.name)
			card.alignment = HORIZONTAL_ALIGNMENT_LEFT
			card.custom_minimum_size = Vector2(0, 34)
			var missing := _missing_child(entry)
			if not attached:
				card.disabled = true
				card.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN
				card.tooltip_text = Lang.t("Click Attach to Selected Node first.")
				_style_card(card, color.darkened(0.45))
			elif missing == "":
				card.tooltip_text = entry.desc + "\n\n" + Lang.t("Code:") + "\n" + entry.code
				_style_card(card, color)
			else:
				card.disabled = true
				card.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN
				card.tooltip_text = Lang.t("Needs a %s under %s before this can work.") % [missing, _target.name]
				_style_card(card, color.darkened(0.45))
				card.text = Lang.t(entry.name) + "  \u26a0"
			card.pressed.connect(_on_card_pressed.bind(entry.name))
			_library_list.add_child(card)

		_library_list.add_child(HSeparator.new())


## Solid category-colored button with black bold text.
func _style_card(card: Button, color: Color) -> void:
	for state in ["normal", "hover", "pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color = color if state == "normal" else color.lightened(0.18)
		box.set_corner_radius_all(4)
		box.content_margin_left = 8
		box.content_margin_right = 8
		card.add_theme_stylebox_override(state, box)
	for item in ["font_color", "font_hover_color", "font_pressed_color"]:
		card.add_theme_color_override(item, Color.BLACK)
	card.add_theme_font_size_override("font_size", 15)
	var bold := _bold_font()
	if bold:
		card.add_theme_font_override("font", bold)


## Names the child class an entry needs but can't find, or "" when it's fine.
## Unlike requires_class this is fixable, so the card is greyed rather than hidden.
func _missing_child(entry: Dictionary) -> String:
	var requirement := String(entry.get("requires_child", ""))
	if requirement == "" or not is_instance_valid(_target):
		return ""
	var wanted := requirement.split(",")
	for child in _target.get_children():
		for class_wanted in wanted:
			if child.is_class(String(class_wanted).strip_edges()):
				return ""
	return String(wanted[0]).strip_edges()


## An entry is offered only when the attached node is one of the classes it
## needs - no point showing Jump on a Sprite2D.
func _fits_target(entry: Dictionary) -> bool:
	var requirement := String(entry.get("requires_class", ""))
	if requirement == "" or not is_instance_valid(_target):
		return true
	for wanted in requirement.split(","):
		if _target.is_class(wanted.strip_edges()):
			return true
	return false


func _on_card_pressed(type: String) -> void:
	_make_graph_node(type, _spawn_offset + _graph.scroll_offset)
	_spawn_offset += Vector2(30, 30)


func _make_graph_node(type: String, pos: Vector2, id: String = "", values: Dictionary = {}) -> GraphNode:
	if type == NOTE_TYPE:
		return _make_note(pos, id, values)
	if _graph_res == null:
		var who := _target.name if is_instance_valid(_target) else Lang.t("a node")
		_set_status(Lang.t("Attach Visuract to %s first - then you can add blocks.") % who)
		return null

	var entry := Library.find(type)
	var gn := GraphNode.new()
	gn.name = id if id != "" else "VN%d" % _next_id
	gn.title = Lang.t(type) if not entry.is_empty() else Lang.t(type) + "  \u26a0"
	gn.set_meta("type", type)
	gn.position_offset = pos
	## Wide enough for every param it could ever show, so ticking a checkbox
	## that reveals a slider doesn't resize the node.
	gn.custom_minimum_size = Vector2(_widest_row(entry.get("params", {})), 0)
	_next_id += 1

	## Slim first row so the in/out ports sit just under the header.
	var port_row := Control.new()
	port_row.custom_minimum_size = Vector2(0, 12)
	port_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gn.add_child(port_row)
	if entry.is_empty():
		gn.tooltip_text = Lang.t("'%s' is not a Visuract node any more. Delete it and pick the closest one from the library.") % type
	else:
		gn.tooltip_text = entry.get("desc", "") + "\n\n" + Lang.t("Code:") + "\n" + entry.get("code", "")
	gn.set_slot(0, true, 0, Color.WHITE, true, 0, Color.WHITE)
	_add_param_fields(gn, entry.get("params", {}), values)
	_graph.add_child(gn)
	_tint_titlebar(gn, Library.color_of(type))
	_refresh_conditional_params()
	_autosave()
	return gn


## A plain comment on the canvas: no ports, no code, just text. The panel
## grows with whatever is typed in it.
func _make_note(pos: Vector2, id: String = "", values: Dictionary = {}) -> GraphNode:
	if _graph_res == null:
		_set_status(Lang.t("Attach Visuract to a node first - then you can add notes."))
		return null

	var gn := GraphNode.new()
	gn.name = id if id != "" else "VN%d" % _next_id
	gn.title = Lang.t(NOTE_TYPE)
	gn.set_meta("type", NOTE_TYPE)
	gn.position_offset = pos
	_next_id += 1

	var edit := TextEdit.new()
	edit.text = String(values.get("text", ""))
	edit.placeholder_text = Lang.t("Write a note\u2026")
	edit.scroll_fit_content_height = true
	edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	edit.add_theme_font_size_override("font_size", NOTE_FONT_SIZE)
	edit.add_theme_color_override("font_color", Color.BLACK)
	edit.add_theme_color_override("font_readonly_color", Color.BLACK)
	edit.add_theme_color_override("font_placeholder_color", Color(0, 0, 0, 0.4))
	edit.add_theme_color_override("caret_color", Color.BLACK)
	edit.add_theme_color_override("selection_color", Color(0, 0, 0, 0.2))
	edit.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	edit.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	edit.add_theme_stylebox_override("read_only", StyleBoxEmpty.new())
	var bold := _bold_font()
	if bold:
		edit.add_theme_font_override("font", bold)
	gn.add_child(edit)
	gn.set_meta("param_widgets", {"text": edit})

	## Click-through until double-clicked, so dragging the note never puts
	## the caret in it.
	gn.tooltip_text = Lang.t("Double-click to edit this note. Drag an edge to resize it.")
	_set_note_editing(edit, false)
	gn.gui_input.connect(_on_note_input.bind(gn, edit))
	gn.gui_input.connect(func(event):
		if gn.get_meta("note_edges", Vector2i.ZERO) != Vector2i.ZERO:
			return
		if event is InputEventMouseButton and event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
			_set_note_editing(edit, true)
			gn.accept_event())
	edit.focus_exited.connect(_set_note_editing.bind(edit, false))
	edit.text_changed.connect(func():
		_fit_note(gn, edit)
		_autosave())

	_graph.add_child(gn)
	_style_note(gn)
	if values.get("size", Vector2.ZERO) != Vector2.ZERO:
		gn.set_meta("note_size", values["size"])
		_apply_note_size(gn, edit)
	else:
		_fit_note(gn, edit)
	_autosave()
	return gn


## Window-style resizing: hovering an edge swaps the cursor, dragging it
## moves that edge and keeps the opposite one in place.
func _on_note_input(event: InputEvent, gn: GraphNode, edit: TextEdit) -> void:
	var edges: Vector2i = gn.get_meta("note_edges", Vector2i.ZERO)
	if event is InputEventMouseMotion:
		if gn.get_meta("note_resizing", false):
			_resize_note(gn, edit, edges, event.relative)
			gn.accept_event()
		else:
			edges = _note_edges(gn, event.position)
			gn.set_meta("note_edges", edges)
			gn.mouse_default_cursor_shape = _edge_cursor(edges)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and edges != Vector2i.ZERO:
			gn.set_meta("note_size", gn.size)
			gn.set_meta("note_resizing", true)
			gn.accept_event()
		elif not event.pressed and gn.get_meta("note_resizing", false):
			gn.set_meta("note_resizing", false)
			_autosave()
			gn.accept_event()


func _note_edges(gn: GraphNode, pos: Vector2) -> Vector2i:
	var edges := Vector2i.ZERO
	if pos.x <= NOTE_EDGE:
		edges.x = -1
	elif pos.x >= gn.size.x - NOTE_EDGE:
		edges.x = 1
	if pos.y <= NOTE_EDGE:
		edges.y = -1
	elif pos.y >= gn.size.y - NOTE_EDGE:
		edges.y = 1
	return edges


func _edge_cursor(edges: Vector2i) -> int:
	if edges.x != 0 and edges.y != 0:
		return Control.CURSOR_FDIAGSIZE if edges.x == edges.y else Control.CURSOR_BDIAGSIZE
	if edges.x != 0:
		return Control.CURSOR_HSIZE
	if edges.y != 0:
		return Control.CURSOR_VSIZE
	return Control.CURSOR_ARROW


func _resize_note(gn: GraphNode, edit: TextEdit, edges: Vector2i, delta: Vector2) -> void:
	var old: Vector2 = gn.get_meta("note_size", gn.size)
	var size := old
	size.x += delta.x * edges.x
	size.y += delta.y * edges.y
	size = size.max(NOTE_MIN_SIZE)
	if edges.x < 0:
		gn.position_offset.x += old.x - size.x
	if edges.y < 0:
		gn.position_offset.y += old.y - size.y
	gn.set_meta("note_size", size)
	_apply_note_size(gn, edit)


## Once a note has been resized by hand the width is fixed and the text
## wraps inside it, but the height still grows so nothing is ever cut off.
func _apply_note_size(gn: GraphNode, edit: TextEdit) -> void:
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.scroll_fit_content_height = true
	edit.custom_minimum_size = Vector2.ZERO
	gn.custom_minimum_size = gn.get_meta("note_size")
	gn.reset_size.call_deferred()


func _set_note_editing(edit: TextEdit, on: bool) -> void:
	edit.editable = on
	edit.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
	if on:
		edit.grab_focus()
	else:
		edit.deselect()


## No header, no ports: the whole block is one yellow panel holding the text.
func _style_note(gn: GraphNode) -> void:
	for item in ["titlebar", "titlebar_selected", "panel", "panel_selected"]:
		var box := StyleBoxFlat.new()
		box.bg_color = NOTE_COLOR
		box.set_corner_radius_all(6)
		box.set_content_margin_all(0 if item.begins_with("titlebar") else 10)
		if item.ends_with("selected"):
			box.border_color = Color.WHITE
			box.set_border_width_all(2)
		gn.add_theme_stylebox_override(item, box)
	for child in gn.get_titlebar_hbox().get_children():
		child.visible = false


## Widens the note to its longest line; the height follows the text itself.
func _fit_note(gn: GraphNode, edit: TextEdit) -> void:
	if gn.has_meta("note_size"):
		_apply_note_size(gn, edit)
		return
	var font := edit.get_theme_font("font")
	var font_size := edit.get_theme_font_size("font_size")
	var width := 160.0
	for line in edit.text.split("\n"):
		width = maxf(width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 40)
	edit.custom_minimum_size = Vector2(width, 0)
	gn.reset_size.call_deferred()


## Colors the GraphNode header by its library category.
func _tint_titlebar(gn: GraphNode, color: Color) -> void:
	for item in ["titlebar", "titlebar_selected"]:
		var base := gn.get_theme_stylebox(item, "GraphNode")
		var box: StyleBoxFlat = base.duplicate() if base is StyleBoxFlat else StyleBoxFlat.new()
		box.bg_color = color if item == "titlebar" else color.lightened(0.25)
		gn.add_theme_stylebox_override(item, box)
	var bold := _bold_font()
	var titlebar := gn.get_titlebar_hbox()
	## A step-order badge, right-aligned in the header.
	var badge := Label.new()
	badge.name = "OrderBadge"
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_font_size_override("font_size", 15)
	badge.add_theme_color_override("font_color", Color(0, 0, 0, 0.55))
	if bold:
		badge.add_theme_font_override("font", bold)
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titlebar.add_child(spacer)
	titlebar.add_child(badge)
	for child in titlebar.get_children():
		if child is Label and child != badge:
			child.add_theme_color_override("font_color", Color.BLACK)
			child.add_theme_font_size_override("font_size", 26)
			child.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
			child.add_theme_constant_override("shadow_offset_x", 0)
			child.add_theme_constant_override("shadow_offset_y", 0)
			child.add_theme_constant_override("shadow_outline_size", 0)
			if bold:
				child.add_theme_font_override("font", bold)


func _bold_font() -> Font:
	var base := EditorInterface.get_base_control()
	return base.get_theme_font("bold", "EditorFonts") if base.has_theme_font("bold", "EditorFonts") else null


## A slider row needs more room than a spinbox or dropdown row.
func _widest_row(defaults: Dictionary) -> float:
	for key in defaults:
		var spec = defaults[key]
		if typeof(spec) == TYPE_DICTIONARY and String(spec.get("type", "")) == "slider":
			return 400.0
	return 330.0


func _add_param_fields(gn: GraphNode, defaults: Dictionary, values: Dictionary) -> void:
	var widgets := {}
	var rows := {}
	var requires := {}
	var needs_param := {}
	for key in defaults:
		var spec = defaults[key]
		var is_spec := typeof(spec) == TYPE_DICTIONARY
		var fallback = spec.get("default", "") if is_spec else spec
		var value = values.get(key, fallback)
		## Older Spawn Scene graphs kept one path and shared placement.
		if is_spec and spec.get("type") == "scene_list" and value is String and value != "":
			var entry := {"scene": value, "weight": 1.0}
			for k in SCENE_PLACEMENT:
				entry[k] = values.get(k, 0.0)
			value = [entry]
		## Place used to be shared by the whole node.
		if is_spec and spec.get("type") == "scene_list" and value is Array:
			for e in value:
				e.merge({"where": values.get("where", "On me"), "spawn_point": values.get("spawn_point", "")})

		## A header is a divider label, not an editable value.
		if is_spec and String(spec.get("type", "")) == "header":
			var heading := Label.new()
			heading.text = Lang.t(String(spec.get("text", "")))
			heading.add_theme_font_size_override("font_size", 11)
			heading.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
			heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
			gn.add_child(heading)
			rows[key] = heading
			requires[key] = []
			needs_param[key] = spec.get("requires_param", {})
			continue

		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		var name_label := Label.new()
		name_label.text = Lang.t(String(key).capitalize())
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.mouse_filter = Control.MOUSE_FILTER_PASS
		## A scene list labels each of its own sections.
		name_label.visible = not (is_spec and spec.get("type") == "scene_list")
		row.add_child(name_label)
		row.add_child(_make_field(spec, is_spec, value, widgets, key))
		gn.add_child(row)
		rows[key] = row
		requires[key] = spec.get("requires_upstream", []) if is_spec else []
		needs_param[key] = spec.get("requires_param", {}) if is_spec else {}
	gn.set_meta("param_widgets", widgets)
	gn.set_meta("param_rows", rows)
	gn.set_meta("param_requires", requires)
	gn.set_meta("param_needs", needs_param)

	## Rows that depend on another param follow it live, rather than waiting
	## for a canvas-wide refresh.
	for key in widgets:
		var widget = widgets[key]
		if widget is OptionButton:
			widget.item_selected.connect(func(_i): _apply_param_conditions(gn))
		elif widget is CheckBox:
			widget.toggled.connect(func(_pressed): _apply_param_conditions(gn))
	_apply_param_conditions(gn)


func _make_field(spec, is_spec: bool, value, widgets: Dictionary, key) -> Control:
	var spec_type := String(spec.get("type", "")) if is_spec else ""

	if spec_type == "slider":
		var slider := HSlider.new()
		slider.min_value = spec.get("min", 0.0)
		slider.max_value = spec.get("max", 100.0)
		slider.step = spec.get("step", 1.0)
		var decimals: int = spec.get("decimals", 0)
		var format := "%%.%df" % decimals
		slider.custom_minimum_size = Vector2(170, 0)
		slider.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		slider.value = value

		## Typable, and a fixed width so changing digits never resize the row
		## and shove the slider sideways.
		var readout := LineEdit.new()
		readout.custom_minimum_size = Vector2(54, 0)
		readout.size_flags_horizontal = Control.SIZE_SHRINK_END
		readout.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		readout.text = format % slider.value
		slider.value_changed.connect(func(v):
			readout.text = format % v
			_autosave())
		readout.text_submitted.connect(func(typed):
			slider.value = typed.to_float()
			readout.release_focus())
		readout.focus_exited.connect(func():
			slider.value = readout.text.to_float()
			readout.text = format % slider.value)

		var track := HBoxContainer.new()
		track.add_child(slider)
		track.add_child(readout)
		widgets[key] = slider
		return track

	if spec_type == "color":
		var swatch := ColorPickerButton.new()
		swatch.custom_minimum_size = Vector2(80, 0)
		swatch.color = value if value is Color else Color.WHITE
		swatch.color_changed.connect(func(_c): _autosave())
		widgets[key] = swatch
		return swatch

	if spec_type == "ramp":
		var ramp := ColorRamp.new()
		if value is Dictionary and not value.is_empty():
			ramp.value = value
		ramp.value_changed.connect(_autosave)
		widgets[key] = ramp
		return ramp

	if spec_type == "choice":
		var picker := OptionButton.new()
		var choices: Array = spec.get("options", [])
		if spec.has("options_from"):
			## Dropdowns built from the project start empty, so a slot left
			## alone stays empty instead of grabbing the first entry.
			choices = _options_from(String(spec["options_from"]))
			if not choices.is_empty() and String(choices[0]).begins_with("(no "):
				pass
			else:
				choices = [NONE_OPTION] + choices
		for i in choices.size():
			picker.add_item(Lang.t(String(choices[i])), i)
		picker.selected = maxi(0, choices.find(value))
		## Labels can be translated, so the English choices are kept alongside.
		picker.set_meta("options", choices)
		picker.item_selected.connect(func(_i): _autosave())
		widgets[key] = picker
		return picker

	## The dialogue is too big for the node, so it's edited in a panel.
	if spec_type == "dialogue":
		var edit := Button.new()
		edit.text = Lang.t("Edit Dialogue\u2026")
		var data: Dictionary = value if value is Dictionary and not value.is_empty() else DialogueEditor.FRESH
		edit.set_meta("dialogue", data.duplicate(true))
		edit.pressed.connect(_open_dialogue.bind(edit))
		widgets[key] = edit
		return edit

	if spec_type == "scene_list":
		return _make_scene_list(value, widgets, key)

	if spec_type == "node" or spec_type == "file":
		var slot := Slot.new()
		slot.kind = spec_type
		slot.value = String(value)
		slot.custom_minimum_size = Vector2(150, 0)
		if spec_type == "node":
			slot.options = _node_options(String(spec.get("class", "")))
			if spec.get("allow_toucher", false):
				slot.options = [TOUCHER_OPTION] + slot.options
		else:
			slot.options = _file_options(String(spec.get("filter", "tscn")))
		if spec_type == "node":
			slot.normalizer = _shorten_node_path
		slot.value_changed.connect(_autosave)
		widgets[key] = slot
		return slot

	if typeof(fallback_type(spec, is_spec)) == TYPE_BOOL:
		var check := CheckBox.new()
		check.button_pressed = value
		check.toggled.connect(func(_pressed): _autosave())
		widgets[key] = check
		return check

	if typeof(fallback_type(spec, is_spec)) == TYPE_STRING:
		var line := LineEdit.new()
		line.text = String(value)
		line.custom_minimum_size = Vector2(120, 0)
		line.text_changed.connect(func(_t): _autosave())
		widgets[key] = line
		return line

	var spin := SpinBox.new()
	spin.min_value = spec.get("min", 0.0) if is_spec else 0.0
	spin.max_value = spec.get("max", 100000.0) if is_spec else 100000.0
	spin.step = spec.get("step", 1.0) if is_spec else 1.0
	spin.value = value
	spin.value_changed.connect(func(_v): _autosave())
	widgets[key] = spin
	return spin


## Several scenes, each with a weight and its own placement. Chance is
## weight / all weights, so the numbers never have to add up to 100.
func _make_scene_list(value, widgets: Dictionary, key) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	var entries: Array = value if value is Array else []
	if entries.is_empty():
		entries = [{}]
	for e in entries:
		_add_scene_entry(box, e)

	var add := Button.new()
	add.text = Lang.t("+ Add Scene")
	add.pressed.connect(func():
		_add_scene_entry(box, {})
		box.move_child(add, -1)
		_autosave())
	box.add_child(add)
	widgets[key] = box
	return box


func _add_scene_entry(box: VBoxContainer, data: Dictionary) -> void:
	var section := PanelContainer.new()
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(1, 1, 1, 0.03)
	frame.border_color = SECTION_BORDER
	frame.set_border_width_all(1)
	frame.set_corner_radius_all(6)
	frame.set_content_margin_all(8)
	section.add_theme_stylebox_override("panel", frame)
	var entry := VBoxContainer.new()
	section.add_child(entry)
	var slot := Slot.new()
	slot.kind = "file"
	slot.value = String(data.get("scene", ""))
	slot.custom_minimum_size = Vector2(150, 0)
	slot.options = _file_options("tscn")
	slot.value_changed.connect(_autosave)

	var remove := Button.new()
	remove.text = "\u2715"
	remove.flat = true
	remove.pressed.connect(func():
		box.remove_child(section)
		section.queue_free()
		_refresh_chances(box)
		_autosave()
		_fit_node.call_deferred(box))
	var title_row := _labeled_row(Lang.t("Scene"), [slot, remove])
	entry.add_child(title_row)

	var where := OptionButton.new()
	for place in Library.SPAWN_PLACES:
		where.add_item(Lang.t(place))
	where.selected = maxi(0, Library.SPAWN_PLACES.find(data.get("where", "On me")))
	var point := Slot.new()
	point.kind = "node"
	point.value = String(data.get("spawn_point", ""))
	point.custom_minimum_size = Vector2(150, 0)
	point.options = _node_options()
	point.normalizer = _shorten_node_path
	point.value_changed.connect(_autosave)
	var point_row := _labeled_row(Lang.t("Spawn Point"), [point])
	point_row.visible = where.selected == 1
	where.item_selected.connect(func(i):
		point_row.visible = i == 1
		_autosave()
		_fit_node.call_deferred(box))
	entry.add_child(_labeled_row(Lang.t("Where"), [where]))
	entry.add_child(point_row)

	var fields := {}
	for group in ["offset", "random"]:
		var header := Label.new()
		header.text = Lang.t(group.capitalize())
		entry.add_child(header)
		var row := HBoxContainer.new()
		for axis in ["x", "y"]:
			var key: String = group + "_" + axis
			var label := Label.new()
			label.text = axis.to_upper()
			var spin := SpinBox.new()
			spin.min_value = 0.0 if group == "random" else -10000.0
			spin.max_value = 10000.0
			spin.step = 5.0
			spin.value = data.get(key, 0.0)
			spin.value_changed.connect(func(_v): _autosave())
			row.add_child(label)
			row.add_child(spin)
			fields[key] = spin
		entry.add_child(row)

	var weight := SpinBox.new()
	weight.max_value = 1000.0
	weight.value = data.get("weight", 1.0)
	weight.tooltip_text = Lang.t("Higher is more likely. 0 never spawns.")
	weight.value_changed.connect(func(_v):
		_refresh_chances(box)
		_autosave())
	var chance := Label.new()
	chance.custom_minimum_size = Vector2(40, 0)
	chance.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	entry.add_child(_labeled_row(Lang.t("Chance"), [weight, chance]))

	section.set_meta("title", title_row.get_child(0))
	section.set_meta("slot", slot)
	section.set_meta("where", where)
	section.set_meta("spawn_point", point)
	section.set_meta("weight", weight)
	section.set_meta("chance", chance)
	section.set_meta("fields", fields)
	box.add_child(section)
	_refresh_chances(box)
	_fit_node.call_deferred(box)


func _labeled_row(text: String, controls: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	row.add_child(label)
	for c in controls:
		row.add_child(c)
	return row


## Resizes the GraphNode to its content after entries come or go.
func _fit_node(box: Control) -> void:
	var gn = box.get_parent().get_parent() if box.get_parent() else null
	if gn is GraphNode:
		gn.reset_size()


func _scene_entries(box: VBoxContainer) -> Array:
	return box.get_children().filter(func(c): return c is PanelContainer and not c.is_queued_for_deletion())


func _scene_list_value(box: VBoxContainer) -> Array:
	var out := []
	for entry in _scene_entries(box):
		var where: OptionButton = entry.get_meta("where")
		var data := {"scene": entry.get_meta("slot").value, "weight": entry.get_meta("weight").value, "where": Library.SPAWN_PLACES[where.selected], "spawn_point": entry.get_meta("spawn_point").value}
		var fields: Dictionary = entry.get_meta("fields")
		for key in fields:
			data[key] = fields[key].value
		out.append(data)
	return out


func _refresh_chances(box: VBoxContainer) -> void:
	var total := 0.0
	for entry in _scene_entries(box):
		total += entry.get_meta("weight").value
	var number := 1
	for entry in _scene_entries(box):
		entry.get_meta("title").text = Lang.t("Scene %d") % number
		number += 1
		entry.get_meta("chance").text = "%d%%" % roundi(100.0 * entry.get_meta("weight").value / total) if total > 0.0 else "0%"


func fallback_type(spec, is_spec: bool):
	return spec.get("default", 0.0) if is_spec else spec


func _on_dialogue_visibility_changed() -> void:
	var on := _dialogue_editor.visible
	_graph.visible = not on
	_library_panel.visible = not on
	_attach_button.visible = not on
	_target_label.visible = not on
	_save_button.visible = not on and is_instance_valid(_target) and _target.get_script() == RUNTIME


func _open_dialogue(button: Button) -> void:
	_dialogue_button = button
	_dialogue_editor.open(button.get_meta("dialogue"), _dialogue_label(button))


## The Label picked on the same Dialogue node, found in the edited scene.
func _dialogue_label(button: Button) -> Label:
	var slot = button.get_parent().get_parent().get_meta("param_widgets", {}).get("label")
	if slot == null or slot.value == "" or _target == null:
		return null
	var found := _target.get_node_or_null(NodePath(slot.value))
	var root := EditorInterface.get_edited_scene_root()
	if found == null and root != null:
		found = root.find_child(String(slot.value).get_file(), true, false)
	return found as Label


func _on_dialogue_changed(data: Dictionary) -> void:
	if is_instance_valid(_dialogue_button):
		_dialogue_button.set_meta("dialogue", data)
		_autosave()


func _options_from(source: String) -> Array:
	match source:
		"signal_names":
			return _signal_name_options()
		"animations":
			return _animation_options()
		"variable_names":
			return _variable_name_options()
		_:
			return _input_action_options()


## Every name any Remember node uses, so Only If can just pick one.
func _variable_name_options() -> Array:
	var out := []
	for child in _graph.get_children():
		if child is GraphNode and _type_of(child) == "Remember":
			_collect_signal_name(_read_params(child).get("variable_name", ""), out)

	for file in DirAccess.get_files_at(GRAPH_DIR):
		if not file.ends_with(".tres"):
			continue
		var resource = ResourceLoader.load(GRAPH_DIR.path_join(file))
		if not (resource is VisuractGraph):
			continue
		for n in resource.nodes:
			if n.type == "Remember":
				_collect_signal_name(n.get("params", {}).get("variable_name", ""), out)

	out.sort()
	if out.is_empty():
		out.append(NO_VARIABLES)
	return out


## Every name any Send Signal node uses, on this canvas or in a saved graph,
## so listeners can just pick one.
func _signal_name_options() -> Array:
	var out := []
	for child in _graph.get_children():
		if child is GraphNode and _type_of(child) == "Send Signal":
			_collect_signal_name(_read_params(child).get("signal_name", ""), out)

	for file in DirAccess.get_files_at(GRAPH_DIR):
		if not file.ends_with(".tres"):
			continue
		var resource = ResourceLoader.load(GRAPH_DIR.path_join(file))
		if not (resource is VisuractGraph):
			continue
		for n in resource.nodes:
			if n.type == "Send Signal":
				_collect_signal_name(n.get("params", {}).get("signal_name", ""), out)

	out.sort()
	if out.is_empty():
		out.append(NO_SIGNALS)
	return out


func _collect_signal_name(signal_name, into: Array) -> void:
	var text := String(signal_name)
	if text != "" and not into.has(text):
		into.append(text)


## The project's own input actions, straight from Project Settings.
func _input_action_options() -> Array:
	var out := []
	for property in ProjectSettings.get_property_list():
		var setting := String(property.name)
		if not setting.begins_with("input/"):
			continue
		var action := setting.substr(6)
		## Godot's own ui_* actions are project settings too - hide them.
		if action.begins_with("ui_") or action.contains("."):
			continue
		out.append(action)
	out.sort()
	if out.is_empty():
		out.append(NO_ACTIONS)
	return out


## Scene dock drops arrive as absolute editor paths - store them relative
## to the attached node instead.
func _shorten_node_path(raw: String) -> String:
	if _target == null:
		return raw.get_file()
	var node := get_tree().root.get_node_or_null(NodePath(raw))
	if node == null:
		return raw.get_file()
	if node == _target:
		return "."
	return String(_target.get_path_to(node))


## Paths of the attached node and everything under it. A class filter (one
## name, or several separated by commas) narrows it to matching nodes only.
func _node_options(filter_class := "") -> Array:
	var out := []
	if _target == null:
		return out
	var wanted := filter_class.split(",", false) if filter_class != "" else []
	if _matches(_target, wanted):
		out.append(".")
	var stack := _target.get_children()
	while not stack.is_empty():
		var node: Node = stack.pop_front()
		if _matches(node, wanted):
			out.append(String(_target.get_path_to(node)))
		stack.append_array(node.get_children())

	## Everything else in the scene, by name, so a graph can point at a node
	## that isn't one of its own children.
	var root := EditorInterface.get_edited_scene_root()
	if root != null:
		var others := [root]
		while not others.is_empty():
			var node: Node = others.pop_front()
			var node_name := String(node.name)
			if node != _target and _matches(node, wanted) and not out.has(node_name):
				out.append(node_name)
			others.append_array(node.get_children())
	return out


func _matches(node: Node, wanted: Array) -> bool:
	if wanted.is_empty():
		return true
	for class_name_wanted in wanted:
		if node.is_class(String(class_name_wanted).strip_edges()):
			return true
	return false


## Every animation on every AnimationPlayer and AnimatedSprite2D under the
## attached node, listed as
## "PlayerName / animation" so one dropdown picks both.
func _animation_options() -> Array:
	var out := []
	if _target == null:
		return [NO_ANIMATIONS]
	var stack := _target.get_children()
	while not stack.is_empty():
		var node: Node = stack.pop_front()
		if node.is_class("AnimationPlayer"):
			for animation in node.call("get_animation_list"):
				out.append("%s / %s" % [_target.get_path_to(node), animation])
		elif node.is_class("AnimatedSprite2D"):
			var frames = node.get("sprite_frames")
			if frames != null:
				for animation in frames.get_animation_names():
					out.append("%s / %s" % [_target.get_path_to(node), animation])
		stack.append_array(node.get_children())
	if out.is_empty():
		out.append(NO_ANIMATIONS)
	return out


func _file_options(filter: String) -> Array:
	var extensions := filter.split(",")
	var out := []
	var dirs := ["res://"]
	while not dirs.is_empty():
		var path: String = dirs.pop_front()
		for dir in DirAccess.get_directories_at(path):
			if not dir.begins_with("."):
				dirs.append(path.path_join(dir))
		for file in DirAccess.get_files_at(path):
			if file.get_extension() in extensions:
				out.append(path.path_join(file))
	return out


func _widget_value(field):
	if field is VBoxContainer:
		return _scene_list_value(field)
	if field.has_meta("dialogue"):
		return field.get_meta("dialogue")
	if field is ColorPickerButton:
		return field.color
	if field is OptionButton:
		var options: Array = field.get_meta("options", [])
		return options[field.selected] if field.selected >= 0 and field.selected < options.size() else field.get_item_text(field.selected)
	if field is CheckBox:
		return field.button_pressed
	if field is LineEdit or field is TextEdit:
		return field.text
	return field.value


## Hides params whose "requires_upstream" event isn't feeding this node.
## Numbers only the branches that leave a socket feeding more than one node,
## since that's the only place run order isn't obvious. Everything else is
## left blank.
func _refresh_run_order() -> void:
	for child in _graph.get_children():
		if child is GraphNode:
			var badge := _find_badge(child)
			if badge:
				badge.text = ""

	## Group outgoing connections by the node they leave.
	var out_targets := {}
	for c in _graph.get_connection_list():
		var from := String(c.get("from_node", c.get("from", "")))
		var to := String(c.get("to_node", c.get("to", "")))
		if not out_targets.has(from):
			out_targets[from] = []
		out_targets[from].append(to)

	for from in out_targets:
		var targets: Array = out_targets[from]
		if targets.size() < 2:
			continue
		var step := 1
		for to in targets:
			var gn := _graph.get_node_or_null(NodePath(to))
			if gn is GraphNode:
				var badge := _find_badge(gn)
				if badge:
					badge.text = str(step)
			step += 1


func _find_badge(gn: GraphNode) -> Label:
	for child in gn.get_titlebar_hbox().get_children():
		if child is Label and child.name == "OrderBadge":
			return child
	return null


func _refresh_conditional_params() -> void:
	for child in _graph.get_children():
		if not (child is GraphNode and child.has_meta("param_rows")):
			continue
		var needed: Dictionary = child.get_meta("param_requires")
		var rows: Dictionary = child.get_meta("param_rows")
		var upstream := _upstream_types(String(child.name))

		for key in rows:
			var list: Array = needed.get(key, [])
			if not list.is_empty():
				rows[key].visible = upstream.any(func(type): return type in list)
		_apply_param_conditions(child)


## A param can also depend on other params on the same node: it shows only
## while each holds the wanted value, or one of several wanted values.
func _apply_param_conditions(gn: GraphNode) -> void:
	var needs_param: Dictionary = gn.get_meta("param_needs") if gn.has_meta("param_needs") else {}
	var rows: Dictionary = gn.get_meta("param_rows")
	var widgets: Dictionary = gn.get_meta("param_widgets")
	for key in needs_param:
		if needs_param[key].is_empty():
			continue
		## Every listed param has to match.
		var shown := true
		for other in needs_param[key]:
			if not widgets.has(other):
				continue
			var wanted = needs_param[key][other]
			var have = _widget_value(widgets[other])
			shown = shown and (have in wanted if wanted is Array else have == wanted)
		rows[key].visible = shown


## Every node type that can reach this one by following cables backwards.
func _upstream_types(node_name: String) -> Array:
	var found := []
	var queue := [node_name]
	var seen := {}
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for c in _graph.get_connection_list():
			var from := String(c.get("from_node", c.get("from", "")))
			var to := String(c.get("to_node", c.get("to", "")))
			if to != current or seen.has(from):
				continue
			seen[from] = true
			var gn := _graph.get_node_or_null(NodePath(from))
			if gn:
				found.append(_type_of(gn))
			queue.append(from)
	return found


func _read_params(gn: GraphNode) -> Dictionary:
	var out := {}
	if not gn.has_meta("param_widgets"):
		return out
	var rows: Dictionary = gn.get_meta("param_rows") if gn.has_meta("param_rows") else {}
	for key in gn.get_meta("param_widgets"):
		## A hidden param isn't relevant to this node's wiring - don't save it.
		if rows.has(key) and not rows[key].visible:
			continue
		out[key] = _widget_value(gn.get_meta("param_widgets")[key])
	if gn.has_meta("note_size"):
		out["size"] = gn.get_meta("note_size")
	return out


func _on_attach_pressed() -> void:
	var selected := EditorInterface.get_selection().get_selected_nodes()
	if selected.is_empty():
		_set_status(Lang.t("Select a node in the scene first."))
		return

	_target = selected[0]
	## Attaching or removing here would only override this one instance.
	if _is_instance(_target):
		_set_status(Lang.t("%s is an instanced scene - open %s to change it.") % [_target.name, _target.scene_file_path.get_file()])
		return
	if _target.get_script() == RUNTIME:
		_confirm_detach()
		return

	if _target.get_script() != RUNTIME:
		_target.set_script(RUNTIME)

	DirAccess.make_dir_recursive_absolute(GRAPH_DIR)
	var existing = _target.get("graph")
	if existing is VisuractGraph:
		## Re-attaching a node that already has one keeps its graph.
		_graph_res = existing
		_graph_path = existing.resource_path
	else:
		_graph_path = _unique_graph_path(_target.name)
		_graph_res = VisuractGraph.new()
		_graph_res.take_over_path(_graph_path)
		ResourceSaver.save(_graph_res, _graph_path)

	_target.set("graph", _graph_res)
	_populate_library()
	_load_into_canvas()
	_set_status(Lang.t("Attached to: %s") % _target.name)
	_refresh_attach_button()
	_save_scene_soon()


func _is_instance(node: Node) -> bool:
	return node.scene_file_path != "" and node != EditorInterface.get_edited_scene_root()


## The graph the instanced scene's own root uses.
func _source_graph(node: Node) -> Resource:
	var state := (load(node.scene_file_path) as PackedScene).get_state()
	for i in state.get_node_property_count(0):
		if state.get_node_property_name(0, i) == &"graph":
			return state.get_node_property_value(0, i)
	return null


## Only worth asking when there are blocks to lose.
func _confirm_detach() -> void:
	var blocks := _graph_res.nodes.size() if _graph_res != null else 0
	if blocks == 0:
		_detach()
		return
	_confirm.dialog_text = Lang.t("Remove Visuract from %s?\n\nIts %d blocks will be forgotten.") % [_target.name, blocks]
	_confirm.popup_centered()


## A fresh node never inherits an old graph that happens to share its name.
func _unique_graph_path(node_name: String) -> String:
	var base := "%s/%s" % [GRAPH_DIR, node_name]
	if not ResourceLoader.exists(base + ".tres"):
		return base + ".tres"
	var suffix := 2
	while ResourceLoader.exists("%s_%d.tres" % [base, suffix]):
		suffix += 1
	return "%s_%d.tres" % [base, suffix]


## Leaves the .tres on disk, but the node forgets it - re-attaching starts fresh.
func _detach() -> void:
	var node_name := _target.name
	_target.set("graph", null)
	_target.set_script(null)
	_clear_canvas()
	_set_status(Lang.t("Removed Visuract from %s") % node_name)
	_populate_library()
	_refresh_attach_button()
	_save_scene_soon()


## Deferred, so the save never runs inside the button's own signal.
func _save_scene_soon() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root != null and root.scene_file_path != "":
		_do_save_scene.call_deferred()


func _do_save_scene() -> void:
	EditorInterface.save_scene()


func _on_save_pressed() -> void:
	if _graph_res == null:
		_set_status(Lang.t("Attach to a node first."))
		return

	_graph_res.nodes.clear()
	_graph_res.connections.clear()

	for child in _graph.get_children():
		if child is GraphNode:
			_graph_res.nodes.append({
				"id": String(child.name),
				"type": _type_of(child),
				"position": child.position_offset,
				"params": _read_params(child),
			})

	for c in _graph.get_connection_list():
		_graph_res.connections.append({
			"from": String(c.get("from_node", c.get("from", ""))),
			"to": String(c.get("to_node", c.get("to", ""))),
		})

	var error := ResourceSaver.save(_graph_res, _graph_path)
	if error != OK:
		_set_status(Lang.t("Save failed (%d): %s") % [error, _graph_path])
		return
	EditorInterface.get_resource_filesystem().scan()
	_set_status(Lang.t("Saved %d nodes to %s") % [_graph_res.nodes.size(), _graph_path])


func _load_into_canvas(frame := true) -> void:
	var resource := _graph_res
	var path := _graph_path
	_clear_canvas()
	_graph_res = resource
	_graph_path = path

	_loading = true
	for n in _graph_res.nodes:
		_make_graph_node(n.type, n.position, n.id, n.get("params", {}))
	for c in _graph_res.connections:
		_graph.connect_node(c.from, 0, c.to, 0)
	_refresh_conditional_params()
	_refresh_run_order()
	_loading = false
	_last_state = _snapshot()
	if frame:
		_graph.frame_nodes()


func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	_graph.connect_node(from_node, from_port, to_node, to_port)
	_refresh_conditional_params()
	_autosave()


func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	_graph.disconnect_node(from_node, from_port, to_node, to_port)
	_refresh_conditional_params()
	_autosave()
