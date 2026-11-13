extends GutTest
## Native events reach the real scene and GUI; no game or controls script is replaced.

const Snapshot = preload("res://test/helpers/native_input_snapshot.gd")
const VIGIL = preload("res://scenes/vigil.tscn")

var snapshot: RefCounted
var viewport: SubViewport
var game: Node2D


func before_each() -> void:
	snapshot = Snapshot.new()
	snapshot.capture()
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 800)
	viewport.handle_input_locally = true
	add_child_autoqfree(viewport)
	game = VIGIL.instantiate()
	viewport.add_child(game)
	# Advance the real process explicitly for deterministic input edges and movement.
	game.set_process(false)
	await _frames()


func after_each() -> void:
	game.set_process_input(false)
	viewport.gui_release_focus()
	snapshot.restore()


func test_dpad_and_a_traverse_controls_back_and_begin_with_visible_focus() -> void:
	if not _focus("BEGIN THE VIGIL"):
		return
	await _tap(JOY_BUTTON_DPAD_DOWN)
	if not _focus("CONTROLS & THE LANTERN"):
		return
	assert_false(Input.is_action_pressed("ui_down"), "D-pad release clears menu action")
	await _tap(JOY_BUTTON_A)
	assert_eq(game.ui.panel.get_child(0).text, "CARRY THE LIGHT")
	if not _focus("BACK TO THE SHORE"):
		return
	await _tap(JOY_BUTTON_A)
	assert_eq(game.ui.panel.get_child(0).text, "LOWTIDE VIGIL")
	if not _focus("BEGIN THE VIGIL"):
		return
	await _tap(JOY_BUTTON_DPAD_DOWN)
	await _tap(JOY_BUTTON_DPAD_UP)
	if not _focus("BEGIN THE VIGIL"):
		return
	await _tap(JOY_BUTTON_A)
	_assert_play()
	assert_false(Input.is_action_pressed("ui_accept"))
	assert_false(Input.is_action_pressed("dash"), "menu A release must not leave dash held")


func test_start_pause_resume_restart_and_return_to_shore_use_real_menu_callbacks() -> void:
	await _tap(JOY_BUTTON_A)
	_assert_play()
	await _tap(JOY_BUTTON_START)
	assert_eq(game.state, "paused")
	if not _focus("RESUME"):
		return
	assert_false(Input.is_action_pressed("pause_run"), "Start release clears pause action")
	game._process(0.0)
	assert_eq(game.state, "paused", "released Start must not resume on a later frame")
	await _tap(JOY_BUTTON_START)
	_assert_play()
	await _tap(JOY_BUTTON_START)
	await _tap(JOY_BUTTON_DPAD_DOWN)
	if not _focus("RESTART"):
		return
	game.keeper.hp = 2
	game.embers = 19
	await _tap(JOY_BUTTON_A)
	_assert_play()
	assert_eq(game.keeper.hp, 5)
	assert_eq(game.embers, 0)
	assert_eq(game.room, 0)
	assert_eq(game.doors.size(), 3)
	await _tap(JOY_BUTTON_START)
	await _tap(JOY_BUTTON_DPAD_DOWN)
	await _tap(JOY_BUTTON_DPAD_DOWN)
	if not _focus("RETURN TO SHORE"):
		return
	await _tap(JOY_BUTTON_A)
	assert_eq(game.state, "title")
	assert_true(game.ui.overlay.visible)
	assert_false(game.keeper.visible)
	assert_false(game.veil.visible)
	assert_true(game.ui.hud.text.is_empty())
	assert_true(game.doors.is_empty())
	_focus("BEGIN THE VIGIL")


func test_left_stick_moves_in_each_signed_direction_and_release_stops_motion(
	case = use_parameters(
		[
			[JOY_AXIS_LEFT_X, -1.0, Vector2.LEFT],
			[JOY_AXIS_LEFT_X, 1.0, Vector2.RIGHT],
			[JOY_AXIS_LEFT_Y, -1.0, Vector2.UP],
			[JOY_AXIS_LEFT_Y, 1.0, Vector2.DOWN],
		]
	)
) -> void:
	game._start_run()
	var origin: Vector2 = game.keeper.position
	_axis(case[0], case[1])
	game._process(1.0 / 60.0)
	var moved: Vector2 = game.keeper.position - origin
	assert_almost_eq(moved, case[2] * VigilKeeper.SPEED / 60.0, Vector2.ONE * 0.001)
	assert_true(game.bolts.is_empty(), "left stick alone does not aim")
	_axis(case[0], 0.0)
	assert_eq(Input.get_vector("move_left", "move_right", "move_up", "move_down"), Vector2.ZERO)
	var stopped: Vector2 = game.keeper.position
	game._process(1.0 / 60.0)
	assert_eq(game.keeper.position, stopped, "neutral left stick stops real keeper movement")


func test_gameplay_a_and_right_shoulder_dash_and_release_the_shared_action(
	button = use_parameters([JOY_BUTTON_A, JOY_BUTTON_RIGHT_SHOULDER])
) -> void:
	game._start_run()
	var origin: Vector2 = game.keeper.position
	await _tap(button)
	assert_gt(game.keeper.dash_left, 0.0)
	assert_gt(game.keeper.dash_cooldown, 0.0)
	assert_false(Input.is_action_pressed("dash"), "the released controller button is neutral")
	game._process(1.0 / 60.0)
	assert_almost_eq(
		game.keeper.position - origin,
		Vector2.UP * VigilKeeper.DASH_SPEED / 60.0,
		Vector2.ONE * 0.001
	)
	assert_eq(game.keeper.dash_direction, Vector2.UP)


func test_right_stick_fires_real_bolts_in_each_signed_direction_and_release_stops_fire(
	case = use_parameters(
		[
			[JOY_AXIS_RIGHT_X, -1.0, Vector2.LEFT],
			[JOY_AXIS_RIGHT_X, 1.0, Vector2.RIGHT],
			[JOY_AXIS_RIGHT_Y, -1.0, Vector2.UP],
			[JOY_AXIS_RIGHT_Y, 1.0, Vector2.DOWN],
		]
	)
) -> void:
	game._start_run()
	var origin: Vector2 = game.keeper.position
	_axis(case[0], case[1])
	game._process(1.0 / 60.0)
	assert_eq(game.keeper.position, origin, "right stick alone does not move")
	assert_eq(game.bolts.size(), 1, "the real keeper signal creates a real scene bolt")
	if game.bolts.size() != 1:
		return
	assert_false(game.bolts[0].hostile)
	assert_eq(game.bolts[0].direction, case[2])
	_axis(case[0], 0.0)
	assert_eq(Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down"), Vector2.ZERO)
	# Enough deterministic time for the fire cooldown, without moving the existing bolt away.
	game.keeper.step(game.keeper.fire_interval + 0.01)
	assert_eq(game.bolts.size(), 1, "neutral right stick must not emit another bolt")


func test_sub_deadzone_sticks_do_not_move_or_fire(
	axis = use_parameters([JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y])
) -> void:
	game._start_run()
	var origin: Vector2 = game.keeper.position
	for value in [-0.21, 0.21]:
		_axis(axis, value)
		game._process(1.0 / 60.0)
		assert_eq(game.keeper.position, origin)
		assert_true(game.bolts.is_empty())
	_axis(axis, 0.0)


func _axis(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	snapshot.inject(event, viewport)


func _tap(button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	snapshot.inject(event, viewport)
	game._process(0.0)
	await _frames()
	event.pressed = false
	snapshot.inject(event, viewport)
	await _frames()


func _frames() -> void:
	for _frame in 3:
		await get_tree().process_frame


func _focus(label: String) -> bool:
	var focused := viewport.gui_get_focus_owner() as Button
	assert_not_null(focused, "expected focused button " + label)
	if focused == null:
		return false
	assert_true(focused.is_visible_in_tree())
	assert_false(focused.disabled)
	assert_true(game.ui.panel.is_ancestor_of(focused))
	assert_eq(focused.text, label)
	return focused.text == label


func _assert_play() -> void:
	assert_eq(game.state, "play")
	assert_false(game.ui.overlay.visible)
	assert_null(viewport.gui_get_focus_owner(), "hidden overlay releases GUI focus")
