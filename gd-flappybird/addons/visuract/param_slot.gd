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

var _menu: PopupMenu


func _ready() -> void:
	_menu = PopupMenu.new()
	_menu.id_pressed.connect(_on_menu_pressed)
	add_child(_menu)
	pressed.connect(_open_menu)
	refresh()


func refresh() -> void:
	if value == "":
		text = Lang.t("Pick a node") if kind == "node" else Lang.t("Pick a file")
	elif value == ".":
		text = Lang.t("(this node)")
		tooltip_text = Lang.t("The node this script is on")
	else:
		text = value.get_file()
		tooltip_text = value


func _open_menu() -> void:
	_menu.clear()
	for i in options.size():
		_menu.add_item(Lang.t(String(options[i])), i)
	if options.is_empty():
		_menu.add_item(Lang.t("(nothing available)"), -1)
	_menu.popup(Rect2i(DisplayServer.mouse_get_position(), Vector2i.ZERO))


func _on_menu_pressed(id: int) -> void:
	if id < 0:
		return
	value = String(options[id])
	refresh()
	value_changed.emit()


## Dropping from the Scene dock is deliberately not supported: the dock
## changes the editor selection as the drag starts, which swaps the graph out
## from under it. Click the slot and pick from the list instead.
