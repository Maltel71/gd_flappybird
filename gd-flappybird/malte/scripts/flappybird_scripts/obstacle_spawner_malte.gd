extends Node2D

@onready var spawn_timer: Timer = $SpawnTimer
var obstacle_scene: PackedScene = preload("res://malte/scenes/obstacle_malte.tscn")

func _on_spawn_timer_timeout() -> void:
	var obstacle = obstacle_scene.instantiate()
	add_child(obstacle)
	obstacle.position.y = randf_range(-297.0, 297.0)

func start() -> void:
	spawn_timer.start()
	
func stop() -> void:
	spawn_timer.stop()
