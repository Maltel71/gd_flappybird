@tool
extends EditorContextMenuPlugin

## Renames everything inside one folder from one name to another: the files
## themselves, the folders, and every mention inside scenes, graphs and
## scripts. Made for giving each student their own copy of a folder.

## Stands in for the folder's own path while the swap runs.
const KEEP := "\uFFFF"
const GRAPH_FOLDER := "visuract_graphs"
const TEXT_TYPES := ["tscn", "tres", "gd", "cfg", "json", "tset"]

var _dialog: ConfirmationDialog
var _done: AcceptDialog
var _from: LineEdit
var _to: LineEdit
var _note: Label
var _folder := ""


func _popup_menu(paths: PackedStringArray) -> void:
	if paths.size() == 1 and DirAccess.dir_exists_absolute(paths[0]):
		add_context_menu_item("Rename for Student...", _open.bind(paths[0]))


## The bound folder arrives after the selection the menu passes in.
func _open(_selected: Array, folder: String) -> void:
	_folder = folder.rstrip("/")
	_build_dialog()
	_from.text = _guess_name()
	_to.text = ""
	_note.text = "Renames every file, folder and mention inside:\n%s" % _folder
	_dialog.popup_centered(Vector2i(440, 260))
	_to.grab_focus()


## The word most file names in the folder start with, which is almost always
## the student the folder was copied from.
func _guess_name() -> String:
	var counts := {}
	for file in _all_files(_folder):
		var first: String = String(file).get_file().get_basename().split("_")[0]
		if first != "":
			counts[first] = counts.get(first, 0) + 1
	var best := ""
	for word in counts:
		if best == "" or counts[word] > counts[best]:
			best = word
	return best


func _build_dialog() -> void:
	if is_instance_valid(_dialog):
		return
	_dialog = ConfirmationDialog.new()
	_dialog.title = "Visuract - Rename for Student"
	_dialog.ok_button_text = "Rename"
	_dialog.confirmed.connect(_apply)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_note = _wrapped_label(box)

	var grid := GridContainer.new()
	grid.columns = 2
	_from = _add_field(grid, "Replace:")
	_to = _add_field(grid, "With:")
	box.add_child(grid)

	var warning := _wrapped_label(box)
	warning.text = "Save and close your scenes first. Only this folder is changed."
	warning.add_theme_color_override("font_color", Color("c9a227"))

	_dialog.add_child(box)
	EditorInterface.get_base_control().add_child(_dialog)


## A wrapping label needs a width, or it asks for a dialog taller than the
## screen and the buttons end up out of reach.
func _wrapped_label(box: VBoxContainer) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(400, 0)
	box.add_child(label)
	return label


func _add_field(grid: GridContainer, text: String) -> LineEdit:
	var label := Label.new()
	label.text = text
	grid.add_child(label)
	var edit := LineEdit.new()
	edit.custom_minimum_size.x = 240
	grid.add_child(edit)
	return edit


func _apply() -> void:
	var from := _from.text.strip_edges()
	var to := _to.text.strip_edges()
	if from == "" or to == "" or from == to:
		return
	EditorInterface.save_all_scenes()
	var copied := _localize_graphs()

	var edited := 0
	## Contents first, while every file is still where the paths say it is.
	for file: String in _all_files(_folder):
		if not TEXT_TYPES.has(file.get_extension()):
			continue
		var text := FileAccess.get_file_as_string(file)
		## The folder itself is never renamed, so paths starting with it must
		## come through the swap untouched - res://malte/scenes/aaritro/...
		var swapped := _swap(text.replace(_folder, KEEP), from, to).replace(KEEP, _folder)
		if swapped != text:
			var writer := FileAccess.open(file, FileAccess.WRITE)
			if writer != null:
				writer.store_string(swapped)
				edited += 1

	## Then the names, deepest first, so a folder is only renamed once what
	## is inside it has been.
	var renamed := 0
	for path: String in _all_paths(_folder):
		var file := path.get_file()
		var swapped := _swap(file, from, to)
		if swapped != file:
			DirAccess.rename_absolute(path, path.get_base_dir().path_join(swapped))
			renamed += 1

	EditorInterface.get_resource_filesystem().scan()
	print("Visuract: renamed %s to %s - %d files and folders." % [from, to, renamed])
	_report(from, to, copied, edited, renamed)


func _report(from: String, to: String, copied: int, edited: int, renamed: int) -> void:
	if not is_instance_valid(_done):
		_done = AcceptDialog.new()
		_done.title = "Visuract - Done"
		EditorInterface.get_base_control().add_child(_done)
	_done.dialog_text = "Renamed %s to %s.\n\n%d graphs copied into the folder\n%d files updated inside\n%d files and folders renamed" % [from, to, copied, edited, renamed]
	_done.popup_centered()


## Copies any graph a scene points at from outside the folder to beside it,
## so the renaming below reaches it. Done on disk - no scene is opened.
func _localize_graphs() -> int:
	var copied := 0
	for scene: String in _all_files(_folder):
		if scene.get_extension() != "tscn":
			continue
		var text := FileAccess.get_file_as_string(scene)
		var dir := scene.get_base_dir().path_join(GRAPH_FOLDER)
		var changed := text
		for line in text.split("\n"):
			if not line.begins_with("[ext_resource") or not line.contains(".tres"):
				continue
			var path := _quoted(line, "path")
			if path.get_base_dir() == dir or not _is_graph(path):
				continue
			var here := dir.path_join(path.get_file())
			DirAccess.make_dir_recursive_absolute(dir)
			if not FileAccess.file_exists(here):
				DirAccess.copy_absolute(path, here)
				copied += 1
			changed = changed.replace(line, _without_uid(line).replace(path, here))
		if changed != text:
			var writer := FileAccess.open(scene, FileAccess.WRITE)
			if writer != null:
				writer.store_string(changed)
	return copied


func _is_graph(path: String) -> bool:
	return path.ends_with(".tres") and FileAccess.get_file_as_string(path).contains("visuract_graph.gd")


## The value of one key="value" pair on an ext_resource line.
func _quoted(line: String, key: String) -> String:
	var start := line.find('%s="' % key)
	if start == -1:
		return ""
	start += key.length() + 2
	return line.substr(start, line.find('"', start) - start)


## The copy sits at a new path, so the old uid would only start an argument.
func _without_uid(line: String) -> String:
	var start := line.find('uid="')
	if start == -1:
		return line
	return line.substr(0, start) + line.substr(line.find('"', start + 5) + 1).lstrip(" ")


## Keeps the capitalisation it finds, so Malte_Player becomes Aaritro_Player.
func _swap(text: String, from: String, to: String) -> String:
	return text.replace(from.to_lower(), to.to_lower()) \
		.replace(_capitalized(from), _capitalized(to)) \
		.replace(from.to_upper(), to.to_upper())


func _capitalized(word: String) -> String:
	return word.substr(0, 1).to_upper() + word.substr(1).to_lower()


func _all_files(dir: String) -> Array:
	return _all_paths(dir).filter(func(path): return not DirAccess.dir_exists_absolute(path))


## Every file and folder inside, children before their parent.
func _all_paths(dir: String) -> Array:
	var out := []
	for sub in DirAccess.get_directories_at(dir):
		var path := dir.path_join(sub)
		out.append_array(_all_paths(path))
		out.append(path)
	for file in DirAccess.get_files_at(dir):
		out.append(dir.path_join(file))
	return out
