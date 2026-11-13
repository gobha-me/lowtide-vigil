extends GutTest
## Power-scaled Kindles retain ordinary rewards and strengthen the real ORDEAL path.

const VIGIL = preload("res://scenes/vigil.tscn")


func _game() -> Node2D:
	var game: Node2D = VIGIL.instantiate()
	add_child_autoqfree(game)
	game.set_process(false)
	game._start_run()
	game._clear_room()
	return game


func _kindle(game: Node2D, kindle_name: String) -> Dictionary:
	for kindle: Dictionary in game.KINDLES:
		if kindle.name == kindle_name:
			return kindle
	fail_test("missing Kindle: " + kindle_name)
	return {}


func test_twin_normal_and_ordeal_stack_from_identical_initial_damage() -> void:
	var normal := _game()
	var ordeal := _game()
	normal.keeper.damage = 2.4
	ordeal.keeper.damage = 2.4
	var twin := _kindle(normal, "Twin Wick")
	normal._apply_kindle(twin, 1.0)
	ordeal._apply_kindle(twin, 1.5)
	assert_true(normal.keeper.twin_wick)
	assert_true(ordeal.keeper.twin_wick)
	assert_almost_eq(normal.keeper.damage, 2.4, 0.0001)
	assert_almost_eq(ordeal.keeper.damage, 2.7, 0.0001)
	assert_gt(ordeal.keeper.damage, normal.keeper.damage)
	normal._apply_kindle(twin, 1.0)
	ordeal._apply_kindle(twin, 1.5)
	assert_almost_eq(normal.keeper.damage, 3.0, 0.0001)
	assert_almost_eq(ordeal.keeper.damage, 3.7125, 0.0001)
	normal._apply_kindle(twin, 1.0)
	ordeal._apply_kindle(twin, 1.5)
	assert_almost_eq(normal.keeper.damage, 3.75, 0.0001)
	assert_almost_eq(ordeal.keeper.damage, 5.1046875, 0.0001)


func test_first_twin_only_adds_damage_above_baseline_power(
	case = use_parameters([[0.0, 2.4], [0.5, 2.4], [1.0, 2.4], [1.01, 2.406], [1.25, 2.55]])
) -> void:
	var game := _game()
	game.keeper.damage = 2.4
	game._apply_kindle(_kindle(game, "Twin Wick"), case[0])
	assert_true(game.keeper.twin_wick)
	assert_almost_eq(game.keeper.damage, case[1], 0.0001)


func test_spare_wick_preserves_missing_health_and_ordeal_adds_two(
	starting_hp = use_parameters([1, 5])
) -> void:
	var normal := _game()
	var ordeal := _game()
	normal.keeper.hp = starting_hp
	ordeal.keeper.hp = starting_hp
	var spare := _kindle(normal, "Spare Wick")
	normal._apply_kindle(spare, 1.0)
	ordeal._apply_kindle(spare, 1.5)
	assert_eq(normal.keeper.max_hp, 6)
	assert_eq(normal.keeper.hp, starting_hp + 1)
	assert_eq(ordeal.keeper.max_hp, 7)
	assert_eq(ordeal.keeper.hp, starting_hp + 2)
	assert_eq(normal.keeper.max_hp - normal.keeper.hp, 5 - starting_hp)
	assert_eq(ordeal.keeper.max_hp - ordeal.keeper.hp, 5 - starting_hp)
	normal._apply_kindle(spare, 1.0)
	ordeal._apply_kindle(spare, 1.5)
	assert_eq(normal.keeper.max_hp, 7)
	assert_eq(normal.keeper.hp, starting_hp + 2)
	assert_eq(ordeal.keeper.max_hp, 9)
	assert_eq(ordeal.keeper.hp, starting_hp + 4)


func test_phoenix_normal_and_ordeal_amounts_and_caps(
	case = use_parameters([[1, 4, 6], [10, 12, 12], [12, 12, 12]])
) -> void:
	var normal := _game()
	var ordeal := _game()
	for game: Node2D in [normal, ordeal]:
		game.keeper.max_hp = 12
		game.keeper.hp = case[0]
	var phoenix := _kindle(normal, "Phoenix Ash")
	normal._apply_kindle(phoenix, 1.0)
	ordeal._apply_kindle(phoenix, 1.5)
	assert_eq(normal.keeper.hp, case[1])
	assert_eq(ordeal.keeper.hp, case[2])
	assert_eq(normal.keeper.max_hp, 12)
	assert_eq(ordeal.keeper.max_hp, 12)


func test_fractional_flame_power_rounds_up(
	case = use_parameters(
		[
			[0.0, 0, 0],
			[0.01, 1, 1],
			[0.5, 1, 2],
			[1.0, 1, 3],
			[1.01, 2, 4],
			[1.5, 2, 5],
			[2.01, 3, 7],
		]
	)
) -> void:
	var game := _game()
	game.keeper.max_hp = 20
	game.keeper.hp = 1
	game._apply_kindle(_kindle(game, "Spare Wick"), case[0])
	assert_eq(game.keeper.max_hp, 20 + case[1])
	assert_eq(game.keeper.hp, 1 + case[1])
	game._apply_kindle(_kindle(game, "Phoenix Ash"), case[0])
	assert_eq(game.keeper.max_hp, 20 + case[1])
	assert_eq(game.keeper.hp, 1 + case[1] + case[2])


func test_reward_and_shop_paths_forward_the_right_power(
	case = use_parameters(
		[
			["Twin Wick", "KINDLE", false, 2.4, 12, 1],
			["Twin Wick", "ORDEAL", false, 2.7, 12, 1],
			["Twin Wick", "SHOP", false, 2.4, 12, 1],
			["Twin Wick", "KINDLE", true, 3.0, 12, 1],
			["Twin Wick", "ORDEAL", true, 3.3, 12, 1],
			["Twin Wick", "SHOP", true, 3.0, 12, 1],
			["Spare Wick", "KINDLE", false, 2.4, 13, 2],
			["Spare Wick", "ORDEAL", false, 2.4, 14, 3],
			["Spare Wick", "SHOP", false, 2.4, 13, 2],
			["Phoenix Ash", "KINDLE", false, 2.4, 12, 4],
			["Phoenix Ash", "ORDEAL", false, 2.4, 12, 6],
			["Phoenix Ash", "SHOP", false, 2.4, 12, 4],
		]
	)
) -> void:
	var game := _game()
	if case[1] == "SHOP":
		game._enter_room("SHOP")
		game.embers = 40
	else:
		game.reward = case[1]
	game.keeper.damage = 2.4
	game.keeper.max_hp = 12
	game.keeper.hp = 1
	game.keeper.twin_wick = case[2]
	var kindle := _kindle(game, case[0])
	if case[1] == "SHOP":
		game._buy_kindle(kindle)
		assert_true(game.shop_bought)
		assert_eq(game.embers, 22)
	else:
		game._take_kindle(kindle)
		assert_eq(game.state, "play")
	assert_eq(game.upgrades, [case[0]])
	assert_almost_eq(game.keeper.damage, case[3], 0.0001)
	assert_eq(game.keeper.max_hp, case[4])
	assert_eq(game.keeper.hp, case[5])
	assert_eq(game.keeper.twin_wick, case[0] == "Twin Wick")


func test_existing_power_scaled_kindles_keep_their_numbers(
	case = use_parameters([[1.0, 1.35, 0.1875, 0.6375], [1.5, 1.525, 0.15625, 0.53125]])
) -> void:
	var game := _game()
	game._apply_kindle(_kindle(game, "Wick"), case[0])
	game._apply_kindle(_kindle(game, "Bellows"), case[0])
	game._apply_kindle(_kindle(game, "Light Step"), case[0])
	assert_almost_eq(game.keeper.damage, case[1], 0.0001)
	assert_almost_eq(game.keeper.fire_interval, case[2], 0.0001)
	assert_almost_eq(game.keeper.max_dash_cooldown, case[3], 0.0001)


func test_restart_resets_powered_reward_state() -> void:
	var game := _game()
	game.keeper.hp = 1
	for kindle_name: String in ["Twin Wick", "Spare Wick", "Phoenix Ash"]:
		game.reward = "ORDEAL"
		game._take_kindle(_kindle(game, kindle_name))
	assert_true(game.keeper.twin_wick)
	assert_almost_eq(game.keeper.damage, 1.125, 0.0001)
	assert_eq(game.keeper.max_hp, 7)
	assert_eq(game.keeper.hp, 7)
	game._start_run()
	assert_false(game.keeper.twin_wick)
	assert_eq(game.keeper.damage, 1.0)
	assert_eq(game.keeper.max_hp, 5)
	assert_eq(game.keeper.hp, 5)
	assert_eq(game.keeper.fire_interval, 0.25)
	assert_eq(game.keeper.max_dash_cooldown, VigilKeeper.DASH_COOLDOWN)
	assert_eq(game.upgrades, [])
