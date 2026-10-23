extends Node

## Attached by Visuract. Runs the connected graph at game runtime.
@export var graph: VisuractGraph
@export var speed := 200.0
@export var jump_force := 400.0
@export var gravity := 980.0

## Emitted by the Health node. A health bar listens for this.
signal health_changed(current: float, maximum: float)
signal died

## Shared by every Visuract node and kept across scene changes, because a
## static var lives as long as the script itself.
static var globals := {}
## Label -> [owner, variable name]. Show Text (Value) keeps these in sync.
static var _live_labels := {}
## Variables scoped to this one node ("This node only").
var locals := {}

## Every Visuract node joins this group, so signals reach all of them.
const LISTENER_GROUP := "visuract_listeners"

const MOUSE_BUTTONS := {
	"Mouse Left": MOUSE_BUTTON_LEFT,
	"Mouse Right": MOUSE_BUTTON_RIGHT,
	"Mouse Middle": MOUSE_BUTTON_MIDDLE,
}

const TOUCH_SIGNALS := {
	"On Body or Area Entered": ["body_entered", "area_entered"],
	"On Body or Area Exited": ["body_exited", "area_exited"],
}

var _button_states := {}
## The body from the most recent collision event, for actions downstream.
var _last_body: Node
## When the node was last touching the ground, for coyote time.
var _grounded_at := -999.0
## Per Character Animation node: what it is playing and its one-shot timers.
var _character_states := {}
## One AudioStreamPlayer per Play Sound node, made on first use.
var _sound_players := {}
## Per Dialogue node: next section, next default response, and cooldown.
var _dialogue_states := {}
## -1 left, 1 right. Updated by Move, used by Launch, Spawn Scene and flipping.
var facing := 1.0
## Set by the Gravity node. Strength is a multiplier: 1.0 is normal.
var _gravity_on := true
var _gravity_strength := 1.0
## The RigidBody2D's own gravity_scale from the scene, so 100 means "as placed".
var _base_gravity_scale := 1.0
## Set by the Health node.
var health := 0.0
var max_health := 0.0
var _invincible_until := 0.0
## From Health (Set max) Save As. Health is kept in "Whole game" memory under
## this name, so it survives a scene change.
var _health_key := ""
## Set by Launch on a node without physics (an Area2D), moved every frame.
var _drift := Vector2.ZERO
## Juicy Button: size as placed, hover state, held blocks and running tweens.
var _juice_rest := Vector2.ONE
var _hovered := false
var _held_buttons := {}
var _juice_tween: Tween
var _tilt_tween: Tween


func _ready() -> void:
	add_to_group(LISTENER_GROUP)
	if is_class("RigidBody2D"):
		set("contact_monitor", true)
		set("max_contacts_reported", 4)
		set("can_sleep", false)
		_base_gravity_scale = get("gravity_scale")

	if graph == null:
		push_warning("Visuract on '%s': no graph assigned." % name)
	elif graph.nodes.is_empty():
		push_warning("Visuract on '%s': graph is empty - click Save Graph in the Visuract tab." % name)
	else:
		print("Visuract on '%s': %d nodes, %d connections." % [name, graph.nodes.size(), graph.connections.size()])

	_connect_touch_signals()
	_start_timers()
	_connect_clicks()
	_connect_juicy_buttons()
	_hide_dialogue_labels()
	_run_event("On Ready", 0.0)


## Physics frames, not render frames - velocity must only be written here.
func _physics_process(delta: float) -> void:
	if _is_grounded():
		_grounded_at = Time.get_ticks_msec() / 1000.0
	if _drift != Vector2.ZERO:
		set("position", get("position") + _drift * delta)
	_run_event("On Every Frame", delta)
	_run_input_actions(delta)
	_run_button_events(delta)
	for id in _held_buttons:
		_run_chain(id, delta)


# --- events -------------------------------------------------------------

## Wires touch events to the attached node's own signals. Only works on nodes
## that emit them: Area2D, or a RigidBody2D with contact reporting on.
func _connect_touch_signals() -> void:
	if graph == null:
		return
	for n in graph.nodes:
		if not TOUCH_SIGNALS.has(n.type):
			continue
		var params: Dictionary = n.get("params", {})
		var kind := String(params.get("kind", "Anything"))
		var names: Array = TOUCH_SIGNALS[n.type]

		var wanted := []
		if kind != "Areas only":
			wanted.append(names[0])
		if kind != "Bodies only":
			wanted.append(names[1])

		var id: String = n.id
		var only_named := String(params.get("only_named", ""))
		var hooked := false
		for signal_name in wanted:
			if has_signal(signal_name):
				## A lambda, not bind(): Godot sees the same method with different
				## binds as one connection, so a second touch event was dropped.
				connect(signal_name, func(other: Node): _on_touch_signal(other, id, only_named))
				hooked = true
		if not hooked:
			push_warning("Visuract on '%s': this node emits no touch signals - use an Area2D or a RigidBody2D." % name)


func _on_touch_signal(other: Node, id: String, only_named: String) -> void:
	if only_named != "" and other.name != only_named and not other.is_in_group(only_named):
		return
	_last_body = other
	_run_chain(id, 0.0)


## Each On Timer Timeout node gets its own Timer child, so no scene setup
## is needed to use one.
func _start_timers() -> void:
	if graph == null:
		return
	for n in graph.nodes:
		if n.type != "On Timer Timeout":
			continue
		var params: Dictionary = n.get("params", {})
		var timer := Timer.new()
		timer.wait_time = maxf(0.1, params.get("seconds", 1.0))
		timer.one_shot = not params.get("repeat", true)
		add_child(timer)
		timer.timeout.connect(_run_chain.bind(n.id, 0.0))
		timer.start()


## On Clicked listens to a button's pressed signal, or a left click on an
## Area2D/physics body's collision shape.
func _connect_clicks() -> void:
	if graph == null:
		return
	for n in graph.nodes:
		if n.type != "On Clicked":
			continue
		var id: String = n.id
		if has_signal("pressed"):
			connect("pressed", func(): _run_chain(id, 0.0))
		elif has_signal("input_event"):
			set("input_pickable", true)
			connect("input_event", func(_viewport, event, _shape):
				if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
					_run_chain(id, 0.0))


## Hover and click juice, state colors, and the blocks after it.
func _connect_juicy_buttons() -> void:
	if graph == null or not is_class("BaseButton"):
		return
	for n in graph.nodes:
		if n.type != "Juicy Button":
			continue
		var id: String = n.id
		var params: Dictionary = n.get("params", {})
		_juice_rest = get("scale")
		_color_button(params)
		connect("mouse_entered", _juice_hover.bind(params, true))
		connect("mouse_exited", _juice_hover.bind(params, false))
		connect("button_down", _juice_click.bind(params))
		match String(params.get("run_blocks", "When released")):
			"When pressed":
				connect("button_down", func(): _run_chain(id, 0.0))
			"While held":
				connect("button_down", func(): _held_buttons[id] = true)
				connect("button_up", func(): _held_buttons.erase(id))
			_:
				connect("pressed", func(): _run_chain(id, 0.0))


func _juice_hover(params: Dictionary, hovering: bool) -> void:
	_hovered = hovering
	_juice_tween = _restart(_juice_tween).set_trans(Tween.TRANS_BACK)
	_juice_tween.tween_property(self, "scale", _hover_scale(params), 0.12)
	_tilt(params.get("hover_tilt", 0.0) if hovering else 0.0, hovering and params.get("hover_wiggle", true), true)


## Punches to the click size, then springs back - overshooting with Wiggle.
func _juice_click(params: Dictionary) -> void:
	var wiggle: bool = params.get("click_wiggle", true)
	_juice_tween = _restart(_juice_tween)
	_juice_tween.tween_property(self, "scale", _juice_rest * (1.0 + params.get("click_grow", 0.0) / 100.0), 0.06).set_trans(Tween.TRANS_SINE)
	_juice_tween.tween_property(self, "scale", _hover_scale(params), 0.35 if wiggle else 0.12) \
		.set_trans(Tween.TRANS_ELASTIC if wiggle else Tween.TRANS_BACK)
	_tilt(params.get("click_tilt", 0.0), wiggle, false)


func _hover_scale(params: Dictionary) -> Vector2:
	return _juice_rest * (1.0 + params.get("hover_grow", 0.0) / 100.0) if _hovered else _juice_rest


## Wiggle swings and settles straight. Otherwise it leans - and holds the lean
## when hold is on, or leans and comes back when it's off.
func _tilt(degrees: float, wiggle: bool, hold: bool) -> void:
	var angle := deg_to_rad(degrees)
	_tilt_tween = _restart(_tilt_tween).set_trans(Tween.TRANS_SINE)
	if wiggle:
		_tilt_tween.tween_property(self, "rotation", angle, 0.08)
		_tilt_tween.tween_property(self, "rotation", -angle, 0.10)
		_tilt_tween.tween_property(self, "rotation", angle * 0.5, 0.08)
	elif not hold:
		_tilt_tween.tween_property(self, "rotation", angle, 0.06)
	_tilt_tween.tween_property(self, "rotation", angle if hold and not wiggle else 0.0, 0.08)


## Scale and rotation pivot from the middle, whatever size the button is now.
func _restart(tween: Tween) -> Tween:
	set("pivot_offset", get("size") / 2.0)
	if tween:
		tween.kill()
	return create_tween().set_ease(Tween.EASE_OUT)


## Recolors the button's own boxes rather than modulate, so text keeps its color.
func _color_button(params: Dictionary) -> void:
	if not params.get("change_colors", false):
		return
	var states := {"normal": "normal_color", "hover": "hover_color", "pressed": "pressed_color", "hover_pressed": "pressed_color", "focus": "selected_color"}
	for state in states:
		var base = call("get_theme_stylebox", state)
		var box: StyleBoxFlat = base.duplicate() if base is StyleBoxFlat else StyleBoxFlat.new()
		var color: Color = params.get(states[state], Color.WHITE)
		if state == "focus":
			box.border_color = color
		else:
			box.bg_color = color
		call("add_theme_stylebox_override", state, box)


func _receive_signal(signal_name: String) -> void:
	if graph == null or signal_name == "":
		return
	var now := Time.get_ticks_msec() / 1000.0
	for n in graph.nodes:
		if n.type == "On Signal" and String(n.get("params", {}).get("listen_for", "")) == signal_name:
			_run_chain(n.id, 0.0)
		elif n.type == "Character Animation":
			var params: Dictionary = n.get("params", {})
			var state := _character_state(n.id)
			for slot in ["attack", "interact"]:
				if String(params.get(slot + "_when", "")) == signal_name:
					var animation := _slot(params, slot)
					if animation != "":
						state.one_shot = animation
						state.one_shot_until = now + _animation_length(animation)
						state.current = ""
			if String(params.get("hurt_when", "")) == signal_name:
				state.hurt_until = now + 0.4
				state.current = ""
			if String(params.get("die_when", "")) == signal_name:
				state.dead = true
				state.die_until = now + 0.8
				state.current = ""


func _is_grounded() -> bool:
	if is_class("RigidBody2D"):
		return call("get_contact_count") > 0
	if has_method("move_and_slide"):
		return call("is_on_floor")
	return false


func _is_down(button: String) -> bool:
	if button == "" or button == "None":
		return false
	if MOUSE_BUTTONS.has(button):
		return Input.is_mouse_button_pressed(MOUSE_BUTTONS[button])
	return Input.is_key_pressed(OS.find_keycode_from_string(button))


## Each On Button Pressed node watches its own key or mouse button, with edge
## detection so "when pressed" fires once instead of every frame.
func _run_button_events(delta: float) -> void:
	if graph == null:
		return
	for n in graph.nodes:
		if n.type != "On Button Pressed":
			continue
		var params: Dictionary = n.get("params", {})
		var down := _is_down(String(params.get("button", "G")))
		var was: bool = _button_states.get(n.id, false)
		_button_states[n.id] = down
		match String(params.get("mode", "When pressed")):
			"While held":
				if down:
					_run_chain(n.id, delta)
			"When released":
				if was and not down:
					_run_chain(n.id, delta)
			_:
				if down and not was:
					_run_chain(n.id, delta)


## Each On Input Action node listens for its own action name, with the same
## edge detection the button events use.
func _run_input_actions(delta: float) -> void:
	if graph == null:
		return
	for n in graph.nodes:
		if n.type != "On Input Action":
			continue
		var params: Dictionary = n.get("params", {})
		var action := String(params.get("action", ""))
		if not InputMap.has_action(action):
			continue

		var down := Input.is_action_pressed(action)
		var was: bool = _button_states.get("action:" + n.id, false)
		_button_states["action:" + n.id] = down
		match String(params.get("mode", "When pressed")):
			"While held":
				if down:
					_run_chain(n.id, delta)
			"When released":
				if was and not down:
					_run_chain(n.id, delta)
			_:
				if down and not was:
					_run_chain(n.id, delta)


func _run_event(event_type: String, delta: float) -> void:
	if graph == null:
		return
	for n in graph.nodes:
		if n.type == event_type:
			_run_chain(n.id, delta)


# --- running the graph --------------------------------------------------

func _run_chain(from_id: String, delta: float) -> void:
	for c in graph.connections:
		if c.from != from_id:
			continue
		var node := _find_node(c.to)
		if node.is_empty():
			continue
		## A gate returning false stops this branch, not the whole graph.
		var carry_on: bool = await _execute(node, delta)
		if carry_on:
			await _run_chain(c.to, delta)


func _find_node(id: String) -> Dictionary:
	for n in graph.nodes:
		if n.id == id:
			return n
	return {}


## Empty or "." means the node this graph is attached to.
func _resolve(params: Dictionary) -> Node:
	var path := String(params.get("target", ""))
	if path == "(what touched me)":
		return _last_body if _last_body != null else self
	if path == "" or path == ".":
		return self
	var found := get_node_or_null(NodePath(path))
	if found == null:
		found = find_child(path.get_file(), true, false)
	## Not one of ours - look through the whole running scene by name.
	if found == null:
		var scene: Node = get_tree().current_scene
		if scene == null:
			scene = get_tree().root
		if scene != null:
			if String(scene.name) == path:
				found = scene
			else:
				found = scene.find_child(path.get_file(), true, false)
	return found if found else self


func _execute(node: Dictionary, delta: float) -> bool:
	var params: Dictionary = node.get("params", {})
	match node.type:
		"Only If":
			return _only_if(params)
		"Wait Until":
			while not _only_if(params):
				await get_tree().process_frame
		"Repeat":
			for _i in int(params.get("count", 3.0)):
				await _run_chain(node.id, delta)
			return false
		"Random":
			return randf() * 100.0 < params.get("chance", 50.0)
		"Print":
			var parts := []
			if params.get("show_what_touched_me", false) and _last_body != null:
				parts.append(_last_body.name)
			parts.append(String(params.get("text", "Hello!")))
			if params.get("show_my_name", false):
				parts.append("(" + name + ")")
			print(" ".join(parts))
		"Move":
			_move(delta, params)
		"Jump":
			_jump(params, node.id)
		"Launch":
			_launch(params)
		"Fly":
			_fly(params)
		"Motor":
			_motor(params, delta)
		"Gravity":
			_set_gravity(params)
		"Rotate":
			var target := _resolve(params)
			target.set("rotation_degrees", target.get("rotation_degrees") + params.get("speed", 90.0) * delta)
		"Point Where Moving":
			_point_where_moving(delta, params)
		"Visibility":
			var seen := _resolve(params)
			match String(params.get("action", "Hide")):
				"Show":
					seen.set("visible", true)
				"Toggle":
					seen.set("visible", not seen.get("visible"))
				_:
					seen.set("visible", false)
		"Remember":
			_remember(params)
		"Health":
			_health(params)
		"Set Property":
			_set_property(params)
		"Set Color":
			var tint: Color = params.get("color", Color.WHITE)
			if params.get("random", false):
				tint = _ramp_color(params.get("ramp", {})) if params.get("use_color_ramp", false) else Color.from_hsv(randf(), 0.6, 1.0)
			_resolve(params).set("modulate", tint)
		"Character Animation":
			_character_animation(node.id, params)
		"Animation":
			await _animate(String(params.get("animation", "")), String(params.get("action", "Play")), params.get("wait_to_finish", false))
		"Play Sound":
			await _play_sound(node.id, params)
		"Spawn Scene":
			_spawn_scene(params)
		"Change Scene":
			if params.get("scene", "") != "":
				get_tree().change_scene_to_file(params.get("scene"))
		"Quit Game":
			get_tree().quit()
		"Dialogue":
			return await _dialogue(node.id, params)
		"Show Text":
			var label := _resolve({"target": params.get("label", "")})
			if label is Label:
				var key := String(params.get("value", ""))
				if String(params.get("show", "Text")) == "Value":
					if not key.begins_with("("):
						_live_labels[label] = [self, key]
					_refresh_labels()
				else:
					label.text = String(params.get("text", ""))
		"Send Signal":
			get_tree().call_group(LISTENER_GROUP, "_receive_signal", String(params.get("signal_name", "")))
		"Wait":
			await get_tree().create_timer(params.get("seconds", 1.0)).timeout
		"Destroy":
			var victim := _resolve(params)
			if victim != null:
				victim.queue_free()
		_:
			push_warning("Visuract: '%s' is not implemented yet." % node.type)
	return true


## Each run plays the next section on the picked Label2D. Once every section
## has been shown, runs cycle through the default responses instead. Runs
## while it is still talking, or during the section transition delay, are
## ignored.
func _dialogue(id: String, params: Dictionary) -> bool:
	var label: Node = _resolve({"target": params.get("label", "")})
	if not (label is Label):
		push_warning("Visuract on '%s': Dialogue needs a Label picked." % name)
		return false
	var state: Dictionary = _dialogue_states.get_or_add(id, {"section": 0, "response": 0, "busy": false, "ready_at": 0.0})
	var now := Time.get_ticks_msec() / 1000.0
	if state.busy or now < state.ready_at:
		return false

	var data: Dictionary = params.get("dialogue", {})
	var sections: Array = data.get("sections", [])
	var responses: Array = data.get("defaults", [])
	state.busy = true
	if state.section < sections.size():
		var section: Dictionary = sections[state.section]
		state.section += 1
		for line in section.get("lines", []):
			await _say(label, line)
			await get_tree().create_timer(line.get("delay", 0.0)).timeout
		state.ready_at = Time.get_ticks_msec() / 1000.0 + section.get("transition_delay", 0.0)
	elif not responses.is_empty():
		await _say(label, responses[state.response % responses.size()])
		state.response += 1
	state.busy = false
	return true


## The label is only shown while talking, so its panel and editor preview
## text never show on their own.
func _say(label: Label, line: Dictionary) -> void:
	label.text = String(line.get("text", ""))
	label.show()
	await get_tree().create_timer(line.get("duration", 2.0)).timeout
	if is_instance_valid(label):
		label.text = ""
		label.hide()


func _hide_dialogue_labels() -> void:
	if graph == null:
		return
	for n in graph.nodes:
		if n.type == "Dialogue":
			var label := _resolve({"target": n.get("params", {}).get("label", "")})
			if label is Label:
				label.hide()


## Remembers each target's scale the first time "Size" touches it, so 100
## means "as placed in the scene" instead of a hard reset to scale 1.0.
var _base_scale := {}

## Only the handful of properties the library offers, each written with the
## plain-English meaning its slider shows.
func _set_property(params: Dictionary) -> void:
	var target := _resolve(params)
	match String(params.get("property", "Size")):
		"Size":
			var id := target.get_instance_id()
			if not _base_scale.has(id):
				_base_scale[id] = target.get("scale")
			target.set("scale", _base_scale[id] * (params.get("size", 100.0) / 100.0))
		"Transparency":
			var tint: Color = target.get("modulate")
			tint.a = 1.0 - clampf(params.get("transparency", 0.0) / 100.0, 0.0, 1.0)
			target.set("modulate", tint)
		"Rotation":
			target.set("rotation_degrees", params.get("rotation", 0.0))
		"Layer":
			target.set("z_index", int(params.get("layer", 0.0)))


## Spawns into the running scene rather than under this node, so the copy
## survives if the spawner is destroyed.
func _spawn_scene(params: Dictionary) -> void:
	var picked := _pick_scene(params)
	var path := String(picked.get("scene", ""))
	if path == "":
		return
	var packed = load(path)
	if not (packed is PackedScene):
		push_warning("Visuract on '%s': can't load scene '%s'." % [name, path])
		return

	var copy: Node = packed.instantiate()
	var host: Node = get_tree().current_scene
	if host == null:
		host = get_parent()

	## Deferred, because spawning from On Ready happens while the parent is
	## still building its children. Both calls stay in order.
	host.add_child.call_deferred(copy)

	## The copy starts out facing the same way as whatever spawned it.
	if "facing" in copy:
		copy.set("facing", facing)

	if copy is Node2D:
		var origin: Node = self
		if String(picked.get("where", "On me")) == "At a node":
			origin = _resolve({"target": picked.get("spawn_point", "")})
		if origin is Node2D:
			## Offset X is mirrored, so it always means "in front of me".
			var offset := Vector2((picked.get("offset_x", 0.0) + randf_range(-1.0, 1.0) * picked.get("random_x", 0.0)) * facing, picked.get("offset_y", 0.0) + randf_range(-1.0, 1.0) * picked.get("random_y", 0.0))
			copy.set_deferred("global_position", origin.global_position + offset)


## Picks one scene entry by weight. Older graphs store a single path, with
## the placement on the node itself.
func _pick_scene(params: Dictionary) -> Dictionary:
	var value = params.get("scene", "")
	if value is String:
		return params
	var total := 0.0
	for entry in value:
		total += entry.weight
	var roll := randf() * total
	for entry in value:
		roll -= entry.weight
		if roll < 0.0:
			return entry
	return {}


## Each Play Sound node keeps its own AudioStreamPlayer child, so no scene
## setup is needed - picking a file is enough.
func _play_sound(id: String, params: Dictionary) -> void:
	var path := String(params.get("sound", ""))
	if path == "":
		return

	var stream = load(path)
	if stream == null:
		push_warning("Visuract on '%s': can't load sound '%s'." % [name, path])
		return

	var player: AudioStreamPlayer = _sound_players.get(id)
	if not is_instance_valid(player):
		player = AudioStreamPlayer.new()
		add_child(player)
		_sound_players[id] = player

	player.stream = stream
	player.volume_db = linear_to_db(clampf(params.get("volume", 100.0) / 100.0, 0.0, 1.0))
	player.play()

	## Waiting on the stream's own length, because the finished signal never
	## arrives for a looping sound or on a silent audio driver.
	if params.get("wait_to_finish", false):
		var length: float = stream.get_length()
		if length > 0.0:
			await get_tree().create_timer(length).timeout
		else:
			await player.finished


## The dropdown stores "PlayerPath / animation" - split it back apart. Works
## for both AnimationPlayer and AnimatedSprite2D.
func _animate(choice: String, action: String, wait_to_finish := false) -> void:
	if choice == "" or choice.begins_with("("):
		return
	var parts := choice.split(" / ")
	if parts.size() != 2:
		push_warning("Visuract on '%s': pick an animation on the Animation node." % name)
		return

	var player := get_node_or_null(NodePath(parts[0]))
	if player == null:
		player = find_child(String(parts[0]).get_file(), true, false)
	if player == null or not player.has_method("play"):
		push_warning("Visuract on '%s': can't find animation player '%s'." % [name, parts[0]])
		return

	match action:
		"Stop":
			if player.has_method("stop"):
				player.call("stop")
		"Pause":
			if player.has_method("pause"):
				player.call("pause")
			elif player.has_method("stop"):
				player.call("stop")
		"Resume":
			player.call("play")
		_:
			player.call("play", parts[1])
			## Chains after this one stay paused until the animation ends.
			## A looping animation never ends, so this would wait forever.
			if wait_to_finish and player.has_signal("animation_finished"):
				await player.animation_finished


# --- movement -----------------------------------------------------------

func _move(delta: float, params: Dictionary) -> void:
	var move_speed: float = params.get("speed", speed)
	var direction := _axis(params, "left", "right")
	var vertical := _axis(params, "up", "down")
	if direction != 0.0:
		facing = signf(direction)

	## RigidBody2D runs its own gravity - only steer it sideways, never write
	## position, or the physics server's integration gets overridden.
	if is_class("RigidBody2D"):
		var rigid_velocity: Vector2 = get("linear_velocity")
		rigid_velocity.x = _ramp(rigid_velocity.x, direction * move_speed, move_speed, delta, params)
		if vertical != 0.0:
			rigid_velocity.y = vertical * move_speed
		set("linear_velocity", rigid_velocity)
		return

	if not has_method("move_and_slide"):
		set("position", get("position") + Vector2(direction, vertical) * move_speed * delta)
		return

	var velocity: Vector2 = get("velocity")
	velocity.x = _ramp(velocity.x, direction * move_speed, move_speed, delta, params)
	## A pressed up/down button drives Y directly instead of gravity.
	if vertical != 0.0:
		velocity.y = vertical * move_speed
	elif _gravity_on:
		velocity.y += gravity * _gravity_strength * delta
	set("velocity", velocity)
	call("move_and_slide")


## Eases current speed toward target. Speeding up uses Acceleration, letting
## go uses Deceleration - both 0 (slow) to 100 (instant).
func _ramp(current: float, target: float, move_speed: float, delta: float, params: Dictionary) -> float:
	var rate: float = params.get("acceleration", 100.0) if target != 0.0 else params.get("deceleration", 100.0)
	if rate >= 100.0:
		return target
	var grip: float = lerp(1.0, 30.0, clampf(rate / 100.0, 0.0, 1.0))
	return move_toward(current, target, move_speed * delta * grip)


## -1, 0 or 1 from a pair of button params.
func _axis(params: Dictionary, negative: String, positive: String) -> float:
	var amount := 0.0
	if _is_down(String(params.get(negative, "None"))):
		amount -= 1.0
	if _is_down(String(params.get(positive, "None"))):
		amount += 1.0
	return amount


func _jump(params: Dictionary, id: String) -> void:
	var down := _is_down(String(params.get("button", "Space")))
	var was: bool = _button_states.get("jump:" + id, false)
	_button_states["jump:" + id] = down
	if not down or was:
		return
	if not _can_jump(params):
		return

	## Used up, so the coyote window can't give a second jump mid-air.
	_grounded_at = -999.0
	var height: float = params.get("height", jump_force)

	if is_class("RigidBody2D"):
		var rigid_velocity: Vector2 = get("linear_velocity")
		rigid_velocity.y = -height
		set("sleeping", false)
		set("linear_velocity", rigid_velocity)
		return

	if has_method("move_and_slide"):
		var velocity: Vector2 = get("velocity")
		velocity.y = -height
		set("velocity", velocity)


## On the ground, or within the coyote window just after leaving it.
func _can_jump(params: Dictionary) -> bool:
	if _is_grounded():
		return true
	if not params.get("coyote_time", false):
		return false
	var window: float = params.get("coyote_seconds", 0.12)
	return Time.get_ticks_msec() / 1000.0 - _grounded_at <= window


## CharacterBody2D falls by Visuract's own gravity in Move; RigidBody2D uses
## the physics server's, so it gets gravity_scale instead.
func _set_gravity(params: Dictionary) -> void:
	match String(params.get("action", "Turn off")):
		"Turn on":
			_gravity_on = true
		"Toggle":
			_gravity_on = not _gravity_on
		_:
			_gravity_on = false
	if params.has("strength"):
		_gravity_strength = params.strength / 100.0

	if is_class("RigidBody2D"):
		set("sleeping", false)
		set("gravity_scale", _base_gravity_scale * _gravity_strength if _gravity_on else 0.0)

## One push in a fixed direction. Facing comes from whatever moved last, so a
## spawned bullet flies the way its spawner was facing.
func _launch(params: Dictionary) -> void:
	var speed_value: float = float(params.get("speed", 400.0))
	var heading := _heading(String(params.get("direction", "Where I'm facing")))

	if is_class("RigidBody2D"):
		set("sleeping", false)
		set("linear_velocity", heading * speed_value)
	elif has_method("move_and_slide"):
		set("velocity", heading * speed_value)
	elif is_class("Node2D"):
		_drift = heading * speed_value

	if heading.x != 0.0:
		facing = signf(heading.x)
		if params.get("flip_to_face", true):
			_face_own_art(facing < 0.0)


func _heading(direction: String) -> Vector2:
	match direction:
		"Left":
			return Vector2.LEFT
		"Right":
			return Vector2.RIGHT
		"Up":
			return Vector2.UP
		"Down":
			return Vector2.DOWN
		"Where I'm pointing":
			return Vector2.RIGHT.rotated(get("rotation"))
	return Vector2(facing, 0.0)


## Body adds speed every physics frame, so it builds up like a real motor.
## Works on velocity rather than force, so light and heavy bodies speed up
## the same. No buttons picked means always on, going forward.
func _motor(params: Dictionary, delta: float) -> void:
	_motor_tilt(params, delta)
	var always := String(params.get("forward", "None")) == "None" and String(params.get("backward", "None")) == "None"
	var direction := 1.0 if always else _axis(params, "backward", "forward")
	if String(params.get("drive", "Body")) == "Wheel joint":
		_wheel_motor(params, direction)
		return
	if direction == 0.0 or not is_class("RigidBody2D"):
		return
	var heading := _heading(String(params.get("direction", "Where I'm pointing")))
	set("sleeping", false)
	set("linear_velocity", get("linear_velocity") + heading * params.get("push", 600.0) * direction * delta)
	set("angular_velocity", get("angular_velocity") + deg_to_rad(params.get("spin", 0.0)) * direction * delta)


## Leans the picked body - empty means this one - on its own buttons, in the
## air too. Forward tips the nose down (clockwise), back lifts it for a wheelie.
func _motor_tilt(params: Dictionary, delta: float) -> void:
	var lean := _axis(params, "tilt_back", "tilt_forward")
	if lean == 0.0:
		return
	var body := _resolve({"target": params.get("tilt_body", "")})
	if not body is RigidBody2D:
		return
	body.sleeping = false
	body.angular_velocity += deg_to_rad(params.get("tilt", 360.0)) * lean * delta


## Uses the joint's own motor (Godot 4.2+), so Speed is also the top speed.
func _wheel_motor(params: Dictionary, direction: float) -> void:
	var joint := _resolve({"target": params.get("joint", "")})
	if not joint is PinJoint2D:
		return
	joint.motor_enabled = direction != 0.0
	joint.motor_target_velocity = deg_to_rad(params.get("speed", 720.0)) * direction
	## A parked car falls asleep, and a sleeping body ignores the motor.
	if direction != 0.0:
		for path in [joint.node_a, joint.node_b]:
			var body := joint.get_node_or_null(path)
			if body is RigidBody2D:
				body.sleeping = false


## Turns the art, not the body - physics resets a RigidBody2D's rotation -
## and not the colliders. Lean reaches its full down angle at FULL_LEAN_SPEED.
const FULL_LEAN_SPEED := 600.0

func _point_where_moving(delta: float, params: Dictionary) -> void:
	var velocity := _body_velocity()
	var turn: float = params.get("turn_speed", 50.0)
	var weight := 1.0 if turn >= 100.0 else 1.0 - exp(-turn / 5.0 * delta)
	var lean := String(params.get("mode", "Face direction")) == "Lean"
	for child in get_children():
		if not child is Node2D or child.is_class("CollisionShape2D") or child.is_class("CollisionPolygon2D"):
			continue
		## Mirrored art turns the mirrored way, so it never ends up upside down.
		var side := signf(child.scale.x)
		var target: float = child.rotation
		if lean:
			var degrees: float = params.get("up_angle", -30.0) if velocity.y < 0.0 else params.get("down_angle", 90.0) * clampf(velocity.y / FULL_LEAN_SPEED, 0.0, 1.0)
			target = deg_to_rad(degrees * side)
		elif velocity.length() > 1.0:
			target = (velocity * side).angle()
		child.rotation = lerp_angle(child.rotation, target, weight)


## Mirrors the art by flipping each visual child's X scale. Not the body
## itself - a RigidBody2D has its scale managed by the physics server and
## resets it - and not the colliders, which should stay put.
func _face_own_art(facing_left: bool) -> void:
	for child in get_children():
		if not child is Node2D:
			continue
		if child.is_class("CollisionShape2D") or child.is_class("CollisionPolygon2D"):
			continue
		var art := child as Node2D
		var current_scale := art.scale
		current_scale.x = -absf(current_scale.x) if facing_left else absf(current_scale.x)
		art.scale = current_scale


## Continuous thrust while the button is held - no ground check, no edge
## detection, so it keeps pushing every physics frame.
func _fly(params: Dictionary) -> void:
	if not _is_down(String(params.get("button", "Space"))):
		return
	var power: float = params.get("power", 600.0)
	## 100 snaps straight to full thrust, 0 is a slow heavy climb.
	var eagerness: float = clampf(params.get("acceleration", 100.0) / 100.0, 0.0, 1.0)
	## Absent when the Max Speed field is hidden, which means no limit.
	var cap: float = params.get("max_speed", 0.0)

	if is_class("RigidBody2D"):
		var rigid_velocity: Vector2 = get("linear_velocity")
		rigid_velocity.y = _capped(_thrust(rigid_velocity.y, power, eagerness), cap)
		set("sleeping", false)
		set("linear_velocity", rigid_velocity)
		return

	if has_method("move_and_slide"):
		var velocity: Vector2 = get("velocity")
		velocity.y = _capped(_thrust(velocity.y, power, eagerness), cap)
		set("velocity", velocity)


func _thrust(current: float, power: float, eagerness: float) -> float:
	if eagerness >= 1.0:
		return -power
	return lerpf(current, -power, maxf(eagerness, 0.01))


func _capped(vertical_speed: float, cap: float) -> float:
	return vertical_speed if cap <= 0.0 else maxf(vertical_speed, -cap)


# --- character animation ------------------------------------------------

## Dropdown placeholders like "(none)" mean the slot was left empty.
func _slot(params: Dictionary, key: String) -> String:
	var value := String(params.get(key, ""))
	return "" if value.begins_with("(") else value


## Walks up from the target, so hitting a child hurtbox still finds the
## Visuract node that owns the health.
func _health(params: Dictionary) -> void:
	var holder := _resolve(params)
	while holder != null and not holder.has_method("change_health"):
		holder = holder.get_parent()
	if holder == null:
		push_warning("Visuract on '%s': Health target has no Visuract script." % name)
		return
	var mode := String(params.get("mode", "Damage"))
	var amount: float = params.get("amount", 1.0)
	var before: float = holder.get("health")
	holder.call("change_health", mode, amount, params.get("invincible_seconds", 0.0), String(params.get("save_as", "")).strip_edges())
	if params.get("print", false):
		print(_health_message(holder, mode, before))


func _health_message(holder: Node, mode: String, before: float) -> String:
	var now: float = holder.get("health")
	var max_hp: float = holder.get("max_health")
	var hp := "(%s/%s)" % [String.num(now), String.num(max_hp)]
	if mode == "Set max":
		return "%s: health set %s" % [holder.name, hp]
	if max_hp <= 0.0:
		return "%s: no health yet - use Health (Set max) first" % holder.name
	if before <= 0.0:
		return "%s: already dead, %s ignored" % [holder.name, mode.to_lower()]
	if mode == "Heal":
		return "%s: healed %s %s" % [holder.name, String.num(now - before), hp]
	if now == before:
		return "%s: invincible, no damage %s" % [holder.name, hp]
	return "%s: took %s damage %s%s" % [holder.name, String.num(before - now), hp, " and died" if now <= 0.0 else ""]


## Public, so another node's Health (What Touched Me) can change this one.
## save_as only matters for Set max; the key then sticks to this node, so
## damage from anything else is saved too.
func change_health(mode: String, amount: float, invincible_seconds := 0.0, save_as := "") -> void:
	var now := Time.get_ticks_msec() / 1000.0
	match mode:
		"Set max":
			max_health = amount
			health = amount
			_health_key = save_as
			if _health_key != "" and globals.has(_health_key):
				health = clampf(String(globals[_health_key]).to_float(), 0.0, max_health)
		_:
			if max_health <= 0.0:
				push_warning("Visuract on '%s': use Health (Set max) before Damage or Heal." % name)
				return
			## Already dead - only Set max brings it back.
			if health <= 0.0:
				return
			if mode == "Heal":
				health = minf(health + amount, max_health)
			else:
				if now < _invincible_until:
					return
				health = maxf(health - amount, 0.0)
				_invincible_until = now + invincible_seconds
	health_changed.emit(health, max_health)
	if health <= 0.0 and mode != "Set max":
		## Cleared, so the next Set max after dying starts full.
		globals.erase(_health_key)
		died.emit()
		_run_event("On Died", 0.0)
	elif _health_key != "":
		globals[_health_key] = str(health)


## Where a variable lives, by scope.
func _var_store(params: Dictionary) -> Dictionary:
	return locals if String(params.get("scope", "Whole game")) == "This node only" else globals


func _remember(params: Dictionary) -> void:
	var store := _var_store(params)
	var key := String(params.get("variable_name", ""))
	if key == "":
		return
	var raw := String(params.get("value", "0"))
	var mode := String(params.get("mode", "Set to"))

	if mode == "Set to":
		store[key] = raw
		_refresh_labels()
		return

	## Add / Subtract / Keep highest work on numbers; a missing variable starts at 0.
	var current := float(store.get(key, 0))
	var amount := raw.to_float()
	if mode == "Keep highest":
		amount = float(store.get(String(params.get("from", "")), 0))
	match mode:
		"Add":
			store[key] = _num(current + amount)
		"Subtract":
			store[key] = _num(current - amount)
		_:
			store[key] = _num(maxf(current, amount))
	_refresh_labels()


## Whole numbers without ".0", so a score reads "2" instead of "2.0".
static func _num(value: float) -> String:
	return str(int(value)) if value == roundf(value) else String.num(value)


static func _refresh_labels() -> void:
	for label in _live_labels.keys():
		var bind: Array = _live_labels[label]
		if not is_instance_valid(label) or not is_instance_valid(bind[0]):
			_live_labels.erase(label)
			continue
		label.text = String(bind[0].locals.get(bind[1], globals.get(bind[1], "")))


func _only_if(params: Dictionary) -> bool:
	var store := _var_store(params)
	var key := String(params.get("variable_name", ""))
	var have: Variant = store.get(key, "")
	match String(params.get("test", "is On")):
		"is On":
			return String(have) == "On"
		"is Off":
			return String(have) != "On"
		"equals":
			return String(have) == String(params.get("value", ""))
		"is not":
			return String(have) != String(params.get("value", ""))
		"is at least":
			return float(have) >= String(params.get("value", "0")).to_float()
		"is at most":
			return float(have) <= String(params.get("value", "0")).to_float()
		"is more than":
			return float(have) > String(params.get("value", "0")).to_float()
		"is less than":
			return float(have) < String(params.get("value", "0")).to_float()
	return false


func _character_state(id: String) -> Dictionary:
	if not _character_states.has(id):
		_character_states[id] = {
			"dead": false, "hurt_until": 0.0, "die_until": 0.0,
			"land_until": 0.0, "was_grounded": true, "fall_speed": 0.0, "current": "",
			"one_shot": "", "one_shot_until": 0.0,
		}
	return _character_states[id]


func _body_velocity() -> Vector2:
	if is_class("RigidBody2D"):
		return get("linear_velocity")
	if has_method("move_and_slide"):
		return get("velocity")
	return Vector2.ZERO


## Highest matching state wins: dead, hurt, landing, airborne, crouch, walk,
## then idle. Empty slots are skipped, so a half-filled node still works.
func _character_animation(id: String, params: Dictionary) -> void:
	var state := _character_state(id)
	var now := Time.get_ticks_msec() / 1000.0
	var grounded := _is_grounded()
	var velocity := _body_velocity()
	var side := String(params.get("game_type", "Side view")) == "Side view"

	## Only a real fall counts as a landing, so spawning on the ground or
	## brushing a slope doesn't trigger it.
	if grounded and not state.was_grounded and state.fall_speed > 50.0:
		state.land_until = now + 0.18
	state.was_grounded = grounded
	state.fall_speed = velocity.y

	var choice := ""
	if state.dead:
		choice = _slot(params, "dead_idle") if now > state.die_until else _slot(params, "die")
		if choice == "":
			choice = _slot(params, "die")
	elif now < state.hurt_until:
		choice = _slot(params, "hurt")
	elif now < state.one_shot_until:
		choice = state.one_shot
	elif side and grounded and now < state.land_until and absf(velocity.x) < 10.0:
		choice = _slot(params, "landing")
	elif side and not grounded:
		choice = _slot(params, "jump") if velocity.y < -10.0 else _slot(params, "falling")
	elif side and grounded and _is_down(String(params.get("crouch_button", "None"))):
		choice = _slot(params, "crouch")
	elif side and absf(velocity.x) > 10.0:
		choice = _slot(params, "walk")
	elif not side and velocity.length() > 10.0:
		choice = _directional_walk(velocity, params)

	if choice == "":
		choice = _slot(params, "idle")
	if choice == "":
		return

	if side and params.get("flip_to_face", true) and absf(velocity.x) > 10.0:
		facing = signf(velocity.x)
		_face(choice, facing < 0.0)

	if choice != state.current:
		state.current = choice
		_animate(choice, "Play")


## How long an animation runs, so a one-shot holds for exactly that long.
func _animation_length(choice: String) -> float:
	var parts := choice.split(" / ")
	if parts.size() != 2:
		return 0.5
	var player := get_node_or_null(NodePath(parts[0]))
	if player == null:
		return 0.5

	## AnimatedSprite2D also has get_animation(), but it takes no arguments -
	## check the class rather than the method name.
	if player.is_class("AnimationPlayer"):
		var animation = player.call("get_animation", parts[1])
		if animation != null:
			return animation.length

	var frames = player.get("sprite_frames")
	if frames != null and frames.has_animation(parts[1]):
		var speed: float = frames.get_animation_speed(parts[1])
		if speed > 0.0:
			return frames.get_frame_count(parts[1]) / speed
	return 0.5


## Whichever direction the character is moving in most.
func _directional_walk(velocity: Vector2, params: Dictionary) -> String:
	if absf(velocity.x) > absf(velocity.y):
		return _slot(params, "walk_left" if velocity.x < 0.0 else "walk_right")
	return _slot(params, "walk_up" if velocity.y < 0.0 else "walk_down")


## Mirrors an AnimatedSprite2D with flip_h, or the whole node otherwise.
func _face(choice: String, facing_left: bool) -> void:
	var parts := choice.split(" / ")
	if parts.size() != 2:
		return
	var player := get_node_or_null(NodePath(parts[0]))
	if player != null and "flip_h" in player:
		player.set("flip_h", facing_left)
		return
	var current_scale: Vector2 = get("scale")
	current_scale.x = -absf(current_scale.x) if facing_left else absf(current_scale.x)
	set("scale", current_scale)


## A random color from somewhere along the ramp.
func _ramp_color(ramp: Dictionary) -> Color:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array(ramp.get("offsets", [0.0, 1.0]))
	gradient.colors = PackedColorArray(ramp.get("colors", [Color("ff6ec7"), Color("4a8cff")]))
	return gradient.sample(randf())
