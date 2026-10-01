# level_button.gd
@tool
extends Control

## One level entry in the level select.
##
## Attach this to the root of your panel scene:
##   LevelButton_Control        (Control, this script)
##   ├── BG_Panel_TextureRect   (TextureRect, your panel art)
##   └── Thumbnail_TextureRect  (TextureRect, per-level thumbnail)
##
## A title Label and an invisible, focusable Button are created in code,
## so you don't have to add them by hand. They are not saved into the scene.
## @tool means the editor preview updates when you change values here.

signal pressed
signal hovered

@export var thumbnail: Texture2D:
	set(value):
		thumbnail = value
		_apply_thumbnail()

@export var title: String = "":
	set(value):
		title = value
		_apply_title()

@export var disabled: bool = false:
	set(value):
		disabled = value
		_apply_disabled()

@export_group("Layout")

## Smallest size of one panel. With Expand To Fill on, panels grow past this
## to share the grid's space evenly.
@export var panel_min_size: Vector2 = Vector2(360, 260):
	set(value):
		panel_min_size = value
		_refresh_layout()

## Let panels stretch to fill the grid. Turn off to keep every panel
## exactly Panel Min Size (useful if stretching distorts your panel art).
@export var expand_to_fill: bool = true:
	set(value):
		expand_to_fill = value
		_refresh_layout()

## Gap between the panel edge and the thumbnail, in pixels.
@export var thumbnail_margin: int = 20:
	set(value):
		thumbnail_margin = value
		_refresh_layout()

## Space reserved at the bottom of the panel for the title.
@export var title_height: int = 56:
	set(value):
		title_height = value
		_refresh_layout()

@export var title_font_size: int = 36:
	set(value):
		title_font_size = value
		_refresh_layout()

## Dark outline around the title so it reads on any panel art. 0 turns it off.
@export var title_outline_size: int = 8:
	set(value):
		title_outline_size = value
		_refresh_layout()

@export_group("Animation")

## Size when hovered or selected with keyboard/controller. 1.0 = no change.
@export_range(1.0, 1.5, 0.01) var hover_scale: float = 1.08

## Size while the mouse button is held down on it.
@export_range(0.5, 1.0, 0.01) var pressed_scale: float = 0.9

## How long the grow/shrink takes, in seconds.
@export_range(0.01, 1.0, 0.01) var scale_time: float = 0.15

## How far it leans counter-clockwise when hovered. 0 turns the tilt off.
## Use a negative number to lean clockwise instead.
@export_range(-15.0, 15.0, 0.5) var tilt_degrees: float = 3.0

## How long the lean takes, in seconds.
@export_range(0.01, 1.0, 0.01) var tilt_time: float = 0.2

## Brightness boost while hovered. 1.0 = no change.
@export_range(1.0, 2.0, 0.01) var hover_brightness: float = 1.15

## Wait this long after the click before loading the level, so the
## bounce-back animation is visible instead of cut off by the scene change.
@export_range(0.0, 1.0, 0.01) var press_delay: float = 0.15

@export_group("")

@onready var bg_panel: TextureRect = $BG_Panel_TextureRect
@onready var thumbnail_rect: TextureRect = $Thumbnail_TextureRect

var _button: Button
var _label: Label

var _mouse_over: bool = false
var _focused: bool = false
var _held: bool = false
var _highlighted: bool = false
var _press_pending: bool = false

var _scale_tween: Tween
var _tilt_tween: Tween


func _ready() -> void:
	_refresh_layout()

	# The clickable hit box and animations only matter in the running game.
	if not Engine.is_editor_hint():
		_ensure_button()
		# Scale and rotate around the middle, not the top-left corner.
		resized.connect(_update_pivot)
		_update_pivot()

	_apply_thumbnail()
	_apply_title()
	_apply_disabled()


func _update_pivot() -> void:
	pivot_offset = size / 2.0


# --- Layout ------------------------------------------------------------------

func _refresh_layout() -> void:
	if not is_node_ready():
		return

	custom_minimum_size = panel_min_size
	var flags: int = Control.SIZE_EXPAND_FILL if expand_to_fill else Control.SIZE_SHRINK_CENTER
	size_flags_horizontal = flags
	size_flags_vertical = flags

	_setup_panel()
	_setup_thumbnail()
	_ensure_label()


func _setup_panel() -> void:
	if bg_panel == null:
		push_warning("LevelButton: no child named 'BG_Panel_TextureRect'.")
		return
	bg_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_panel.stretch_mode = TextureRect.STRETCH_SCALE


func _setup_thumbnail() -> void:
	if thumbnail_rect == null:
		push_warning("LevelButton: no child named 'Thumbnail_TextureRect'.")
		return
	thumbnail_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	thumbnail_rect.offset_left = thumbnail_margin
	thumbnail_rect.offset_top = thumbnail_margin
	thumbnail_rect.offset_right = -thumbnail_margin
	thumbnail_rect.offset_bottom = -(thumbnail_margin + title_height)
	thumbnail_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumbnail_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumbnail_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED


func _ensure_label() -> void:
	_label = get_node_or_null("Title_Label") as Label
	if _label == null:
		_label = Label.new()
		_label.name = "Title_Label"
		add_child(_label)  # no owner set, so it is never saved into the scene

	_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_label.offset_left = thumbnail_margin
	_label.offset_right = -thumbnail_margin
	_label.offset_top = -(title_height + thumbnail_margin / 2)
	_label.offset_bottom = -(thumbnail_margin / 2)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_label.add_theme_font_size_override("font_size", title_font_size)
	_label.add_theme_constant_override("outline_size", title_outline_size)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)

	_keep_button_on_top()


func _ensure_button() -> void:
	_button = get_node_or_null("HitBox_Button") as Button
	if _button == null:
		_button = Button.new()
		_button.name = "HitBox_Button"
		add_child(_button)

	# Invisible hit box: the panel art is the visuals, the Button is the input.
	_button.flat = true
	_button.text = ""
	# Hide Godot's white focus rectangle; the grow + tilt shows selection instead.
	_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_button.focus_mode = Control.FOCUS_ALL
	_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_keep_button_on_top()

	_button.pressed.connect(_on_button_pressed)
	_button.button_down.connect(_on_button_down)
	_button.button_up.connect(_on_button_up)
	_button.mouse_entered.connect(_on_mouse_entered)
	_button.mouse_exited.connect(_on_mouse_exited)
	_button.focus_entered.connect(_on_focus_entered)
	_button.focus_exited.connect(_on_focus_exited)


func _keep_button_on_top() -> void:
	if _button and _button.get_parent() == self:
		move_child(_button, get_child_count() - 1)


# --- Applying values ---------------------------------------------------------

func _apply_thumbnail() -> void:
	if not is_node_ready() or thumbnail_rect == null:
		return
	thumbnail_rect.texture = thumbnail
	thumbnail_rect.visible = thumbnail != null


func _apply_title() -> void:
	if not is_node_ready():
		return
	if _label:
		_label.text = title
		_label.visible = title != ""
	if _button:
		_button.tooltip_text = title


func _apply_disabled() -> void:
	if not is_node_ready():
		return
	if _button:
		_button.disabled = disabled
	if disabled:
		_highlighted = false
		_held = false
		scale = Vector2.ONE
		rotation = 0.0
	_refresh_modulate()


func _refresh_modulate() -> void:
	if disabled:
		modulate = Color(1, 1, 1, 0.45)
	elif _highlighted:
		modulate = Color(hover_brightness, hover_brightness, hover_brightness)
	else:
		modulate = Color.WHITE


# --- Public helpers (used by level_select_menu.gd) ---------------------------

func grab_button_focus() -> void:
	if _button and not _button.disabled:
		_button.grab_focus()


func set_tooltip(text: String) -> void:
	if _button:
		_button.tooltip_text = text


# --- Input + animation -------------------------------------------------------

func _on_mouse_entered() -> void:
	_mouse_over = true
	# Move keyboard focus here too, so the mouse and arrow keys share one
	# highlight and a previously focused panel lets go.
	if _button and not disabled:
		_button.grab_focus()
	_update_highlight()


func _on_mouse_exited() -> void:
	_mouse_over = false
	if _button and _button.has_focus():
		_button.release_focus()
	_update_highlight()


func _on_focus_entered() -> void:
	_focused = true
	_update_highlight()


func _on_focus_exited() -> void:
	_focused = false
	_update_highlight()


func _update_highlight() -> void:
	var now: bool = (_mouse_over or _focused) and not disabled
	if now == _highlighted:
		return
	_highlighted = now

	# Draw on top of neighbours while enlarged, so it doesn't slide under them.
	z_index = 1 if _highlighted else 0
	_refresh_modulate()

	if _highlighted:
		_tween_scale(pressed_scale if _held else hover_scale)
		_tween_tilt(-deg_to_rad(tilt_degrees))
		hovered.emit()
	else:
		_held = false
		_tween_scale(1.0)
		_tween_tilt(0.0)


func _on_button_down() -> void:
	if disabled:
		return
	_held = true
	# Quick squish: faster than the hover grow so the click feels snappy.
	_tween_scale(pressed_scale, scale_time * 0.5, Tween.TRANS_QUAD)


func _on_button_up() -> void:
	_held = false
	_tween_scale(hover_scale if _highlighted else 1.0)


func _on_button_pressed() -> void:
	if _press_pending:
		return
	_press_pending = true

	if press_delay > 0.0:
		await get_tree().create_timer(press_delay).timeout

	_press_pending = false
	pressed.emit()


func _tween_scale(target: float, time: float = -1.0, trans: Tween.TransitionType = Tween.TRANS_BACK) -> void:
	if time < 0.0:
		time = scale_time
	if _scale_tween:
		_scale_tween.kill()
	_scale_tween = create_tween()
	_scale_tween.set_trans(trans).set_ease(Tween.EASE_OUT)
	_scale_tween.tween_property(self, "scale", Vector2.ONE * target, time)


func _tween_tilt(target_radians: float) -> void:
	if _tilt_tween:
		_tilt_tween.kill()
	_tilt_tween = create_tween()
	# TRANS_BACK overshoots slightly, which gives the lean a little life.
	_tilt_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tilt_tween.tween_property(self, "rotation", target_radians, tilt_time)
