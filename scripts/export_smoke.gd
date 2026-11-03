extends Node
## Opt-in acceptance driver: exercise the exported game's actual menu callbacks.

const FRAME_LIMIT := 240
var frames := 0
var game: Node2D
var failed := false


func _ready() -> void:
	game = get_parent()
	_run.call_deferred()


func _process(_delta: float) -> void:
	frames += 1
	if frames > FRAME_LIMIT:
		_fail("menu traversal exceeded %d frames" % FRAME_LIMIT)


# Each failed observation ends the traversal immediately.
# gdlint: disable=max-returns
func _run() -> void:
	await _settle()
	if not _title() or not _press("CONTROLS & THE LANTERN"):
		return
	await _settle()
	if not _expect("title", "CARRY THE LIGHT", true) or not _press("BACK TO THE SHORE"):
		return
	await _settle()
	if not _title() or not _press("BEGIN THE VIGIL"):
		return
	await _settle()
	if not _play() or not await _pause():
		return
	if not _press("RESUME"):
		return
	await _settle()
	if not _play() or not await _pause():
		return
	if not _press("RESTART"):
		return
	await _settle()
	if not _play() or not await _pause():
		return
	if not _press("RETURN TO SHORE"):
		return
	await _settle()
	if not _title() or not _press("QUIT"):
		return
	# Quit's real callback has run synchronously; SceneTree exits after this frame.
	print("EXPORT SMOKE: passed")


func _settle() -> void:
	for _frame in 3:
		await get_tree().process_frame


func _pause() -> bool:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	Input.parse_input_event(event)
	await _settle()
	event = InputEventKey.new()
	event.physical_keycode = KEY_ESCAPE
	Input.parse_input_event(event)
	await _settle()
	return _expect("paused", "THE VIGIL WAITS", true)


func _title() -> bool:
	if not _expect("title", "LOWTIDE VIGIL", true):
		return false
	if game.keeper.visible or game.veil.visible or not game.ui.hud.text.is_empty():
		return _fail("shore must hide the keeper, veil and HUD")
	if not game.foes.is_empty() or not game.bolts.is_empty() or not game.doors.is_empty():
		return _fail("shore retained room entities")
	return true


func _play() -> bool:
	if not _expect("play", "", false):
		return false
	if not game.keeper.visible or not game.veil.visible or game.ui.hud.text.is_empty():
		return _fail("play must show the keeper, veil and HUD")
	if game.room != 0 or game.keeper.hp != 5 or game.embers != 0 or game.doors.size() != 3:
		return _fail("begin/restart did not create a fresh run")
	return true


func _expect(state: String, heading: String, panel_visible: bool) -> bool:
	if game.state != state or game.ui.overlay.visible != panel_visible:
		return _fail(
			"expected %s with panel visible=%s, got %s" % [state, panel_visible, game.state]
		)
	if panel_visible and game.ui.panel.get_child(0).text != heading:
		return _fail("expected panel " + heading)
	return true


func _press(label: String) -> bool:
	for child in game.ui.panel.get_children():
		if child is Button and child.text == label:
			if child.disabled or not child.is_visible_in_tree():
				return _fail("unavailable button " + label)
			child.pressed.emit()
			return true
	return _fail("missing button " + label)


func _fail(message: String) -> bool:
	if not failed:
		failed = true
		push_error("EXPORT SMOKE: " + message)
		get_tree().quit(1)
	return false
