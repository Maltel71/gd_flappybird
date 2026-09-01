extends Node2D

@onready var obstacle_spawner_malte: Node2D = $Obstacle_Spawner_Malte
@onready var ground_malte: StaticBody2D = $Ground_Malte

var score := 0

func _on_player_malte_game_started() -> void:
	obstacle_spawner_malte.start()


func _on_player_malte_died() -> void:
	obstacle_spawner_malte.stop()
	ground_malte.animation_player.pause()
	get_tree().call_group("obstacles", "stop")


func _on_player_malte_scored() -> void:
	print("player scored point")
