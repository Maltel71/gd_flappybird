extends StaticBody2D

@onready var animation_player: AnimationPlayer = $AnimationPlayer

func _on_death_zone_body_entered(body: Node2D) -> void:
	if body is Player_Malte:
		body.die()
