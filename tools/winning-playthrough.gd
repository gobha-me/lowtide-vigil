extends SceneTree
## External observer/controller: all gameplay changes come from ordinary input events.

const ROUTE := ["EMBERS", "FONT", "EMBERS", "FONT", "THE DROWNED TOLLING"]
const MAX_FRAMES := 18000
const WAYPOINTS := [Vector2(1100, 580), Vector2(1100, 240), Vector2(180, 240), Vector2(180, 580)]

var game: Node
var frame := 0
var menu_stage := 0
var stage_frame := 0
var previous_room := 0
var waypoint := 0
var saw_phase := false
var saw_boss := false
var saw_title := false
var dash_count := 0
var last_hp := 5
var finished := false


func _initialize() -> void:
	seed(3)
	_load_game.call_deferred()


func _load_game() -> void:
	var scene := load("res://scenes/vigil.tscn") as PackedScene
	if scene == null:
		_fail("packed main scene missing")
		return
	game = scene.instantiate()
	root.add_child(game)
	current_scene = game


func _process(_delta: float) -> bool:
	if finished or game == null:
		return false
	frame += 1
	if frame >= MAX_FRAMES:
		_fail("frame budget exhausted")
		return false
	if menu_stage < 6:
		_title_input()
		return false
	_play_input()
	return false


func _play_input() -> void:
	if game.keeper.hp != last_hp:
		last_hp = game.keeper.hp
		print("PLAYTHROUGH HP frame=%d room=%d hp=%d" % [frame, game.room, last_hp])
	if game.state == "lost" or game.keeper.hp <= 0:
		_fail("lantern extinguished")
		return
	if game.room != previous_room:
		if game.room != previous_room + 1 or game.reward != ROUTE[previous_room]:
			_fail("unexpected room transition")
			return
		previous_room = game.room
		waypoint = 0
		print(
			(
				"PLAYTHROUGH ROOM frame=%d room=%d reward=%s hp=%d foes=%d"
				% [frame, game.room, game.reward, game.keeper.hp, game.foes.size()]
			)
		)
	if game.state == "won":
		_verify_win()
		return
	if game.state != "play":
		_fail("unexpected gameplay panel: " + game.state)
		return
	if game.foes.is_empty():
		_walk_to_door()
	else:
		_fight()
	if frame % 600 == 0:
		print(
			(
				"PLAYTHROUGH PROGRESS frame=%d room=%d hp=%d foes=%d position=%s"
				% [frame, game.room, game.keeper.hp, game.foes.size(), game.keeper.position]
			)
		)


func _title_input() -> void:
	if frame - stage_frame < 8:
		return
	stage_frame = frame
	match menu_stage:
		0:
			if game.state != "title" or not _panel_has("LOWTIDE VIGIL"):
				_fail("title missing")
				return
			saw_title = true
			print("PLAYTHROUGH TITLE frame=%d" % frame)
			_key(KEY_DOWN, true)
		1:
			_key(KEY_DOWN, false)
			_key(KEY_ENTER, true)
		2:
			_key(KEY_ENTER, false)
			if not _panel_has("CARRY THE LIGHT"):
				_fail("controls button did not open controls")
				return
			print("PLAYTHROUGH CONTROLS frame=%d" % frame)
			_key(KEY_ENTER, true)
		3:
			_key(KEY_ENTER, false)
			if not _panel_has("LOWTIDE VIGIL"):
				_fail("back button did not return to title")
				return
			_key(KEY_ENTER, true)
		4:
			_key(KEY_ENTER, false)
			if game.state != "play" or game.room != 0 or game.keeper.hp != 5:
				_fail("begin button did not start an ordinary run")
				return
			print("PLAYTHROUGH BEGIN frame=%d hp=%d" % [frame, game.keeper.hp])
		5:
			pass
	menu_stage += 1


func _walk_to_door() -> void:
	_axis(JOY_AXIS_RIGHT_X, 0.0)
	_axis(JOY_AXIS_RIGHT_Y, 0.0)
	_key(KEY_SPACE, false)
	if game.room >= ROUTE.size():
		_fail("boss absent without victory")
		return
	for door in game.doors:
		if door.reward == ROUTE[game.room] and door.unlocked:
			_move((door.position + Vector2(0, 20) - game.keeper.position).normalized())
			return
	_fail("chosen door missing after clear")


func _fight() -> void:
	var position: Vector2 = game.keeper.position
	var nearest: Node2D = game.foes[0]
	for foe in game.foes:
		if (
			position.distance_squared_to(foe.position)
			< position.distance_squared_to(nearest.position)
		):
			nearest = foe
		if foe.kind == "boss":
			if not saw_boss:
				if game.room != 5 or foe.hp != 100.0 or foe.max_hp != 100.0:
					_fail("boss did not start at 100 hp")
					return
				saw_boss = true
				print("PLAYTHROUGH BOSS frame=%d hp=%g max_hp=%g" % [frame, foe.hp, foe.max_hp])
			if foe.second_phase and not saw_phase:
				saw_phase = true
				print("PLAYTHROUGH PHASE2 frame=%d boss_hp=%g hp=%d" % [frame, foe.hp, last_hp])
	var aim := (nearest.position - position).normalized()
	_axis(JOY_AXIS_RIGHT_X, aim.x)
	_axis(JOY_AXIS_RIGHT_Y, aim.y)
	if position.distance_to(WAYPOINTS[waypoint]) < 35.0:
		waypoint = (waypoint + 1) % WAYPOINTS.size()
	var movement: Vector2 = (WAYPOINTS[waypoint] - position).normalized()
	_move(movement)
	var danger := false
	for bolt in game.bolts:
		if bolt.hostile and position.distance_to(bolt.position) < 85.0:
			var relative: Vector2 = bolt.direction * bolt.speed - movement * 235.0
			var offset: Vector2 = bolt.position - position
			var time := clampf(
				-offset.dot(relative) / maxf(1.0, relative.length_squared()), 0, 0.22
			)
			if (offset + relative * time).length() < 38.0:
				danger = true
	if position.distance_to(nearest.position) < nearest.radius + 85.0:
		danger = true
	var dash: bool = danger and game.keeper.dash_cooldown <= 0.0
	_key(KEY_SPACE, dash)
	if dash:
		dash_count += 1


func _verify_win() -> void:
	if (
		not saw_title
		or not saw_boss
		or not saw_phase
		or previous_room != 5
		or game.keeper.hp <= 0
		or game.kills != 11
		or not game.foes.is_empty()
		or not game.upgrades.is_empty()
		or not game.ui.overlay.visible
		or not _panel_has("THE TOLLING FALLS SILENT")
		or not _panel_has("CARRY ANOTHER LIGHT")
	):
		_fail("incomplete victory evidence")
		return
	print(
		(
			"PLAYTHROUGH PASS frame=%d hp=%d phase2=%s kills=%d dashes=%d route=%s"
			% [frame, game.keeper.hp, saw_phase, game.kills, dash_count, ",".join(ROUTE)]
		)
	)
	finished = true
	quit(0)


func _panel_has(text: String) -> bool:
	for child in game.ui.panel.get_children():
		if (child is Label or child is Button) and child.text == text:
			return true
	return false


func _move(direction: Vector2) -> void:
	_axis(JOY_AXIS_LEFT_X, direction.x)
	_axis(JOY_AXIS_LEFT_Y, direction.y)


func _axis(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _fail(reason: String) -> void:
	printerr("PLAYTHROUGH FAIL frame=%d reason=%s" % [frame, reason])
	finished = true
	quit(1)
