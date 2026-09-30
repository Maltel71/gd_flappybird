extends Control

## Level select that builds its own buttons from the list below.
## To add a student's level: add one entry to `level_scenes` in the Inspector.
## Optionally add a matching entry to `level_names` for the button label.
## If `level_names` is shorter than `level_scenes`, the filename is used.

@export_file("*.tscn") var level_scenes: Array[String] = []
@export var level_names: Array[String] = []

@export var hover_sound: AudioStream
@export_range(-80, 24) var hover_volume: float = 0.0

## Set this to the bus name that actually exists in this project.
## Leave empty to use the default Master bus.
@export var sfx_bus: String = ""

@export_file("*.tscn") var main_menu_scene: String = ""

@onready var main_menu_button: Button = $Panel/VBoxContainer/MainMenuButton
@onready var grid_container: GridContainer = $Panel/GridContainer
@onready var audio_player: AudioStreamPlayer = $AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_setup_audio()

	main_menu_button.pressed.connect(_on_main_menu_pressed)
	_connect_hover(main_menu_button)

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

	var first_button: Button = null

	for i in level_scenes.size():
		var path: String = level_scenes[i]

		var btn := Button.new()
		btn.text = _label_for(i, path)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		if path == "" or not ResourceLoader.exists(path):
			btn.disabled = true
			btn.tooltip_text = "Missing scene: %s" % path
			push_warning("Level select: scene not found at '%s' (index %d)." % [path, i])
		else:
			btn.pressed.connect(_on_level_pressed.bind(path))
			_connect_hover(btn)

		grid_container.add_child(btn)

		if first_button == null and not btn.disabled:
			first_button = btn

	# Let keyboard and controller players navigate without a mouse.
	if first_button != null:
		first_button.grab_focus()


func _label_for(index: int, path: String) -> String:
	if index < level_names.size() and level_names[index] != "":
		return level_names[index]
	if path == "":
		return "Level %d" % (index + 1)
	return path.get_file().get_basename()


func _connect_hover(btn: Button) -> void:
	if hover_sound and audio_player:
		btn.mouse_entered.connect(_on_button_hover)


func _on_level_pressed(path: String) -> void:
	# If you use a MusicManager autoload, stop the menu music here, e.g.
	# if Engine.has_singleton("MusicManager"): MusicManager.stop_music()
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
