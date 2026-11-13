extends GutTest
## Re-entry rebuilds native bindings while preserving actions owned by other systems.

const VIGIL = preload("res://scenes/vigil.tscn")
const UNRELATED := "lowtide_test_controls_unrelated"
const BINDINGS := {
	"move_left":
	[["key", KEY_A, 0, 0, false, false, false, false], ["axis", JOY_AXIS_LEFT_X, -1.0, 0]],
	"move_right":
	[["key", KEY_D, 0, 0, false, false, false, false], ["axis", JOY_AXIS_LEFT_X, 1.0, 0]],
	"move_up":
	[["key", KEY_W, 0, 0, false, false, false, false], ["axis", JOY_AXIS_LEFT_Y, -1.0, 0]],
	"move_down":
	[["key", KEY_S, 0, 0, false, false, false, false], ["axis", JOY_AXIS_LEFT_Y, 1.0, 0]],
	"aim_left":
	[["key", KEY_LEFT, 0, 0, false, false, false, false], ["axis", JOY_AXIS_RIGHT_X, -1.0, 0]],
	"aim_right":
	[["key", KEY_RIGHT, 0, 0, false, false, false, false], ["axis", JOY_AXIS_RIGHT_X, 1.0, 0]],
	"aim_up":
	[["key", KEY_UP, 0, 0, false, false, false, false], ["axis", JOY_AXIS_RIGHT_Y, -1.0, 0]],
	"aim_down":
	[["key", KEY_DOWN, 0, 0, false, false, false, false], ["axis", JOY_AXIS_RIGHT_Y, 1.0, 0]],
	"dash":
	[
		["key", KEY_SPACE, 0, 0, false, false, false, false],
		["key", KEY_SHIFT, 0, 0, false, false, false, false],
		["button", JOY_BUTTON_A, 0],
		["button", JOY_BUTTON_RIGHT_SHOULDER, 0],
		["mouse", MOUSE_BUTTON_RIGHT, 0, false, false, false, false],
	],
	"pause_run":
	[
		["key", KEY_ESCAPE, 0, 0, false, false, false, false],
		["key", KEY_P, 0, 0, false, false, false, false],
		["button", JOY_BUTTON_START, 0],
	],
	"toggle_fullscreen": [["key", KEY_F11, 0, 0, false, false, false, false]],
}

var _saved_actions: Dictionary = {}


func before_each() -> void:
	_saved_actions.clear()
	for action: String in BINDINGS.keys() + [UNRELATED]:
		if InputMap.has_action(action):
			_saved_actions[action] = {
				"deadzone": InputMap.action_get_deadzone(action),
				"events": InputMap.action_get_events(action),
			}
			InputMap.erase_action(action)


func after_each() -> void:
	for action: String in BINDINGS.keys() + [UNRELATED]:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
		if _saved_actions.has(action):
			InputMap.add_action(action, _saved_actions[action].deadzone)
			for event: InputEvent in _saved_actions[action].events:
				InputMap.action_add_event(action, event)
	_saved_actions.clear()


func _sorted(bindings: Array) -> Array:
	var result := bindings.duplicate(true)
	result.sort_custom(func(a: Array, b: Array) -> bool: return str(a) < str(b))
	return result


func _bindings(action: String) -> Array:
	var bindings := []
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			(
				bindings
				. append(
					[
						"key",
						event.physical_keycode,
						event.keycode,
						event.device,
						event.alt_pressed,
						event.shift_pressed,
						event.ctrl_pressed,
						event.meta_pressed,
					]
				)
			)
		elif event is InputEventJoypadMotion:
			bindings.append(["axis", event.axis, event.axis_value, event.device])
		elif event is InputEventJoypadButton:
			bindings.append(["button", event.button_index, event.device])
		elif event is InputEventMouseButton:
			(
				bindings
				. append(
					[
						"mouse",
						event.button_index,
						event.device,
						event.alt_pressed,
						event.shift_pressed,
						event.ctrl_pressed,
						event.meta_pressed,
					]
				)
			)
		else:
			bindings.append(["unexpected", event.get_class()])
	return _sorted(bindings)


func _canonical_bindings(action: String) -> Array:
	var bindings: Array = BINDINGS[action].duplicate(true)
	# Keyboard and mouse use Godot's native default devices, not controller device 0.
	var key_device := InputEventKey.new().device
	var mouse_device := InputEventMouseButton.new().device
	for binding: Array in bindings:
		if binding[0] == "key":
			binding[3] = key_device
		elif binding[0] == "mouse":
			binding[2] = mouse_device
	return _sorted(bindings)


func _assert_canonical(action: String) -> void:
	assert_true(InputMap.has_action(action), "missing managed action: " + action)
	if not InputMap.has_action(action):
		return
	assert_almost_eq(InputMap.action_get_deadzone(action), 0.22, 0.0001, action)
	assert_eq(
		_bindings(action), _canonical_bindings(action), "exact binding identities/count: " + action
	)


func _seed_stale(action: String, deadzone: float) -> void:
	InputMap.action_set_deadzone(action, deadzone)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_Q
	key.shift_pressed = true
	key.device = 7
	InputMap.action_add_event(action, key)
	var axis := InputEventJoypadMotion.new()
	axis.axis = JOY_AXIS_TRIGGER_LEFT
	axis.axis_value = 0.42
	axis.device = 3
	InputMap.action_add_event(action, axis)
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_X
	button.device = 2
	InputMap.action_add_event(action, button)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_MIDDLE
	mouse.ctrl_pressed = true
	mouse.device = 5
	InputMap.action_add_event(action, mouse)


func _add_unrelated_action() -> Array[InputEvent]:
	InputMap.add_action(UNRELATED, 0.73)
	_seed_stale(UNRELATED, 0.73)
	return InputMap.action_get_events(UNRELATED)


func test_reentry_replaces_stale_events_and_boundary_deadzones_for_every_action(
	action = use_parameters(BINDINGS.keys())
) -> void:
	VigilControls.configure()
	if not InputMap.has_action(action):
		fail_test("initial configure omitted " + action)
		return
	_seed_stale(action, 0.0 if action.begins_with("aim_") else 1.0)
	for _iteration in 3:
		VigilControls.configure()
		_assert_canonical(action)


func test_repeated_configure_keeps_exact_action_names_and_all_canonical_bindings() -> void:
	VigilControls.configure()
	var names := InputMap.get_actions()
	names.sort()
	for _iteration in 4:
		VigilControls.configure()
	var actual_names := InputMap.get_actions()
	actual_names.sort()
	assert_eq(actual_names, names, "re-entry must not introduce actions")
	for action: String in BINDINGS:
		_assert_canonical(action)


func test_repeated_configure_preserves_unrelated_event_objects_and_deadzone() -> void:
	var events := _add_unrelated_action()
	var bindings := _bindings(UNRELATED)
	for _iteration in 4:
		VigilControls.configure()
	assert_true(InputMap.has_action(UNRELATED))
	if not InputMap.has_action(UNRELATED):
		return
	assert_almost_eq(InputMap.action_get_deadzone(UNRELATED), 0.73, 0.0001)
	assert_eq(_bindings(UNRELATED), bindings)
	assert_eq(InputMap.action_get_events(UNRELATED), events, "unrelated event objects survive")


func test_real_scene_reentry_repairs_every_action_and_keeps_unrelated_bindings() -> void:
	var unrelated := _add_unrelated_action()
	var first: Node2D = VIGIL.instantiate()
	add_child(first)
	first.set_process(false)
	var names := InputMap.get_actions()
	names.sort()
	for action: String in BINDINGS:
		_seed_stale(action, 1.0)
	first.queue_free()
	await get_tree().process_frame
	var second: Node2D = VIGIL.instantiate()
	add_child_autoqfree(second)
	second.set_process(false)
	for action: String in BINDINGS:
		_assert_canonical(action)
	var actual_names := InputMap.get_actions()
	actual_names.sort()
	assert_eq(actual_names, names)
	assert_almost_eq(InputMap.action_get_deadzone(UNRELATED), 0.73, 0.0001)
	assert_eq(InputMap.action_get_events(UNRELATED), unrelated)
