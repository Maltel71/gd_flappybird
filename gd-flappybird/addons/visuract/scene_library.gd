@tool
extends PanelContainer

## Ready-made scenes ("prefabs") the students drag into their level. Any
## .tscn under PREFAB_DIR shows up; a subfolder name becomes its subtitle.
## A prefab saved with a Visuract script keeps it when it's dropped in.

const Card := preload("res://addons/visuract/library_card.gd")
const RUNTIME := preload("res://addons/visuract/visuract_runtime.gd")
const PREFAB_DIR := "res://visuract/prefabs"
## A "<prefab>_tn" image here replaces the auto preview on that prefab's card.
const THUMBNAIL_DIR := "res://visuract/scene_library_thumbnails"
const THUMBNAIL_EXTENSIONS := ["png", "jpg", "jpeg", "webp", "svg"]
const CARD_SIZE := Vector2(140, 160)
const DIALOGUE_PREFAB := PREFAB_DIR + "/dialogue_label.tscn"
const Lang := preload("res://addons/visuract/visuract_lang.gd")
const HEALTH_BAR_PREFAB := PREFAB_DIR + "/health_bar.tscn"
const BUTTON_PREFAB := PREFAB_DIR + "/button.tscn"

var _grid: HFlowContainer
var _empty_hint: Label


func _ready() -> void:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var heading := Label.new()
	heading.text = Lang.t("Visuract Scene Library")
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 32)
	column.add_child(heading)

	var hint := Label.new()
	hint.text = Lang.t("Drag a scene onto a node in the Scene dock.")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	column.add_child(hint)

	_empty_hint = Label.new()
	_empty_hint.text = Lang.t("No scenes yet - save some into %s") % PREFAB_DIR
	_empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_empty_hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	_grid = HFlowContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.alignment = FlowContainer.ALIGNMENT_CENTER
	_grid.add_theme_constant_override("h_separation", 16)
	_grid.add_theme_constant_override("v_separation", 16)
	scroll.add_child(_grid)


## Rescans every time it's shown, so newly saved prefabs appear without a restart.
func refresh() -> void:
	for child in _grid.get_children():
		child.queue_free()
	DirAccess.make_dir_recursive_absolute(PREFAB_DIR)
	DirAccess.make_dir_recursive_absolute(THUMBNAIL_DIR)
	_ensure_dialogue_prefab()
	_ensure_health_bar_prefab()
	_ensure_button_prefab()
	var paths := _scene_paths()
	for path in paths:
		_grid.add_child(_make_card(path))
	_empty_hint.visible = paths.is_empty()


## A ready-made Label for the Dialogue node, so there's always one to drag in.
func _ensure_dialogue_prefab() -> void:
	if FileAccess.file_exists(DIALOGUE_PREFAB):
		return
	var label := Label.new()
	label.name = "DialogueLabel"
	label.text = "Hello there!"
	label.size = Vector2(240, 60)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.label_settings = LabelSettings.new()
	label.label_settings.font_size = 20
	label.label_settings.outline_size = 6
	label.label_settings.outline_color = Color.BLACK
	var packed := PackedScene.new()
	packed.pack(label)
	ResourceSaver.save(packed, DIALOGUE_PREFAB)
	label.free()


## A ready-made bar for the Health node. Drop it under a player, enemy or door.
func _ensure_health_bar_prefab() -> void:
	if FileAccess.file_exists(HEALTH_BAR_PREFAB):
		return
	var bar := ProgressBar.new()
	bar.name = "HealthBar"
	bar.set_script(preload("res://addons/visuract/health_bar.gd"))
	bar.position = Vector2(-24, -40)
	bar.size = Vector2(48, 6)
	bar.show_percentage = false
	bar.value = 100.0
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.15, 0.15, 0.15)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("e04b4b")
	bar.add_theme_stylebox_override("background", back)
	bar.add_theme_stylebox_override("fill", fill)
	var packed := PackedScene.new()
	packed.pack(bar)
	ResourceSaver.save(packed, HEALTH_BAR_PREFAB)
	bar.free()


## A rounded button for the Juicy Button node. No Visuract script, so every
## copy gets its own graph when you attach.
func _ensure_button_prefab() -> void:
	if FileAccess.file_exists(BUTTON_PREFAB):
		return
	var button := Button.new()
	button.name = "Button"
	button.text = "Play"
	button.size = Vector2(160, 56)
	button.add_theme_font_size_override("font_size", 22)
	for state in ["normal", "hover", "pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color("4b8fe0") if state == "normal" else Color("4b8fe0").lightened(0.15)
		box.set_corner_radius_all(12)
		button.add_theme_stylebox_override(state, box)
	var packed := PackedScene.new()
	packed.pack(button)
	ResourceSaver.save(packed, BUTTON_PREFAB)
	button.free()


func _scene_paths() -> Array:
	var out := []
	var dirs := [PREFAB_DIR]
	while not dirs.is_empty():
		var dir: String = dirs.pop_front()
		for sub in DirAccess.get_directories_at(dir):
			dirs.append(dir.path_join(sub))
		for file in DirAccess.get_files_at(dir):
			if file.get_extension() == "tscn":
				out.append(dir.path_join(file))
	return out


func _make_card(path: String) -> Button:
	var card := Card.new()
	card.scene_path = path
	card.custom_minimum_size = CARD_SIZE
	card.expand_icon = true
	card.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	card.icon = EditorInterface.get_base_control().get_theme_icon("PackedScene", "EditorIcons")
	card.text = path.get_file().get_basename().capitalize()
	if path.get_base_dir() != PREFAB_DIR:
		card.text += "\n" + path.get_base_dir().get_file().capitalize()
	card.tooltip_text = path
	if _has_visuract(path):
		card.text = "\u26a1 " + card.text
		card.tooltip_text += "\n" + Lang.t("Comes with a Visuract script.")
	var thumbnail := _thumbnail_of(path)
	if thumbnail:
		card.icon = thumbnail
	else:
		EditorInterface.get_resource_previewer().queue_resource_preview(path, self, "_on_preview_ready", card)
	return card


func _thumbnail_of(path: String) -> Texture2D:
	var base := THUMBNAIL_DIR.path_join(path.get_file().get_basename() + "_tn.")
	for extension in THUMBNAIL_EXTENSIONS:
		if ResourceLoader.exists(base + extension):
			return load(base + extension)
	return null


func _has_visuract(path: String) -> bool:
	var packed := load(path) as PackedScene
	if packed == null or packed.get_state().get_node_count() == 0:
		return false
	var state := packed.get_state()
	for i in state.get_node_property_count(0):
		if state.get_node_property_name(0, i) == &"script":
			return state.get_node_property_value(0, i) == RUNTIME
	return false


func _on_preview_ready(_path: String, preview: Texture2D, _thumbnail: Texture2D, card) -> void:
	if preview and is_instance_valid(card):
		card.icon = preview
