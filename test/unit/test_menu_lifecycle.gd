extends GutTest
## Real menu callbacks must reset a run and discard abandoned room entities.

const VIGIL = preload("res://scenes/vigil.tscn")


func _game() -> Node2D:
	var game: Node2D = VIGIL.instantiate()
	add_child_autoqfree(game)
	game.set_process(false)
	return game


func _press(game: Node2D, label: String) -> bool:
	for child in game.ui.panel.get_children():
		if child is Button and child.text == label:
			assert_false(child.disabled, label)
			assert_true(child.is_visible_in_tree(), label)
			if child.disabled or not child.is_visible_in_tree():
				return false
			child.pressed.emit()
			return true
	fail_test("missing button " + label)
	return false


func _begin() -> Node2D:
	var game := _game()
	_press(game, "BEGIN THE VIGIL")
	return game


func _assert_fresh(game: Node2D) -> void:
	assert_eq(game.state, "play")
	assert_false(game.ui.overlay.visible)
	assert_true(game.keeper.visible)
	assert_true(game.veil.visible)
	assert_eq(game.room, 0)
	assert_eq(game.embers, 0)
	assert_eq(game.kills, 0)
	assert_eq(game.reward, "")
	assert_eq(game.offered.size(), 0)
	assert_false(game.shop_bought)
	assert_eq(game.upgrades.size(), 0)
	assert_eq(game.room_time, 0.0)
	var keeper: VigilKeeper = game.keeper
	assert_eq(keeper.hp, 5)
	assert_eq(keeper.max_hp, 5)
	assert_eq(keeper.damage, 1.0)
	assert_eq(keeper.fire_interval, 0.25)
	assert_false(keeper.twin_wick)
	assert_eq(keeper.max_dash_cooldown, VigilKeeper.DASH_COOLDOWN)
	assert_eq(keeper.dash_left, 0.0)
	assert_eq(keeper.dash_cooldown, 0.0)
	assert_eq(keeper.invulnerable, 0.0)
	assert_eq(keeper.fire_cooldown, 0.0)
	assert_eq(keeper.facing, Vector2.UP)
	assert_eq(keeper.dash_direction, Vector2.UP)
	assert_eq(keeper.walking_time, 0.0)
	assert_eq(keeper.position, Vector2(640, 560))
	assert_eq(game.foes.size(), 0)
	assert_eq(game.bolts.size(), 0)
	var rewards := []
	for door in game.doors:
		rewards.append(door.reward)
	assert_eq(rewards, ["KINDLE", "EMBERS", "ORDEAL"])
	assert_string_contains(game.ui.hud.text, "DESCENT 0 / 5")
	assert_string_contains(game.ui.hud.text, "EMBERS  0")
	assert_string_contains(game.ui.hud.text, "* * * * * ")


func test_normal_startup_has_no_opt_in_smoke_node_and_controls_return_to_title() -> void:
	assert_false("--smoke" in OS.get_cmdline_user_args())
	var game := _game()
	assert_eq(game.state, "title")
	for child in game.get_children():
		var script: Script = child.get_script()
		if script != null:
			assert_ne(script.resource_path, "res://scripts/export_smoke.gd")
	assert_eq(game.ui.hud.text, "")
	assert_false(game.keeper.visible)
	assert_false(game.veil.visible)
	if not _press(game, "CONTROLS & THE LANTERN"):
		return
	assert_eq(game.ui.panel.get_child(0).text, "CARRY THE LIGHT")
	assert_string_contains(game.ui.panel.get_child(1).text, "F11")
	_press(game, "BACK TO THE SHORE")
	assert_eq(game.ui.panel.get_child(0).text, "LOWTIDE VIGIL")
	_press(game, "BEGIN THE VIGIL")
	_assert_fresh(game)
	await get_tree().process_frame


func test_pause_restart_resets_upgrades_keeper_and_every_transient() -> void:
	var game := _begin()
	game._enter_room("ORDEAL")
	game._open_doors()
	game._fire_hostile(Vector2(300, 300), Vector2.DOWN, 100.0)
	var old_nodes: Array = game.foes.duplicate() + game.bolts.duplicate() + game.doors.duplicate()
	game.room_time = 8.0
	game.embers = 85
	game.kills = 17
	game.offered = game.KINDLES.duplicate()
	game.shop_bought = true
	for kindle in game.KINDLES:
		game._apply_kindle(kindle)
	game.keeper.hp = 2
	game.keeper.facing = Vector2.RIGHT
	game.keeper.dash_direction = Vector2.LEFT
	game.keeper.walking_time = 9.0
	game.keeper.dash_left = 0.1
	game.keeper.dash_cooldown = 0.6
	game.keeper.invulnerable = 0.8
	game.keeper.fire_cooldown = 0.2
	game._pause_run()
	assert_eq(game.state, "paused")
	if not _press(game, "RESTART"):
		return
	_assert_fresh(game)
	for node in old_nodes:
		assert_true(node.is_queued_for_deletion())
	await get_tree().process_frame
	for node in old_nodes:
		assert_false(is_instance_valid(node))


func test_shore_clears_all_entities_from_pause_win_and_loss(
	ending = use_parameters(["paused", "won", "lost"])
) -> void:
	var game := _begin()
	game._spawn_foe("root", Vector2(200, 200))
	game._fire_hostile(Vector2(300, 300), Vector2.DOWN, 100.0)
	var old_nodes: Array = game.foes.duplicate() + game.bolts.duplicate() + game.doors.duplicate()
	match ending:
		"paused":
			game._pause_run()
		"won":
			game._win_run()
		"lost":
			game.keeper.hp = 1
			game.keeper.hurt()
	assert_eq(game.state, ending)
	if not _press(game, "RETURN TO SHORE"):
		return
	assert_eq(game.state, "title")
	assert_eq(game.foes.size(), 0)
	assert_eq(game.bolts.size(), 0)
	assert_eq(game.doors.size(), 0)
	assert_false(game.keeper.visible)
	assert_false(game.veil.visible)
	assert_eq(game.ui.hud.text, "")
	assert_true(game.ui.overlay.visible)
	assert_eq(game.ui.panel.get_child(0).text, "LOWTIDE VIGIL")
	for node in old_nodes:
		assert_true(node.is_queued_for_deletion())
	await get_tree().process_frame
	for node in old_nodes:
		assert_false(is_instance_valid(node))
	_press(game, "BEGIN THE VIGIL")
	_assert_fresh(game)


func _assert_changed_hud(game: Node2D) -> void:
	assert_string_contains(game.ui.hud.text, "DESCENT 3 / 5")
	assert_string_contains(game.ui.hud.text, "* * . . . ")
	assert_string_contains(game.ui.hud.text, "EMBERS  47")
	assert_string_contains(game.ui.hud.text, "DASH  0.6s")
	assert_string_contains(game.ui.hud.text, "Wick")


func _dirty_hud(game: Node2D) -> void:
	game.room = 3
	game.keeper.hp = 2
	game.keeper.dash_cooldown = 0.6
	game.embers = 47
	game.upgrades.assign(["Wick"])
	game.ui.hud.text = "stale HUD"


func test_hud_refreshes_synchronously_on_transitions(
	transition = use_parameters(["doors", "kindles", "shop", "pause", "resume", "win", "loss"])
) -> void:
	var game := _begin()
	if transition == "resume":
		game._pause_run()
	_dirty_hud(game)
	match transition:
		"doors":
			game._clear_room()
			game._open_doors()
		"kindles":
			game._show_kindles()
		"shop":
			game._show_shop()
		"pause":
			game._pause_run()
		"resume":
			_press(game, "RESUME")
		"win":
			game._win_run()
		"loss":
			game._lose_run()
	_assert_changed_hud(game)


func test_hud_tracks_each_shop_purchase_and_leave_without_a_gameplay_frame() -> void:
	var game := _begin()
	game.embers = 60
	game.keeper.hp = 1
	game._enter_room("SHOP")
	assert_string_contains(game.ui.hud.text, "EMBERS  60")
	assert_string_contains(game.ui.hud.text, "DESCENT 1 / 5")
	if not _press(game, "MEND TWO FLAMES  /  10 EMBERS"):
		return
	assert_eq(game.keeper.hp, 3)
	assert_eq(game.embers, 50)
	assert_string_contains(game.ui.hud.text, "* * * . . ")
	assert_string_contains(game.ui.hud.text, "EMBERS  50")
	var ware: Dictionary = game.offered[0]
	if not _press(game, ware.name + "  /  " + ware.description + "  /  18 EMBERS"):
		return
	assert_eq(game.embers, 32)
	assert_string_contains(game.ui.hud.text, "EMBERS  32")
	assert_string_contains(game.ui.hud.text, ware.name)
	assert_string_contains(game.ui.panel.get_child(1).text, "32 embers")
	assert_true(game.ui.panel.get_child(2).disabled)
	_press(game, "LEAVE THE CANDLEWRIGHT")
	assert_eq(game.state, "play")
	assert_false(game.ui.overlay.visible)
	assert_string_contains(game.ui.hud.text, "EMBERS  32")


func test_hud_keeps_refreshing_when_gameplay_is_stopped(
	screen = use_parameters(["paused", "reward", "shop", "won", "lost"])
) -> void:
	var game := _begin()
	match screen:
		"paused":
			game._pause_run()
		"reward":
			game._show_kindles()
		"shop":
			game._show_shop()
		"won":
			game._win_run()
		"lost":
			game._lose_run()
	_dirty_hud(game)
	game._process(0.0)
	_assert_changed_hud(game)
	assert_eq(game.state, screen)
	assert_true(game.ui.overlay.visible)


func test_fullscreen_f11_is_global_and_echo_release_and_other_keys_are_ignored(
	screen = use_parameters(
		["title", "controls", "play", "paused", "reward", "shop", "won", "lost"]
	)
) -> void:
	# A real isolated viewport exposes input handling even when headless cannot change mode.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 800)
	viewport.handle_input_locally = true
	add_child_autoqfree(viewport)
	var game: Node2D = VIGIL.instantiate()
	viewport.add_child(game)
	game.set_process(false)
	match screen:
		"controls":
			_press(game, "CONTROLS & THE LANTERN")
		"play", "paused", "reward", "shop", "won", "lost":
			_press(game, "BEGIN THE VIGIL")
			match screen:
				"paused":
					game._pause_run()
				"reward":
					game._show_kindles()
				"shop":
					game._show_shop()
				"won":
					game._win_run()
				"lost":
					game._lose_run()
	var original_state: String = game.state
	var original_mode := DisplayServer.window_get_mode()
	var event := InputEventKey.new()
	event.physical_keycode = KEY_F11
	event.pressed = true
	assert_true(event.is_action_pressed("toggle_fullscreen"), "F11 must be bound")
	viewport.push_input(event, true)
	assert_true(viewport.is_input_handled(), "F11 reaches the game's real global handler")
	var toggled_mode := DisplayServer.window_get_mode()
	if DisplayServer.get_name() != "headless":
		var expected := DisplayServer.WINDOW_MODE_FULLSCREEN
		if original_mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
			expected = DisplayServer.WINDOW_MODE_WINDOWED
		assert_eq(toggled_mode, expected)
	event.echo = true
	viewport.push_input(event, true)
	assert_false(viewport.is_input_handled(), "repeat must bypass the toggle handler")
	assert_eq(DisplayServer.window_get_mode(), toggled_mode)
	event.echo = false
	event.pressed = false
	viewport.push_input(event, true)
	assert_false(viewport.is_input_handled(), "key release must not toggle")
	assert_eq(DisplayServer.window_get_mode(), toggled_mode)
	event.physical_keycode = KEY_F10
	event.pressed = true
	viewport.push_input(event, true)
	assert_false(viewport.is_input_handled(), "unbound keys must not toggle")
	assert_eq(DisplayServer.window_get_mode(), toggled_mode)
	assert_eq(game.state, original_state)
	DisplayServer.window_set_mode(original_mode)


func test_final_combat_signal_updates_ending_hud_without_another_frame(
	ending = use_parameters(["won", "lost"])
) -> void:
	var game := _begin()
	game.embers = 19
	if ending == "won":
		game._enter_room("THE DROWNED TOLLING")
		var boss: VigilFoe = game.foes[0]
		boss.take_hit(boss.hp)
		assert_eq(game.embers, 22)
		assert_string_contains(game.ui.hud.text, "EMBERS  22")
		assert_string_contains(game.ui.hud.text, "DESCENT 1 / 5")
	else:
		game.keeper.hp = 1
		game.keeper.hurt()
		assert_eq(game.keeper.hp, 0)
		assert_string_contains(game.ui.hud.text, ". . . . . ")
		assert_string_contains(game.ui.hud.text, "EMBERS  19")
	assert_eq(game.state, ending)
	assert_true(game.ui.overlay.visible)
