extends Node

## Autoload singleton. Register in Project Settings -> Autoload as "MusicManager".
##
## Requires three audio buses, spelled exactly like this (bus names ARE
## case-sensitive in Godot):
##   Master
##   music   -> output to Master
##   sfx     -> output to Master

const MUSIC_BUS := "music"
const SFX_BUS := "sfx"
const MASTER_BUS := "Master"

## Startup volumes, as linear values from 0.0 to 1.0.
## A settings menu loading saved values later will override these.
const DEFAULT_MASTER_LINEAR := 0.5
const DEFAULT_MUSIC_LINEAR := 0.5
const DEFAULT_SFX_LINEAR := 0.5

var music_player: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	music_player = AudioStreamPlayer.new()
	music_player.name = "MusicPlayer"
	add_child(music_player)

	if _bus_exists(MUSIC_BUS):
		music_player.bus = MUSIC_BUS
	else:
		push_warning("Audio bus '%s' is missing. Music will play on Master." % MUSIC_BUS)

	_set_bus_linear(MASTER_BUS, DEFAULT_MASTER_LINEAR)
	_set_bus_linear(MUSIC_BUS, DEFAULT_MUSIC_LINEAR)
	_set_bus_linear(SFX_BUS, DEFAULT_SFX_LINEAR)


func _bus_exists(bus_name: String) -> bool:
	return AudioServer.get_bus_index(bus_name) != -1


## Sets a bus volume from a 0.0-1.0 linear value. Does nothing if the bus
## is missing, instead of spamming errors with an index of -1.
func _set_bus_linear(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		push_warning("Audio bus '%s' not found. Skipping volume setup." % bus_name)
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0, 1.0)))


## Public helper so a settings menu can set volumes without repeating
## the index lookup and the missing-bus check.
func set_bus_volume(bus_name: String, linear: float) -> void:
	_set_bus_linear(bus_name, linear)


func get_bus_volume(bus_name: String) -> float:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return 0.0
	return db_to_linear(AudioServer.get_bus_volume_db(idx))


## Starts the track only if it is not already the one playing, so moving
## between menus does not restart the music.
func play_menu_music(music: AudioStream) -> void:
	if music == null:
		return
	if music_player.stream != music:
		music_player.stream = music
		music_player.play()
	elif not music_player.playing:
		music_player.play()


func stop_music() -> void:
	music_player.stop()


func is_playing() -> bool:
	return music_player.playing
