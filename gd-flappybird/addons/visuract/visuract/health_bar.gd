extends ProgressBar

## Follows the health of the nearest Visuract parent with a Health node.
@export var hide_when_full := false


func _ready() -> void:
	var source := get_parent()
	while source != null and not source.has_signal("health_changed"):
		source = source.get_parent()
	if source == null:
		push_warning("Health bar '%s': put it under a node with a Visuract script." % name)
		return
	source.connect("health_changed", _on_health_changed)


func _on_health_changed(current: float, maximum: float) -> void:
	max_value = maximum
	value = current
	if hide_when_full:
		visible = current < maximum
