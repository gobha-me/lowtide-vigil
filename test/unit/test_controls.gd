extends GutTest
## The single-call native keyboard, mouse, and controller action contract.

const BINDINGS := {
	"move_left": ["key:%d:0" % KEY_A, "axis:%d:-1.0" % JOY_AXIS_LEFT_X],
	"move_right": ["key:%d:0" % KEY_D, "axis:%d:1.0" % JOY_AXIS_LEFT_X],
	"move_up": ["key:%d:0" % KEY_W, "axis:%d:-1.0" % JOY_AXIS_LEFT_Y],
	"move_down": ["key:%d:0" % KEY_S, "axis:%d:1.0" % JOY_AXIS_LEFT_Y],
	"aim_left": ["key:%d:0" % KEY_LEFT, "axis:%d:-1.0" % JOY_AXIS_RIGHT_X],
	"aim_right": ["key:%d:0" % KEY_RIGHT, "axis:%d:1.0" % JOY_AXIS_RIGHT_X],
	"aim_up": ["key:%d:0" % KEY_UP, "axis:%d:-1.0" % JOY_AXIS_RIGHT_Y],
	"aim_down": ["key:%d:0" % KEY_DOWN, "axis:%d:1.0" % JOY_AXIS_RIGHT_Y],
	"dash":
	[
		"key:%d:0" % KEY_SPACE,
		"key:%d:0" % KEY_SHIFT,
		"button:%d" % JOY_BUTTON_A,
		"button:%d" % JOY_BUTTON_RIGHT_SHOULDER,
		"mouse:%d" % MOUSE_BUTTON_RIGHT,
	],
	"pause_run": ["key:%d:0" % KEY_ESCAPE, "key:%d:0" % KEY_P, "button:%d" % JOY_BUTTON_START],
	"toggle_fullscreen": ["key:%d:0" % KEY_F11],
}

var _saved_actions: Dictionary = {}


func before_each() -> void:
	_saved_actions.clear()
	for action: String in BINDINGS:
		if InputMap.has_action(action):
			_saved_actions[action] = {
				"deadzone": InputMap.action_get_deadzone(action),
				"events": InputMap.action_get_events(action),
			}
			InputMap.erase_action(action)
	# Only one configure call: re-entry behaviour belongs to the separate fix issue.
	VigilControls.configure()


func after_each() -> void:
	for action: String in BINDINGS:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
		if _saved_actions.has(action):
			InputMap.add_action(action, _saved_actions[action].deadzone)
			for event: InputEvent in _saved_actions[action].events:
				InputMap.action_add_event(action, event)
	_saved_actions.clear()


func _signatures(action: String) -> Array[String]:
	var signatures: Array[String] = []
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			signatures.append("key:%d:%d" % [event.physical_keycode, event.keycode])
		elif event is InputEventJoypadMotion:
			signatures.append("axis:%d:%.1f" % [event.axis, event.axis_value])
		elif event is InputEventJoypadButton:
			signatures.append("button:%d" % event.button_index)
		elif event is InputEventMouseButton:
			signatures.append("mouse:%d" % event.button_index)
		else:
			signatures.append("unexpected:" + event.get_class())
	signatures.sort()
	return signatures


func test_managed_action_has_exact_bindings_and_deadzone(action = use_parameters(BINDINGS.keys())):
	assert_true(InputMap.has_action(action), "missing managed action: " + action)
	if not InputMap.has_action(action):
		return
	assert_almost_eq(InputMap.action_get_deadzone(action), 0.22, 0.0001, action)
	var expected: Array = BINDINGS[action].duplicate()
	expected.sort()
	assert_eq(_signatures(action), expected, "missing, extra, or wrong binding for " + action)
