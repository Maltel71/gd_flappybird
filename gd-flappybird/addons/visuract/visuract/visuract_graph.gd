@tool
class_name VisuractGraph
extends Resource

## Each node: {"id": String, "type": String, "position": Vector2}
@export var nodes: Array = []
## Each connection: {"from": String, "to": String}
@export var connections: Array = []
## UID of the scene that owns this graph. A duplicated scene gets its own copy.
@export var scene_uid := ""
