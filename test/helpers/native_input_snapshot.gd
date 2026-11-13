extends RefCounted
## Restore the runner's complete action map and every native input touched by a test.

var _actions: Dictionary = {}
var _native: Dictionary = {}
var _accumulated := true


func capture() -> void:
	_accumulated = Input.use_accumulated_input
	Input.flush_buffered_events()
	for action in InputMap.get_actions():
		_actions[action] = {
			"deadzone": InputMap.action_get_deadzone(action),
			"events": InputMap.action_get_events(action).duplicate(true),
			"pressed": Input.is_action_pressed(action),
			"strength": Input.get_action_strength(action),
		}
		Input.action_release(action)
	Input.use_accumulated_input = false


func inject(event: InputEvent, viewport: Viewport = null) -> void:
	_remember_native(event)
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	if viewport != null:
		# push_input dispatches GUI events; parse_input_event updates Input's polled state.
		viewport.push_input(event, true)


func restore() -> void:
	# Release using the test's map first, then reinstall the map present at capture.
	for original: InputEvent in _native.values():
		var release := original.duplicate() as InputEvent
		if release is InputEventJoypadMotion:
			release.axis_value = 0.0
		else:
			release.set("pressed", false)
		Input.parse_input_event(release)
	Input.flush_buffered_events()
	for action in InputMap.get_actions():
		Input.action_release(action)
		InputMap.erase_action(action)
	for action: StringName in _actions:
		InputMap.add_action(action, _actions[action].deadzone)
		for event: InputEvent in _actions[action].events:
			InputMap.action_add_event(action, event)
	for original: InputEvent in _native.values():
		Input.parse_input_event(original)
	Input.flush_buffered_events()
	for action: StringName in _actions:
		Input.action_release(action)
		if _actions[action].pressed:
			Input.action_press(action, _actions[action].strength)
	Input.use_accumulated_input = _accumulated
	_actions.clear()
	_native.clear()


func _remember_native(event: InputEvent) -> void:
	var original := event.duplicate() as InputEvent
	var identity := ""
	if event is InputEventJoypadMotion:
		identity = "axis:%d:%d" % [event.device, event.axis]
		original.axis_value = Input.get_joy_axis(event.device, event.axis)
	elif event is InputEventJoypadButton:
		identity = "button:%d:%d" % [event.device, event.button_index]
		original.pressed = Input.is_joy_button_pressed(event.device, event.button_index)
	elif event is InputEventKey:
		identity = "key:%d:%d" % [event.keycode, event.physical_keycode]
		original.echo = false
		original.pressed = (
			Input.is_physical_key_pressed(event.physical_keycode)
			if event.physical_keycode != KEY_NONE
			else Input.is_key_pressed(event.keycode)
		)
	elif event is InputEventMouseButton:
		identity = "mouse:%d" % event.button_index
		original.pressed = Input.is_mouse_button_pressed(event.button_index)
	if not identity.is_empty() and not _native.has(identity):
		_native[identity] = original
