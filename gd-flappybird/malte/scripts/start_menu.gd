# start_menu.gd
extends Control

@export var game_scene_path: String = "res://levels/car_level_1.tscn"  # Update this path
@export var hover_sound: AudioStream
@export_range(-80, 24) var hover_volume: float = 0.0
@export_range(-80, 24) var menu_music_volume: float = 0.0

@export_group("Button Animation")

## Size when hovered or selected with keyboard/controller. 1.0 = no change.
@export_range(1.0, 1.5, 0.01) var hover_scale: float = 1.12

## Size while the mouse button is held down.
@export_range(0.5, 1.0, 0.01) var pressed_scale: float = 0.94

## How far past the target it swings before settling back. This is the
## wiggle. 0 turns it off and the scaling becomes a plain glide.
@export_range(0.0, 0.3, 0.01) var overshoot: float = 0.07

## How long the whole grow/shrink takes, in seconds.
@export_range(0.03, 1.0, 0.01) var scale_time: float = 0.1

@export_group("")

@onready var play_button = $Panel/VBoxContainer/PlayButton
@onready var settings_button = $Panel/VBoxContainer/SettingsButton
@onready var quit_button = $Panel/VBoxContainer/QuitButton
@onready var audio_player = $AudioStreamPlayer

@export var menu_music: AudioStream

# One running tween per button, so a new animation can cancel the old one.
var _scale_tweens: Dictionary = {}

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	if audio_player:
		audio_player.bus = "sfx"
	
	play_button.pressed.connect(_on_play_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	
	for button in [play_button, settings_button, quit_button]:
		_setup_button_animation(button)
	
	if hover_sound:
		play_button.mouse_entered.connect(_on_button_hover)
		settings_button.mouse_entered.connect(_on_button_hover)
		quit_button.mouse_entered.connect(_on_button_hover)
	
	# Start menu music
	if menu_music:
		MusicManager.play_menu_music(menu_music)
		MusicManager.music_player.volume_db = menu_music_volume

# --- Hover / focus animation -------------------------------------------------

func _setup_button_animation(button: Control) -> void:
	# Scale around the middle instead of the top-left corner. The VBoxContainer
	# resizes its children, so the pivot has to follow the size.
	button.resized.connect(_update_pivot.bind(button))
	_update_pivot(button)
	
	button.mouse_entered.connect(_on_button_grow.bind(button))
	button.mouse_exited.connect(_on_button_shrink.bind(button))
	# Keyboard and controller selection gets the same treatment.
	button.focus_entered.connect(_on_button_grow.bind(button))
	button.focus_exited.connect(_on_button_shrink.bind(button))
	button.button_down.connect(_on_button_down.bind(button))
	button.button_up.connect(_on_button_up.bind(button))

func _update_pivot(button: Control) -> void:
	button.pivot_offset = button.size / 2.0

func _is_highlighted(button: Control) -> bool:
	return button.is_hovered() or button.has_focus()

func _on_button_grow(button: Control) -> void:
	# Draw over its neighbours while enlarged.
	button.z_index = 1
	_animate_scale(button, hover_scale)

func _on_button_shrink(button: Control) -> void:
	if _is_highlighted(button):
		return  # mouse left but keyboard focus is still on it (or vice versa)
	button.z_index = 0
	_animate_scale(button, 1.0)

func _on_button_down(button: Control) -> void:
	# Quick squish with no overshoot, so the click feels snappy.
	_animate_scale(button, pressed_scale, scale_time * 0.4, 0.0)

func _on_button_up(button: Control) -> void:
	_animate_scale(button, hover_scale if _is_highlighted(button) else 1.0)

## Scales `button` to `target`, swinging a little past it first and then
## settling back. That out-and-back is what reads as a bounce.
func _animate_scale(button: Control, target: float, time: float = -1.0, swing: float = -1.0) -> void:
	if time < 0.0:
		time = scale_time
	if swing < 0.0:
		swing = overshoot
	
	var old_tween: Tween = _scale_tweens.get(button)
	if old_tween and old_tween.is_valid():
		old_tween.kill()
	
	var tween: Tween = create_tween()
	_scale_tweens[button] = tween
	
	var direction: float = signf(target - button.scale.x)
	if swing > 0.0 and direction != 0.0:
		# Overshoot: past the target when growing, below it when shrinking.
		var peak: float = maxf(target + direction * swing, 0.01)
		tween.tween_property(button, "scale", Vector2.ONE * peak, time * 0.65) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(button, "scale", Vector2.ONE * target, time * 0.35) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		tween.tween_property(button, "scale", Vector2.ONE * target, time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

# --- Buttons -----------------------------------------------------------------

func _on_play_pressed():
	get_tree().change_scene_to_file("res://malte/scenes/menus/level_select_menu.tscn")

func _on_settings_pressed():
	get_tree().change_scene_to_file("res://malte/scenes/menus/settings_menu.tscn")

func _on_quit_pressed():
	get_tree().quit()

func _on_button_hover():
	if hover_sound and audio_player:
		audio_player.stream = hover_sound
		audio_player.volume_db = hover_volume
		audio_player.play()
