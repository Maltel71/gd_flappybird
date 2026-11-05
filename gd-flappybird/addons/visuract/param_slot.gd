@tool
extends Button

signal value_changed
const Lang := preload("res://addons/visuract/visuract_lang.gd")

## "node" (accepts Scene dock drops) or "file" (accepts FileSystem drops).
var kind := "node"
var value := ""
var options: Array = []
## Optional Callable(String) -> String, used to shorten dropped node paths.
var normalizer: Callable

var _popup: PopupPanel
var _search: LineEdit
var _list: ItemList


func _ready() -> void:
	pressed.connect(_open_picker)
	refresh()


func refresh() -> void:
	if value == "":
		text = Lang.t("Pick a node") if kind == "node" else Lang.t("Pick a file")
	elif value == ".":
		text = Lang.t("(this node)")
		tooltip_text = Lang.t("The node this script is on")
	else:
		var path := value
		if path.begins_with("uid://"):
			path = ResourceUID.get_id_path(ResourceUID.text_to_id(path)) if ResourceUID.has_id(ResourceUID.text_to_id(path)) else Lang.t("(missing file)")
		text = path.get_file()
		tooltip_text = path


func _build_picker() -> void:
	_popup = PopupPanel.new()
	add_child(_popup)
	var box := VBoxContainer.new()
	_popup.add_child(box)
	_search = LineEdit.new()
	_search.placeholder_text = Lang.t("Search")
	_search.clear_button_enabled = true
	_search.text_changed.connect(_fill_list)
	_search.gui_input.connect(_on_search_input)
	box.add_child(_search)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_pick)
	box.add_child(_list)


## A short filtered list beats a popup menu taller than the screen.
func _open_picker() -> void:
	if _popup == null:
		_build_picker()
	_search.text = ""
	_fill_list("")
	var at := get_screen_position() + Vector2(0, size.y)
	_popup.popup(Rect2i(Vector2i(at), Vector2i(maxi(int(size.x), 320), 280)))
	_search.grab_focus()


func _fill_list(filter: String) -> void:
	_list.clear()
	var words := filter.to_lower().split(" ", false)
	for i in options.size():
		var option := String(options[i])
		if not _matches(option.to_lower(), words):
			continue
		var label := option
		if kind == "file" and option.begins_with("res://"):
			label = "%s    %s" % [option.get_file(), option.get_base_dir().trim_prefix("res://")]
		var row := _list.add_item(Lang.t(label))
		_list.set_item_tooltip(row, option)
		_list.set_item_metadata(row, i)
	if _list.item_count == 0:
		_list.set_item_disabled(_list.add_item(Lang.t("(nothing available)")), true)
	else:
		_list.select(0)


func _matches(haystack: String, words: PackedStringArray) -> bool:
	for word in words:
		if not haystack.contains(word):
			return false
	return true


func _on_search_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	match event.keycode:
		KEY_DOWN, KEY_UP:
			var rows := _list.get_selected_items()
			var from := rows[0] if rows.size() > 0 else 0
			_list.select(clampi(from + (1 if event.keycode == KEY_DOWN else -1), 0, _list.item_count - 1))
			_list.ensure_current_is_visible()
			accept_event()
		KEY_ENTER, KEY_KP_ENTER:
			var rows := _list.get_selected_items()
			if rows.size() > 0:
				_pick(rows[0])
			accept_event()


func _pick(row: int) -> void:
	if _list.is_item_disabled(row):
		return
	_popup.hide()
	value = String(options[int(_list.get_item_metadata(row))])
	## Files are kept by UID, so renaming or moving them never breaks the block.
	if kind == "file" and ResourceLoader.exists(value):
		value = ResourceUID.id_to_text(ResourceLoader.get_resource_uid(value))
	refresh()
	value_changed.emit()


## Dropping from the Scene dock is deliberately not supported: the dock
## changes the editor selection as the drag starts, which swaps the graph out
## from under it. Click the slot and pick from the list instead.
