extends Node
## Menu/input evidence on the real exported scene; ending panels use explicit fixtures.

const FRAME_LIMIT := 2400
const SETTLE_FRAMES := 4
var game: Node
var frames := 0
var finished := false


func _ready() -> void:
	_run.call_deferred()


func _process(_delta: float) -> void:
	frames += 1
	if frames > FRAME_LIMIT:
		_fail("frame budget exhausted")


func _run() -> void:
	await _settle()
	game = get_tree().current_scene
	if game == null or not _panel("title", "LOWTIDE VIGIL", "BEGIN THE VIGIL"):
		_fail("real title scene required")
		return
	if not await _fullscreen():
		return
	for joypad in [false, true]:
		if not await _menus(joypad):
			return
	if finished:
		return
	finished = true
	print("DESKTOP ACCEPTANCE: passed")
	get_tree().quit(0)


# Stop immediately at a failed observation; never print success after a failure.
# gdlint: disable=max-returns
func _menus(joypad: bool) -> bool:
	var device := "joypad" if joypad else "keyboard"
	if not _panel("title", "LOWTIDE VIGIL", "BEGIN THE VIGIL"):
		return false
	await _navigate(joypad)
	if not _focus("CONTROLS & THE LANTERN"):
		return false
	await _accept(joypad)
	if not _panel("title", "CARRY THE LIGHT", "BACK TO THE SHORE"):
		return false
	await _accept(joypad)
	if not _panel("title", "LOWTIDE VIGIL", "BEGIN THE VIGIL"):
		return false
	print("DESKTOP ACCEPTANCE: %s controls/back" % device)
	await _accept(joypad)
	if not _fresh():
		return false
	await _pause(joypad)
	if not _panel("paused", "THE VIGIL WAITS", "RESUME"):
		return false
	await _pause(joypad)
	if not _play():
		return false
	print("DESKTOP ACCEPTANCE: %s pause/resume" % device)
	await _pause(joypad)
	if not _panel("paused", "THE VIGIL WAITS", "RESUME"):
		return false
	await _navigate(joypad)
	if not _focus("RESTART"):
		return false
	await _accept(joypad)
	if not _fresh():
		return false
	print("DESKTOP ACCEPTANCE: %s restart" % device)
	if joypad and not await _sticks():
		return false
	await _pause(joypad)
	if not _panel("paused", "THE VIGIL WAITS", "RESUME"):
		return false
	await _navigate(joypad)
	await _navigate(joypad)
	if not _focus("RETURN TO SHORE"):
		return false
	await _accept(joypad)
	if not _shore():
		return false
	for ending in ["lost", "won"]:
		await _accept(joypad)
		if not _fresh():
			return false
		# Stage only the ending panel. This is menu evidence, not a combat outcome.
		game.call("_lose_run" if ending == "lost" else "_win_run")
		await _settle()
		var heading := "THE LANTERN GOES OUT" if ending == "lost" else "THE TOLLING FALLS SILENT"
		var replay := "TRY THE VIGIL AGAIN" if ending == "lost" else "CARRY ANOTHER LIGHT"
		if not _panel(ending, heading, replay):
			return false
		await _navigate(joypad)
		if not _focus("RETURN TO SHORE"):
			return false
		await _accept(joypad)
		if not _shore():
			return false
		print("DESKTOP ACCEPTANCE: %s %s fixture/shore" % [device, ending])
	return true


func _fullscreen() -> bool:
	var viewport := game.get_viewport()
	var headless := DisplayServer.get_name() == "headless"
	var original := DisplayServer.window_get_mode()
	for index in 2:
		var before := DisplayServer.window_get_mode()
		var event := _key(KEY_F11)
		event.pressed = true
		viewport.push_input(event, true)
		if not viewport.is_input_handled():
			return _fail("F11 did not reach the global handler")
		await _settle()
		var after := DisplayServer.window_get_mode()
		var expected := DisplayServer.WINDOW_MODE_FULLSCREEN
		if before == DisplayServer.WINDOW_MODE_FULLSCREEN:
			expected = DisplayServer.WINDOW_MODE_WINDOWED
		if not headless and after != expected:
			return _fail("F11 did not change the window mode")
		event.echo = true
		viewport.push_input(event, true)
		if viewport.is_input_handled() or DisplayServer.window_get_mode() != after:
			return _fail("F11 echo was accepted")
		event.echo = false
		event.pressed = false
		viewport.push_input(event, true)
		if viewport.is_input_handled() or DisplayServer.window_get_mode() != after:
			return _fail("F11 release was accepted")
		print("DESKTOP ACCEPTANCE: F11 press/echo/release %d" % (index + 1))
	if not headless and DisplayServer.window_get_mode() != original:
		return _fail("two F11 presses did not restore the window mode")
	if headless:
		print("DESKTOP ACCEPTANCE: headless window-mode transitions unverified")
	return true


func _sticks() -> bool:
	# Let the accepted menu A press finish any ordinary dash before measuring movement.
	await _settle(24)
	var before: Vector2 = game.keeper.position
	_axis(JOY_AXIS_LEFT_X, 1.0)
	await _settle(10)
	_axis(JOY_AXIS_LEFT_X, 0.0)
	if game.keeper.position.x <= before.x:
		return _fail("left stick did not move the keeper")
	_axis(JOY_AXIS_RIGHT_X, 1.0)
	await _settle(10)
	_axis(JOY_AXIS_RIGHT_X, 0.0)
	var friendly := false
	for bolt in game.bolts:
		if not bolt.hostile and bolt.direction.x > 0.0:
			friendly = true
	if not friendly:
		return _fail("right stick did not fire a friendly bolt")
	await _settle()
	if Input.get_axis("move_left", "move_right") != 0.0:
		return _fail("left stick remained pressed")
	if Input.get_axis("aim_left", "aim_right") != 0.0:
		return _fail("right stick remained pressed")
	print("DESKTOP ACCEPTANCE: joypad sticks/release")
	return true


func _navigate(joypad: bool) -> void:
	await _tap(_button(JOY_BUTTON_DPAD_DOWN) if joypad else _key(KEY_DOWN))


func _accept(joypad: bool) -> void:
	await _tap(_button(JOY_BUTTON_A) if joypad else _key(KEY_ENTER))


func _pause(joypad: bool) -> void:
	await _tap(_button(JOY_BUTTON_START) if joypad else _key(KEY_ESCAPE))


func _tap(event: InputEvent) -> void:
	event.set("pressed", true)
	Input.parse_input_event(event)
	await _settle()
	var release := event.duplicate() as InputEvent
	release.set("pressed", false)
	Input.parse_input_event(release)
	await _settle()


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	return event


func _button(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	return event


func _axis(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)


func _settle(count: int = SETTLE_FRAMES) -> void:
	for _frame in count:
		await get_tree().process_frame


func _panel(state: String, heading: String, focus: String) -> bool:
	if game.state != state or not game.ui.overlay.visible:
		return _fail("expected panel state " + state)
	if game.ui.panel.get_child(0).text != heading:
		return _fail("expected heading " + heading)
	return _focus(focus)


func _focus(label: String) -> bool:
	var focus := game.get_viewport().gui_get_focus_owner() as Button
	if focus == null or focus.text != label or not game.ui.panel.is_ancestor_of(focus):
		return _fail("expected focused button " + label)
	if focus.disabled or not focus.is_visible_in_tree():
		return _fail("focused button unavailable: " + label)
	return true


func _play() -> bool:
	if game.state != "play" or game.ui.overlay.visible:
		return _fail("expected ordinary play without overlay")
	if game.get_viewport().gui_get_focus_owner() != null:
		return _fail("hidden menu retained focus")
	return true


func _fresh() -> bool:
	if not _play():
		return false
	if game.room != 0 or game.keeper.hp != 5 or game.embers != 0 or game.doors.size() != 3:
		return _fail("begin/restart did not reset the run")
	return true


func _shore() -> bool:
	if not _panel("title", "LOWTIDE VIGIL", "BEGIN THE VIGIL"):
		return false
	if game.keeper.visible or game.veil.visible or not game.ui.hud.text.is_empty():
		return _fail("shore retained gameplay presentation")
	if not game.foes.is_empty() or not game.bolts.is_empty() or not game.doors.is_empty():
		return _fail("shore retained room entities")
	return true


func _fail(message: String) -> bool:
	if not finished:
		finished = true
		push_error("DESKTOP ACCEPTANCE: " + message)
		get_tree().quit(1)
	return false
