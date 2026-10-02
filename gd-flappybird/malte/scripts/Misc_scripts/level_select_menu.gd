# level_select_menu.gd
extends Control

## Level select that builds its own buttons from the lists below.
## To add a student's level: add one entry to `level_scenes` in the Inspector.
## Optionally add matching entries to `level_names` (button label) and
## `level_thumbnails` (preview image). Entries are matched by index, so
## element 0 of each array belongs to the same level.
##
## Assign `level_button_scene` to your panel scene (LevelButton_Control.tscn).
## If it's left empty, plain Buttons are used as a fallback.
##
## Expected scene tree (node names are case-sensitive):
##   LevelSelectMenu      (Control, this script)
##   ├── Panel
##   │   └── GridContainer
##   ├── VBoxContainer
##   │   └── MainMenuButton
##   └── AudioStreamPlayer

## The panel scene instantiated once per level. Root should use level_button.gd.
@export var level_button_scene: PackedScene

@export_file("*.tscn") var level_scenes: Array[String] = []
@export var level_names: Array[String] = []

## One thumbnail per level, in the same order as `level_scenes`.
@export var level_thumbnails: Array[Texture2D] = []

@export_group("Grid Layout")

## How many panels per row. 0 leaves the GridContainer's own setting alone.
@export_range(0, 8) var grid_columns: int = 3

## Stretch the GridContainer to fill the Panel (minus Grid Margin).
## Turn off if you want to position the GridContainer by hand.
@export var fit_grid_to_panel: bool = true

## Empty space between the Panel edge and the level buttons, in pixels.
@export var grid_margin: int = 40

## Gap between level buttons, in pixels.
@export var grid_spacing: int = 24

@export_group("")

@export var hover_sound: AudioStream
@export_range(-80, 24) var hover_volume: float = 0.0

## Set this to the bus name that actually exists in this project.
## Leave empty to use the default Master bus.
@export var sfx_bus: String = "sfx"

@export_file("*.tscn") var main_menu_scene: String = "res://malte/scenes/menus/start_menu.tscn"

var _first_entry: Control = null

@onready var main_menu_button: Button = $VBoxContainer/MainMenuButton
@onready var grid_container: GridContainer = $Panel/GridContainer
@onready var audio_player: AudioStreamPlayer = $AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_setup_audio()

	main_menu_button.pressed.connect(_on_main_menu_pressed)
	main_menu_button.mouse_entered.connect(_on_button_hover)

	_build_level_buttons()


func _setup_audio() -> void:
	if audio_player == null:
		return
	if sfx_bus == "":
		return
	if AudioServer.get_bus_index(sfx_bus) == -1:
		push_warning("Audio bus '%s' does not exist. Falling back to Master." % sfx_bus)
		return
	audio_player.bus = sfx_bus


func _build_level_buttons() -> void:
	# Clear anything placed in the grid by hand, so the list is the only source of truth.
	for child in grid_container.get_children():
		child.queue_free()

	_layout_grid()

	var first_entry: Control = null

	for i in level_scenes.size():
		var path: String = level_scenes[i]
		var is_valid: bool = path != "" and ResourceLoader.exists(path)

		if not is_valid:
			push_warning("Level select: scene not found at '%s' (index %d)." % [path, i])

		var entry: Control = _make_entry(i, path, is_valid)
		grid_container.add_child(entry)

		if first_entry == null and is_valid:
			first_entry = entry

	# Nothing is focused at startup, so no panel looks selected before the
	# player does anything. The first arrow/controller press focuses this one.
	_first_entry = first_entry


func _unhandled_input(event: InputEvent) -> void:
	if _first_entry == null:
		return
	if get_viewport().gui_get_focus_owner() != null:
		return  # something already has focus; normal navigation takes over

	var nav_pressed: bool = (
		event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down")
		or event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right")
		or event.is_action_pressed("ui_focus_next")
	)
	if not nav_pressed:
		return

	if _first_entry.has_method("grab_button_focus"):
		_first_entry.call("grab_button_focus")
	else:
		_first_entry.grab_focus()
	get_viewport().set_input_as_handled()


func _layout_grid() -> void:
	if grid_columns > 0:
		grid_container.columns = grid_columns

	if fit_grid_to_panel:
		grid_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		grid_container.offset_left = grid_margin
		grid_container.offset_top = grid_margin
		grid_container.offset_right = -grid_margin
		grid_container.offset_bottom = -grid_margin

	grid_container.add_theme_constant_override("h_separation", grid_spacing)
	grid_container.add_theme_constant_override("v_separation", grid_spacing)


func _make_entry(index: int, path: String, is_valid: bool) -> Control:
	if level_button_scene == null:
		return _make_plain_button(index, path, is_valid)

	var panel: Control = level_button_scene.instantiate() as Control
	if panel == null:
		push_error("level_button_scene root must be a Control.")
		return _make_plain_button(index, path, is_valid)

	# Set properties directly so this still works if you use your own script,
	# as long as the property names match.
	_set_if_present(panel, "title", _label_for(index, path))
	_set_if_present(panel, "thumbnail", _thumbnail_for(index))
	_set_if_present(panel, "disabled", not is_valid)

	if not is_valid:
		if panel.has_method("set_tooltip"):
			panel.call("set_tooltip", "Missing scene: %s" % path)
		else:
			panel.tooltip_text = "Missing scene: %s" % path
	elif panel.has_signal("pressed"):
		panel.connect("pressed", _on_level_pressed.bind(path))

	if is_valid and panel.has_signal("hovered"):
		panel.connect("hovered", _on_button_hover)

	return panel


func _make_plain_button(index: int, path: String, is_valid: bool) -> Button:
	var btn := Button.new()
	btn.text = _label_for(index, path)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var tex: Texture2D = _thumbnail_for(index)
	if tex != null:
		btn.icon = tex
		btn.expand_icon = true
		btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP

	if not is_valid:
		btn.disabled = true
		btn.tooltip_text = "Missing scene: %s" % path
	else:
		btn.pressed.connect(_on_level_pressed.bind(path))
		btn.mouse_entered.connect(_on_button_hover)

	return btn


func _set_if_present(node: Node, property: String, value: Variant) -> void:
	for prop in node.get_property_list():
		if prop.name == property:
			node.set(property, value)
			return


func _label_for(index: int, path: String) -> String:
	if index < level_names.size() and level_names[index] != "":
		return level_names[index]
	if path == "":
		return "Level %d" % (index + 1)
	return path.get_file().get_basename()


func _thumbnail_for(index: int) -> Texture2D:
	if index < level_thumbnails.size():
		return level_thumbnails[index]
	return null


func _on_level_pressed(path: String) -> void:
	# If you use a MusicManager autoload, stop the menu music here, e.g.
	# MusicManager.stop_music()
	get_tree().change_scene_to_file(path)


func _on_main_menu_pressed() -> void:
	if main_menu_scene == "" or not ResourceLoader.exists(main_menu_scene):
		push_error("Main menu scene path is not set or does not exist.")
		return
	get_tree().change_scene_to_file(main_menu_scene)


func _on_button_hover() -> void:
	if hover_sound and audio_player:
		audio_player.stream = hover_sound
		audio_player.volume_db = hover_volume
		audio_player.play()
