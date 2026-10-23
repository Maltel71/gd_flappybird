@tool
extends RefCounted

const BUTTONS := ["None", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N",
	"O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
	"0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
	"Space", "Enter", "Escape", "Shift", "Ctrl", "Tab",
	"Left", "Right", "Up", "Down",
	"Mouse Left", "Mouse Right", "Mouse Middle"]

## Params tagged with these only appear when such an event feeds the node.
const TOUCH_EVENTS := ["On Body or Area Entered", "On Body or Area Exited"]

const TOUCH_KINDS := ["Anything", "Bodies only", "Areas only"]

const CATEGORY_COLORS := {
	"Events": Color("e0754b"),
	"Actions": Color("4b8fe0"),
	"Flow": Color("b45be0"),
}

const LAUNCH_DIRECTIONS := ["Where I'm facing", "Left", "Right", "Up", "Down"]

const MOTOR_DRIVES := ["Body", "Wheel joint"]

const MOTOR_DIRECTIONS := ["Where I'm pointing", "Where I'm facing", "Left", "Right", "Up", "Down"]

const REMEMBER_SCOPES := ["Whole game", "This node only"]

const REMEMBER_MODES := ["Set to", "Add", "Subtract", "Keep highest"]

const HEALTH_MODES := ["Set max", "Damage", "Heal"]

const GLOBAL_VALUES := ["On", "Off"]

const GLOBAL_TESTS := ["is On", "is Off", "equals", "is not", "is at least", "is at most", "is more than", "is less than"]

const TEXT_SOURCES := ["Text", "Value"]

const VISIBILITY_ACTIONS := ["Show", "Hide", "Toggle"]

const SPAWN_PLACES := ["On me", "At a node"]

const GAME_TYPES := ["Side view", "Top down"]

const ANIMATION_ACTIONS := ["Play", "Stop", "Pause", "Resume"]

const GRAVITY_ACTIONS := ["Turn on", "Turn off", "Toggle"]

const POINT_MODES := ["Face direction", "Lean"]

const BUTTON_MODES := ["When pressed", "While held", "When released"]

## A short, friendly whitelist instead of every property Godot reports.
const PROPERTIES := ["Size", "Transparency", "Rotation", "Layer"]

## Each entry: name (label), desc (simple explanation), code (GDScript it maps to),
## requires_class (optional; only offered when the attached node is one of these),
## requires_child (optional; offered but greyed out until such a child exists),
## params (optional, name -> default). A plain value picks the widget by type:
## float -> spinbox, bool -> checkbox, String -> text field. A dictionary picks
## an explicit widget: {"type": "slider"|"node"|"file"|"scene_list"}.
const NODES := {
	"Events": [
		{"name": "On Ready", "desc": "Runs once when the scene starts.", "code": "func _ready():"},
		{"name": "On Every Frame", "desc": "Runs again every frame.", "code": "func _process(delta):"},
		{"name": "On Input Action", "desc": "Runs on an action from your project's Input Map.", "code": "if Input.is_action_pressed(\"action\"):", "params": {"action": {"type": "choice", "options_from": "input_actions", "default": ""}, "mode": {"type": "choice", "options": BUTTON_MODES, "default": "When pressed"}}},
		{"name": "On Button Pressed", "desc": "Runs when you press a key or a mouse button.", "code": "if Input.is_key_pressed(KEY_G):", "params": {"button": {"type": "choice", "options": BUTTONS, "default": "G"}, "mode": {"type": "choice", "options": BUTTON_MODES, "default": "When pressed"}}},
		{"name": "On Body or Area Entered", "requires_child": "CollisionShape2D,CollisionPolygon2D", "requires_class": "Area2D,RigidBody2D", "desc": "Runs when something touches this. Kind picks whether objects, zones, or both count.", "code": "func _on_body_entered(body):", "params": {"only_named": "", "kind": {"type": "choice", "options": TOUCH_KINDS, "default": "Anything"}}},
		{"name": "On Body or Area Exited", "requires_child": "CollisionShape2D,CollisionPolygon2D", "requires_class": "Area2D,RigidBody2D", "desc": "Runs when something stops touching this.", "code": "func _on_body_exited(body):", "params": {"only_named": "", "kind": {"type": "choice", "options": TOUCH_KINDS, "default": "Anything"}}},
		{"name": "On Timer Timeout", "desc": "Waits a number of seconds, then runs. Keep Repeat on to run again and again.", "code": "func _on_timeout():", "params": {"seconds": {"type": "number", "default": 1.0, "min": 0.1, "step": 0.1}, "repeat": true}},
		{"name": "On Signal", "desc": "Runs when any node sends this signal name.", "code": "some_signal.connect(_on_signal)", "params": {"listen_for": {"type": "choice", "options_from": "signal_names", "default": ""}}},
		{"name": "On Clicked", "requires_class": "BaseButton,CollisionObject2D", "desc": "Runs when this is clicked. Works on a Button, or on an Area2D with a collision shape as a clickable hotspot in the world.", "code": "pressed.connect(_on_pressed)"},
		{"name": "Juicy Button", "requires_class": "BaseButton", "desc": "Makes a button grow, tilt and wiggle when you hover or click it, and can recolor it. Runs the blocks after it when pressed, held or released. Selected is the outline for keyboard and gamepad.", "code": "button_down.connect(_on_down)", "params": {"run_blocks": {"type": "choice", "options": BUTTON_MODES, "default": "When released"}, "h_hover": {"type": "header", "text": "ON HOVER"}, "hover_grow": {"type": "slider", "default": 8.0, "min": 0.0, "max": 50.0}, "hover_tilt": {"type": "slider", "default": 3.0, "min": 0.0, "max": 20.0}, "hover_wiggle": true, "h_click": {"type": "header", "text": "ON CLICK"}, "click_grow": {"type": "slider", "default": -10.0, "min": -50.0, "max": 50.0}, "click_tilt": {"type": "slider", "default": 0.0, "min": 0.0, "max": 20.0}, "click_wiggle": true, "h_colors": {"type": "header", "text": "COLORS"}, "change_colors": false, "normal_color": {"type": "color", "default": Color("4b8fe0"), "requires_param": {"change_colors": true}}, "hover_color": {"type": "color", "default": Color("6aa8f0"), "requires_param": {"change_colors": true}}, "pressed_color": {"type": "color", "default": Color("3570b8"), "requires_param": {"change_colors": true}}, "selected_color": {"type": "color", "default": Color.WHITE, "requires_param": {"change_colors": true}}}},
		{"name": "On Died", "desc": "Runs once when this node's health reaches 0.", "code": "died.connect(_on_died)"},
	],
	"Actions": [
		{"name": "Move", "requires_class": "Node2D", "desc": "Move with the buttons you pick. Lower Acceleration to start slowly, lower Deceleration to slide to a stop.", "code": "velocity.x = direction * speed", "params": {"speed": 200.0, "acceleration": {"type": "slider", "default": 100.0, "min": 0.0, "max": 100.0}, "deceleration": {"type": "slider", "default": 100.0, "min": 0.0, "max": 100.0}, "left": {"type": "choice", "options": BUTTONS, "default": "Left"}, "right": {"type": "choice", "options": BUTTONS, "default": "Right"}, "up": {"type": "choice", "options": BUTTONS, "default": "None"}, "down": {"type": "choice", "options": BUTTONS, "default": "None"}}},
		{"name": "Jump", "requires_class": "CharacterBody2D,RigidBody2D", "desc": "Jump when you press the button. Coyote Time still lets you jump just after walking off an edge.", "code": "velocity.y = -height", "params": {"height": 400.0, "coyote_time": false, "coyote_seconds": {"type": "slider", "default": 0.12, "min": 0.05, "max": 0.3, "step": 0.01, "decimals": 2, "requires_param": {"coyote_time": true}}, "button": {"type": "choice", "options": BUTTONS, "default": "Space"}}},
		{"name": "Launch", "requires_class": "CharacterBody2D,RigidBody2D,Area2D", "desc": "Sets off in one direction at a speed, turning to face that way. Good for bullets, and Flappy Bird pipes (on an Area2D).", "code": "velocity = direction * speed", "params": {"direction": {"type": "choice", "options": LAUNCH_DIRECTIONS, "default": "Where I'm facing"}, "speed": {"type": "number", "default": 400.0, "step": 10.0}, "flip_to_face": {"type": "bool", "default": true}}},
		{"name": "Fly", "requires_class": "CharacterBody2D,RigidBody2D", "desc": "Push upward the whole time you hold the button, like a jetpack.", "code": "velocity.y = -power", "params": {"power": 600.0, "acceleration": {"type": "slider", "default": 100.0, "min": 0.0, "max": 100.0}, "limit_top_speed": false, "max_speed": {"type": "number", "default": 800.0, "min": 10.0, "step": 10.0, "requires_param": {"limit_top_speed": true}}, "button": {"type": "choice", "options": BUTTONS, "default": "Space"}}},
		{"name": "Motor", "requires_class": "Node2D", "desc": "Keeps something going, like an engine. Body pushes and spins this RigidBody2D - Where I'm Pointing follows its rotation, like a rocket. Wheel Joint drives a wheel through its PinJoint2D (Godot 4.2+), and Speed is its top speed. Put it after On Every Frame. Leave both buttons on None to run all the time. Raise a body's Linear Damp to limit its top speed. Tilt buttons lean Tilt Body (empty means this RigidBody2D, pick the frame otherwise) forward or back, on the ground or in the air - for wheelies and balancing like a trials bike. Raise its Angular Damp for steadier balance.", "code": "linear_velocity += direction * push * delta", "params": {"drive": {"type": "choice", "options": MOTOR_DRIVES, "default": "Body"}, "direction": {"type": "choice", "options": MOTOR_DIRECTIONS, "default": "Where I'm pointing", "requires_param": {"drive": "Body"}}, "push": {"type": "number", "default": 600.0, "min": 0.0, "max": 10000.0, "step": 10.0, "requires_param": {"drive": "Body"}}, "spin": {"type": "number", "default": 0.0, "min": -3600.0, "max": 3600.0, "step": 10.0, "requires_param": {"drive": "Body"}}, "joint": {"type": "node", "class": "PinJoint2D", "requires_param": {"drive": "Wheel joint"}}, "speed": {"type": "number", "default": 720.0, "min": 0.0, "max": 7200.0, "step": 30.0, "requires_param": {"drive": "Wheel joint"}}, "forward": {"type": "choice", "options": BUTTONS, "default": "None"}, "backward": {"type": "choice", "options": BUTTONS, "default": "None"}, "tilt_forward": {"type": "choice", "options": BUTTONS, "default": "None"}, "tilt_back": {"type": "choice", "options": BUTTONS, "default": "None"}, "tilt": {"type": "number", "default": 360.0, "min": 0.0, "max": 3600.0, "step": 10.0}, "tilt_body": {"type": "node", "class": "RigidBody2D"}}},
		{"name": "Gravity", "requires_class": "CharacterBody2D,RigidBody2D", "desc": "Turn falling on or off, or change how strong it is. 100 is normal, 50 is floaty like the moon, 200 is heavy.", "code": "gravity_scale = strength", "params": {"action": {"type": "choice", "options": GRAVITY_ACTIONS, "default": "Turn off"}, "strength": {"type": "slider", "default": 100.0, "min": 0.0, "max": 300.0, "requires_param": {"action": ["Turn on", "Toggle"]}}}},
		{"name": "Animation", "desc": "Play, stop or pause one of your animations. Wait To Finish holds up the blocks after it until the animation ends.", "code": "$AnimationPlayer.play(\"name\")", "params": {"animation": {"type": "choice", "options_from": "animations", "default": ""}, "action": {"type": "choice", "options": ANIMATION_ACTIONS, "default": "Play"}, "wait_to_finish": {"type": "bool", "default": false, "requires_param": {"action": "Play"}}}},
		{"name": "Character Animation", "requires_class": "CharacterBody2D,RigidBody2D", "desc": "Picks the right animation every frame from what your character is doing.", "code": "if is_on_floor(): play(\"idle\")", "params": {"h_setup": {"type": "header", "text": "SET UP"}, "game_type": {"type": "choice", "options": GAME_TYPES, "default": "Side view"}, "flip_to_face": {"type": "bool", "default": true, "requires_param": {"game_type": "Side view"}}, "h_moving": {"type": "header", "text": "MOVING"}, "idle": {"type": "choice", "options_from": "animations", "default": ""}, "walk": {"type": "choice", "options_from": "animations", "default": "", "requires_param": {"game_type": "Side view"}}, "walk_up": {"type": "choice", "options_from": "animations", "default": "", "requires_param": {"game_type": "Top down"}}, "walk_down": {"type": "choice", "options_from": "animations", "default": "", "requires_param": {"game_type": "Top down"}}, "walk_left": {"type": "choice", "options_from": "animations", "default": "", "requires_param": {"game_type": "Top down"}}, "walk_right": {"type": "choice", "options_from": "animations", "default": "", "requires_param": {"game_type": "Top down"}}, "h_air": {"type": "header", "text": "IN THE AIR", "requires_param": {"game_type": "Side view"}}, "jump": {"type": "choice", "options_from": "animations", "default": "", "requires_param": {"game_type": "Side view"}}, "falling": {"type": "choice", "options_from": "animations", "default": "", "requires_param": {"game_type": "Side view"}}, "landing": {"type": "choice", "options_from": "animations", "default": "", "requires_param": {"game_type": "Side view"}}, "h_crouch": {"type": "header", "text": "CROUCHING", "requires_param": {"game_type": "Side view"}}, "crouch": {"type": "choice", "options_from": "animations", "default": "", "requires_param": {"game_type": "Side view"}}, "crouch_button": {"type": "choice", "options": BUTTONS, "default": "None", "requires_param": {"game_type": "Side view"}}, "h_oneshot": {"type": "header", "text": "ONE-SHOT ACTIONS"}, "attack": {"type": "choice", "options_from": "animations", "default": ""}, "attack_when": {"type": "choice", "options_from": "signal_names", "default": ""}, "interact": {"type": "choice", "options_from": "animations", "default": ""}, "interact_when": {"type": "choice", "options_from": "signal_names", "default": ""}, "hurt": {"type": "choice", "options_from": "animations", "default": ""}, "hurt_when": {"type": "choice", "options_from": "signal_names", "default": ""}, "h_dying": {"type": "header", "text": "DYING"}, "die": {"type": "choice", "options_from": "animations", "default": ""}, "die_when": {"type": "choice", "options_from": "signal_names", "default": ""}, "dead_idle": {"type": "choice", "options_from": "animations", "default": ""}}},
		{"name": "Play Sound", "desc": "Play a sound file. Drag one in from the FileSystem, or click to pick.", "code": "$AudioStreamPlayer.play()", "params": {"sound": {"type": "file", "filter": "wav,ogg,mp3"}, "volume": {"type": "slider", "default": 100.0, "min": 0.0, "max": 100.0}, "wait_to_finish": false}},
		{"name": "Spawn Scene", "desc": "Create a copy of a scene, on this node or at one you pick. Add more scenes to pick one at random - a higher number makes it more likely, 0 never. Each scene has its own place and offset, and Random X and Y move it by up to that much.", "code": "add_child(scene.instantiate())", "params": {"scene": {"type": "scene_list"}}},
		{"name": "Change Scene", "desc": "Switch to another scene.", "code": "get_tree().change_scene_to_file(path)", "params": {"scene": {"type": "file", "filter": "tscn"}}},
		{"name": "Quit Game", "desc": "Closes the game.", "code": "get_tree().quit()"},
		{"name": "Visibility", "requires_class": "CanvasItem", "desc": "Shows, hides or toggles a node.", "code": "visible = true", "params": {"target": {"type": "node"}, "action": {"type": "choice", "options": VISIBILITY_ACTIONS, "default": "Hide"}}},
		{"name": "Point Where Moving", "requires_class": "CharacterBody2D,RigidBody2D", "desc": "Turns the art with how you move. Lean: nose up while rising, down while falling (Flappy Bird). Face Direction: always points the way you're going (arrows, falling bullets). Draw the art facing right, and put this after On Every Frame. Turn Speed 100 is instant.", "code": "rotation = velocity.angle()", "params": {"mode": {"type": "choice", "options": POINT_MODES, "default": "Face direction"}, "up_angle": {"type": "number", "default": -30.0, "min": -90.0, "max": 0.0, "step": 5.0, "requires_param": {"mode": "Lean"}}, "down_angle": {"type": "number", "default": 90.0, "min": 0.0, "max": 180.0, "step": 5.0, "requires_param": {"mode": "Lean"}}, "turn_speed": {"type": "slider", "default": 50.0, "min": 1.0, "max": 100.0}}},
		{"name": "Rotate", "requires_class": "Node2D", "desc": "Spin a node around. Negative speed spins the other way.", "code": "rotation += speed * delta", "params": {"target": {"type": "node"}, "speed": {"type": "number", "default": 90.0, "min": -3600.0, "max": 3600.0, "step": 10.0}}},
		{"name": "Print", "desc": "Write a message to the output.", "code": "print(text)", "params": {"text": "Hello!", "show_what_touched_me": {"type": "bool", "default": false, "requires_upstream": TOUCH_EVENTS}, "show_my_name": false}},
		{"name": "Dialogue", "desc": "Shows text on a Label. Each time it runs it plays the next section, then cycles the default responses.", "code": "label.text = line", "params": {"label": {"type": "node", "class": "Label"}, "dialogue": {"type": "dialogue"}}},
		{"name": "Show Text", "desc": "Writes on a Label: your own text, or a value you remembered.", "code": "label.text = text", "params": {"label": {"type": "node", "class": "Label"}, "show": {"type": "choice", "options": TEXT_SOURCES, "default": "Text"}, "text": {"type": "text", "default": "Hello!", "requires_param": {"show": "Text"}}, "value": {"type": "choice", "options_from": "variable_names", "default": "", "requires_param": {"show": "Value"}}}},
		{"name": "Send Signal", "desc": "Shout a name. Every On Signal node listening for that name will run.", "code": "my_signal.emit()", "params": {"signal_name": "door open"}},
		{"name": "Destroy", "desc": "Remove a node from the game. Defaults to this one.", "code": "queue_free()", "params": {"target": {"type": "node", "allow_toucher": true}}},
		{"name": "Remember", "desc": "Remembers a value you can check later, even after changing scene. Keep Highest keeps the bigger of it and another one.", "code": "vars[name] = value", "params": {"variable_name": "score", "scope": {"type": "choice", "options": REMEMBER_SCOPES, "default": "Whole game"}, "mode": {"type": "choice", "options": REMEMBER_MODES, "default": "Set to"}, "value": {"type": "text", "default": "0", "requires_param": {"mode": ["Set to", "Add", "Subtract"]}}, "from": {"type": "choice", "options_from": "variable_names", "default": "", "requires_param": {"mode": "Keep highest"}}}},
		{"name": "Health", "desc": "Set Max gives full health (use it in On Ready). Damage hurts, then stays invincible a moment so one touch isn't many hits. Pick What Touched Me to hurt someone else. Add a Health Bar from the Scene Library to see it. Tick Print to see what happened in the Output.", "code": "health -= amount", "params": {"target": {"type": "node", "allow_toucher": true}, "mode": {"type": "choice", "options": HEALTH_MODES, "default": "Damage"}, "amount": {"type": "number", "default": 1.0, "min": 0.0, "step": 1.0}, "invincible_seconds": {"type": "number", "default": 0.5, "min": 0.0, "step": 0.1, "requires_param": {"mode": "Damage"}}, "save_as": {"type": "text", "default": "", "requires_param": {"mode": "Set max"}}, "print": false}},
		{"name": "Set Property", "requires_class": "Node2D", "desc": "Change one thing about a node: how big it is, how see-through it is, which way it points, or whether it draws in front.", "code": "scale = size", "params": {"target": {"type": "node"}, "property": {"type": "choice", "options": PROPERTIES, "default": "Size"}, "size": {"type": "slider", "default": 100.0, "min": 10.0, "max": 400.0, "requires_param": {"property": "Size"}}, "transparency": {"type": "slider", "default": 0.0, "min": 0.0, "max": 100.0, "requires_param": {"property": "Transparency"}}, "rotation": {"type": "number", "default": 0.0, "min": -360.0, "max": 360.0, "step": 5.0, "requires_param": {"property": "Rotation"}}, "layer": {"type": "number", "default": 0.0, "min": -100.0, "max": 100.0, "step": 1.0, "requires_param": {"property": "Layer"}}}},
		{"name": "Set Color", "requires_class": "CanvasItem", "desc": "Tint a node with a color. Random picks a new bright color each time it runs, or one from your own color ramp.", "code": "modulate = color", "params": {"target": {"type": "node"}, "random": false, "use_color_ramp": {"type": "bool", "default": false, "requires_param": {"random": true}}, "ramp": {"type": "ramp", "default": {}, "requires_param": {"random": true, "use_color_ramp": true}}, "color": {"type": "color", "default": Color.WHITE, "requires_param": {"random": false}}}},
		{"name": "Wait", "desc": "Pause for some seconds.", "code": "await get_tree().create_timer(seconds).timeout", "params": {"seconds": {"type": "number", "default": 1.0, "min": 0.0, "step": 0.1}}},
	],
	"Flow": [
		{"name": "Only If", "desc": "Blocks the blocks after it unless what you remembered matches.", "code": "if vars[name] ... :", "params": {"variable_name": {"type": "choice", "options_from": "variable_names", "default": ""}, "scope": {"type": "choice", "options": REMEMBER_SCOPES, "default": "Whole game"}, "test": {"type": "choice", "options": GLOBAL_TESTS, "default": "is On"}, "value": {"type": "text", "default": "", "requires_param": {"test": ["equals", "is not", "is at least", "is at most", "is more than", "is less than"]}}}},
		{"name": "Wait Until", "desc": "Waits here until what you remembered matches, then carries on.", "code": "await until true", "params": {"variable_name": {"type": "choice", "options_from": "variable_names", "default": ""}, "scope": {"type": "choice", "options": REMEMBER_SCOPES, "default": "Whole game"}, "test": {"type": "choice", "options": GLOBAL_TESTS, "default": "is On"}, "value": {"type": "text", "default": "", "requires_param": {"test": ["equals", "is not", "is at least", "is at most", "is more than", "is less than"]}}}},
		{"name": "Repeat", "desc": "Runs the blocks after it several times.", "code": "for i in count:", "params": {"count": {"type": "number", "default": 3.0, "min": 1.0, "step": 1.0, "decimals": 0}}},
		{"name": "Random", "desc": "A dice roll. Only carries on part of the time - set the chance.", "code": "if randf() < chance:", "params": {"chance": {"type": "slider", "default": 50.0, "min": 0.0, "max": 100.0}}},
	],
}


static func category_of(node_name: String) -> String:
	for category in NODES:
		for entry in NODES[category]:
			if entry.name == node_name:
				return category
	return ""


static func color_of(node_name: String) -> Color:
	return CATEGORY_COLORS.get(category_of(node_name), Color.GRAY)


static func find(node_name: String) -> Dictionary:
	for category in NODES:
		for entry in NODES[category]:
			if entry.name == node_name:
				return entry
	return {}
