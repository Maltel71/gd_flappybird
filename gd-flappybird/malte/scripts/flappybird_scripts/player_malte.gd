extends RigidBody2D
class_name Player_Malte

signal game_started
signal died
signal scored

var started := false
var is_alive := true

var flap_force := -340.0
var maximum_rotation_up := -30.0
var maximum_rotation_down := 90.0

#(uppdaterar varje frame)
func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed("flap") && is_alive:
		if not started:
			start_game()
		flap()
		
#rotate the player Upwards
	if rotation_degrees <= maximum_rotation_up:
		rotation_degrees = maximum_rotation_up
		angular_velocity = 0.0
		
#rotate the player downwards
	if linear_velocity.y > 0.0:
		if rotation_degrees <= maximum_rotation_down:
			angular_velocity = 5.0
		else:
			angular_velocity =  0.0
		
#will be called once when the flap buttons gets pressed the first time
func start_game() -> void:
	started = true
	print ("start the game!")
	gravity_scale = 1.0
	game_started.emit()
	
#flap function
func flap() -> void:
	linear_velocity.y = flap_force
	angular_velocity = -8.0
	
func die() -> void:
	if is_alive:
		is_alive = false
		died.emit()
	
func score_point() -> void:
	if is_alive:
		scored.emit()
	
	
	
		
