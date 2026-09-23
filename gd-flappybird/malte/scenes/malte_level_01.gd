extends Node2D

@onready var obstacle_spawner_malte: Node2D = $Obstacle_Spawner_Malte
@onready var ground_malte: StaticBody2D = $Ground_Malte
@onready var hud: CanvasLayer = $HUD

var score: int = 0
var high_score: int = 0

func _ready() -> void:
	hud.set_score(score)

func _on_player_malte_game_started() -> void:
	obstacle_spawner_malte.start()
	hud.hide_start_message()


func _on_player_malte_died() -> void:
	obstacle_spawner_malte.stop()
	ground_malte.animation_player.pause()
	get_tree().call_group("obstacles", "stop")
	
	await get_tree().create_timer(0.5).timeout
	hud.show_game_over_screen(score, 123)


func _on_player_malte_scored() -> void:
	score += 1
	hud.set_score(score)
