extends GutTest
## Baseline Twin Wick, Light Step, and Spare Wick on the real scene and keeper.

const VIGIL = preload("res://scenes/vigil.tscn")


func after_each() -> void:
	Input.action_release("aim_right")


func _game() -> Node2D:
	var game: Node2D = VIGIL.instantiate()
	add_child_autoqfree(game)
	game.set_process(false)
	game._start_run()
	return game


func _kindle(game: Node2D, kindle_name: String) -> Dictionary:
	for kindle: Dictionary in game.KINDLES:
		if kindle.name == kindle_name:
			return kindle
	fail_test("missing Kindle: " + kindle_name)
	return {}


func test_first_twin_wick_fires_two_diverging_bolts_without_damage_bonus() -> void:
	var game := _game()
	game.keeper.damage = 2.4
	game._apply_kindle(_kindle(game, "Twin Wick"), 1.0)
	assert_true(game.keeper.twin_wick)
	assert_almost_eq(game.keeper.damage, 2.4, 0.0001)
	watch_signals(game.keeper)
	Input.action_press("aim_right")
	game.keeper.step(0.0)
	assert_signal_emit_count(game.keeper, "fired", 2)
	var origin: Vector2 = game.keeper.position + Vector2(22, 0)
	assert_signal_emitted_with_parameters(
		game.keeper, "fired", [origin, Vector2.RIGHT.rotated(-0.10)], 0
	)
	assert_signal_emitted_with_parameters(
		game.keeper, "fired", [origin, Vector2.RIGHT.rotated(0.10)], 1
	)
	assert_eq(game.bolts.size(), 2, "the scene receives both real keeper emissions")
	game.keeper.step(0.0)
	assert_signal_emit_count(game.keeper, "fired", 2, "cooldown prevents a second pair")
	game.keeper.step(game.keeper.fire_interval)
	Input.action_release("aim_right")
	assert_signal_emit_count(game.keeper, "fired", 4, "the next pair fires at exact cooldown")


func test_repeat_twin_wick_compounds_existing_damage_by_one_quarter() -> void:
	var game := _game()
	game.keeper.damage = 2.4
	var twin := _kindle(game, "Twin Wick")
	game._apply_kindle(twin, 1.0)
	game._apply_kindle(twin, 1.0)
	assert_almost_eq(game.keeper.damage, 3.0, 0.0001)
	game._apply_kindle(twin, 1.0)
	assert_almost_eq(game.keeper.damage, 3.75, 0.0001)
	assert_true(game.keeper.twin_wick, "repeat rewards must preserve twin firing")


func test_light_step_compounds_recovery_without_resetting_active_cooldown() -> void:
	var game := _game()
	game.keeper.dash_cooldown = 0.4
	var light_step := _kindle(game, "Light Step")
	game._apply_kindle(light_step, 1.0)
	assert_almost_eq(game.keeper.max_dash_cooldown, 0.6375, 0.0001)
	assert_eq(game.keeper.dash_cooldown, 0.4)
	game._apply_kindle(light_step, 1.0)
	assert_almost_eq(game.keeper.max_dash_cooldown, 0.478125, 0.0001)
	assert_eq(game.keeper.dash_cooldown, 0.4)


func test_spare_wick_adds_one_maximum_and_one_current_flame_when_wounded_or_full(
	starting_hp = use_parameters([1, 5])
) -> void:
	var game := _game()
	game.keeper.hp = starting_hp
	var spare := _kindle(game, "Spare Wick")
	game._apply_kindle(spare, 1.0)
	assert_eq(game.keeper.max_hp, 6)
	assert_eq(game.keeper.hp, starting_hp + 1, "Spare Wick does not refill missing flames")
	game._apply_kindle(spare, 1.0)
	assert_eq(game.keeper.max_hp, 7)
	assert_eq(game.keeper.hp, starting_hp + 2)
