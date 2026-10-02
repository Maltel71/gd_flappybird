extends CharacterBody2D

var speed := -215.0
#move the obstacle
func _physics_process(delta: float) -> void:
	velocity.x = speed
	move_and_slide()
	
	if global_position.x < -200.0:
		print ("deleting obstacle...")
		queue_free()


func _on_area_2d_body_entered(body: Node2D) -> void:
	if body is Player_Malte:
		body.score_point()
		
		
func stop() -> void:
	speed = 0.0


func _on_wall_top_body_entered(body: Node2D) -> void:
	if body is Player_Malte:
			body.die()


func _on_wall_bottom_body_entered(body: Node2D) -> void:
	if body is Player_Malte:
			body.die()
