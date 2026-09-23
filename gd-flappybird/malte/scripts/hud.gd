extends CanvasLayer

@onready var score_label: Label = $ScoreLabel
@onready var start_message: TextureRect = $StartMessage

func set_score(new_score: int) -> void:
	score_label.text = str(new_score)

func hide_start_message() -> void:
	var tween: Tween = get_tree().create_tween()
	tween.tween_property(start_message, "modulate:a",
	0.0, 0.1)
