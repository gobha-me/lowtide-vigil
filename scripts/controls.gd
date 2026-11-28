class_name VigilControls
extends RefCounted
## Input bindings live here so keyboard and controller follow the same actions.


static func configure() -> void:
	bind_keys("move_left", [KEY_A])
	bind_keys("move_right", [KEY_D])
	bind_keys("move_up", [KEY_W])
	bind_keys("move_down", [KEY_S])
	bind_keys("aim_left", [KEY_LEFT])
	bind_keys("aim_right", [KEY_RIGHT])
	bind_keys("aim_up", [KEY_UP])
	bind_keys("aim_down", [KEY_DOWN])
	bind_keys("dash", [KEY_SPACE, KEY_SHIFT])
	bind_keys("pause_run", [KEY_ESCAPE, KEY_P])
	bind_keys("toggle_fullscreen", [KEY_F11])
	bind_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	bind_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	bind_axis("move_up", JOY_AXIS_LEFT_Y, -1.0)
	bind_axis("move_down", JOY_AXIS_LEFT_Y, 1.0)
	bind_axis("aim_left", JOY_AXIS_RIGHT_X, -1.0)
	bind_axis("aim_right", JOY_AXIS_RIGHT_X, 1.0)
	bind_axis("aim_up", JOY_AXIS_RIGHT_Y, -1.0)
	bind_axis("aim_down", JOY_AXIS_RIGHT_Y, 1.0)
	bind_button("dash", JOY_BUTTON_A)
	bind_button("dash", JOY_BUTTON_RIGHT_SHOULDER)
	bind_button("pause_run", JOY_BUTTON_START)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_RIGHT
	InputMap.action_add_event("dash", mouse)


static func bind_keys(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.22)
	else:
		InputMap.action_erase_events(action)
		InputMap.action_set_deadzone(action, 0.22)
	for key: int in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)


static func bind_axis(action: String, axis: int, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	InputMap.action_add_event(action, event)


static func bind_button(action: String, button: int) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)
