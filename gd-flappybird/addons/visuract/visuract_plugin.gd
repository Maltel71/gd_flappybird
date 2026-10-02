@tool
extends EditorPlugin

const MainPanel := preload("res://addons/visuract/visuract_main.gd")

var _main_panel: MainPanel


func _enter_tree() -> void:
	_main_panel = MainPanel.new()
	_main_panel.undo_redo = get_undo_redo()
	_main_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	EditorInterface.get_editor_main_screen().add_child(_main_panel)
	_make_visible(false)


func _exit_tree() -> void:
	if _main_panel:
		_main_panel.queue_free()


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if _main_panel:
		_main_panel.visible = visible


func _get_plugin_name() -> String:
	return "Visuract"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_base_control().get_theme_icon("Node", "EditorIcons")
