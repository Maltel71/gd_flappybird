@tool
class_name VisuractGraph
extends Resource

## Each node: {"id": String, "type": String, "position": Vector2}
@export var nodes: Array = []
## Each connection: {"from": String, "to": String}
@export var connections: Array = []
