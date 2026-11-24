extends GutTest
## One clean native configuration; configure re-entry belongs to separate coverage.

const Snapshot = preload("res://test/helpers/native_input_snapshot.gd")
const CONTRACT := {
	"move_left": [["key", KEY_A], ["axis", JOY_AXIS_LEFT_X, -1.0]],
	"move_right": [["key", KEY_D], ["axis", JOY_AXIS_LEFT_X, 1.0]],
	"move_up": [["key", KEY_W], ["axis", JOY_AXIS_LEFT_Y, -1.0]],
	"move_down": [["key", KEY_S], ["axis", JOY_AXIS_LEFT_Y, 1.0]],
	"aim_left": [["key", KEY_LEFT], ["axis", JOY_AXIS_RIGHT_X, -1.0]],
	"aim_right": [["key", KEY_RIGHT], ["axis", JOY_AXIS_RIGHT_X, 1.0]],
	"aim_up": [["key", KEY_UP], ["axis", JOY_AXIS_RIGHT_Y, -1.0]],
	"aim_down": [["key", KEY_DOWN], ["axis", JOY_AXIS_RIGHT_Y, 1.0]],
	"dash":
	[
		["key", KEY_SPACE],
		["key", KEY_SHIFT],
		["mouse", MOUSE_BUTTON_RIGHT],
		["button", JOY_BUTTON_A],
		["button", JOY_BUTTON_RIGHT_SHOULDER],
	],
	"pause_run": [["key", KEY_ESCAPE], ["key", KEY_P], ["button", JOY_BUTTON_START]],
	"toggle_fullscreen": [["key", KEY_F11]],
}

var snapshot: RefCounted
var unrelated_actions: Array[StringName]


func before_each() -> void:
	snapshot = Snapshot.new()
	snapshot.capture()
	for action: String in CONTRACT:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
	unrelated_actions = InputMap.get_actions()
	VigilControls.configure()


func after_each() -> void:
	snapshot.restore()


func test_native_action_names_and_deadzones_are_exact() -> void:
	var added: Array[String] = []
	for action in InputMap.get_actions():
		if action not in unrelated_actions:
			added.append(String(action))
	var expected: Array = CONTRACT.keys()
	added.sort()
	expected.sort()
	assert_eq(added, expected, "configure adds only the eleven native gameplay actions")
	for action: String in CONTRACT:
		assert_almost_eq(InputMap.action_get_deadzone(action), 0.22, 0.000001, action)


func test_each_native_action_has_only_its_physical_keys_buttons_or_signed_axes(
	action = use_parameters(CONTRACT.keys())
) -> void:
	var actual: Array = []
	for event in InputMap.action_get_events(action):
		assert_eq(event.device, 0, "default joypad device contract")
		if event is InputEventKey:
			assert_eq(event.keycode, KEY_NONE, "layout-independent physical bindings")
			assert_eq(event.unicode, 0)
			assert_false(event.shift_pressed or event.ctrl_pressed or event.alt_pressed)
			assert_false(event.meta_pressed or event.command_or_control_autoremap)
			actual.append(["key", event.physical_keycode])
		elif event is InputEventJoypadMotion:
			actual.append(["axis", event.axis, event.axis_value])
		elif event is InputEventJoypadButton:
			actual.append(["button", event.button_index])
		elif event is InputEventMouseButton:
			actual.append(["mouse", event.button_index])
		else:
			fail_test("unexpected native binding: " + event.get_class())
	assert_eq(actual.size(), CONTRACT[action].size(), action + " binding count")
	for binding: Array in CONTRACT[action]:
		assert_eq(actual.count(binding), 1, "%s requires exactly one %s" % [action, binding])
