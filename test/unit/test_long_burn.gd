extends GutTest
## Long Burn through real keeper shots, combat rewards, shop and run menus.

const VIGIL = preload("res://scenes/vigil.tscn")
const CENTER := Vector2(640, 400)


func _begin() -> Node2D:
	var game: Node2D = VIGIL.instantiate()
	add_child_autoqfree(game)
	game.set_process(false)
	_press(game, "BEGIN THE VIGIL")
	game.keeper.position = CENTER
	return game


func _button(game: Node2D, prefix: String) -> Button:
	for child in game.ui.panel.get_children():
		if child is Button and child.text.begins_with(prefix):
			return child
	fail_test("missing real button: " + prefix)
	return null


func _press(game: Node2D, prefix: String) -> bool:
	var button := _button(game, prefix)
	if button == null:
		return false
	assert_false(button.disabled, prefix)
	assert_true(button.is_visible_in_tree(), prefix)
	if button.disabled or not button.is_visible_in_tree():
		return false
	button.pressed.emit()
	return true


func _kindle(game: Node2D, label: String) -> Dictionary:
	for kindle: Dictionary in game.KINDLES:
		if kindle.name == label:
			return kindle
	fail_test("missing Kindle in native pool: " + label)
	return {}


func _long(game: Node2D, power: float = 1.0) -> bool:
	var kindle := _kindle(game, "Long Burn")
	if kindle.is_empty():
		return false
	game._apply_kindle(kindle, power)
	return true


func _shoot(game: Node2D) -> VigilBolt:
	game.keeper.fire_cooldown = 0.0
	Input.action_press("aim_right")
	game.keeper.step(0.0)
	Input.action_release("aim_right")
	return game.bolts.back()


func _assert_bolt(bolt: VigilBolt, speed: float, life: float, damage: float = 1.0) -> void:
	assert_false(bolt.hostile)
	assert_false(bolt.spent)
	assert_almost_eq(bolt.speed, speed, 0.0001)
	assert_almost_eq(bolt.lifetime, life, 0.0001)
	assert_almost_eq(bolt.damage, damage, 0.0001)


func _offer_seed(game: Node2D, shop: bool) -> bool:
	# Find a bounded deterministic seed, then let the real callback shuffle its own pool.
	# No replacement dictionaries, forced offers or mutated KINDLES are used.
	for candidate in range(64):
		seed(candidate)
		var pool: Array = game.KINDLES.duplicate()
		pool.shuffle()
		for index in range(1 if shop else 3):
			if pool[index].name == "Long Burn":
				seed(candidate)
				return true
	fail_test("Long Burn unavailable in 64 deterministic offer seeds")
	return false


func _clear_combat(game: Node2D) -> void:
	for foe: VigilFoe in game.foes.duplicate():
		foe.take_hit(foe.hp)


func _oscillate(game: Node2D, steps: int) -> void:
	# Keep real travel inside the unchanged arena so lifetime can expire independently.
	for index in steps:
		for bolt: VigilBolt in game.bolts:
			bolt.direction = Vector2.RIGHT if index % 2 == 0 else Vector2.LEFT
		game._step_bolts(0.05)


func test_unupgraded_keeper_fires_baseline_bolt() -> void:
	var game := _begin()
	var bolt := _shoot(game)
	assert_eq(game.bolts.size(), 1)
	_assert_bolt(bolt, 640.0, 2.4)
	assert_eq(bolt.position, Vector2(662, 400))
	assert_eq(bolt.direction, Vector2.RIGHT)
	assert_almost_eq(bolt.speed * bolt.lifetime, 1536.0, 0.001)


func test_normal_ordeal_and_mixed_stacks_have_additive_weighted_strength(
	sample = use_parameters(
		[
			{"powers": [1.0], "speed": 780.8, "life": 2.688, "range": 2098.7904},
			{"powers": [1.5], "speed": 851.2, "life": 2.832, "range": 2410.5984},
			{"powers": [1.0, 1.5], "speed": 992.0, "life": 3.12, "range": 3095.04},
			{"powers": [1.5, 1.0], "speed": 992.0, "life": 3.12, "range": 3095.04},
		]
	)
) -> void:
	var game := _begin()
	for power: float in sample.powers:
		if not _long(game, power):
			return
	var bolt := _shoot(game)
	_assert_bolt(bolt, sample.speed, sample.life)
	# Theoretical range only: arena exit still spends the bolt earlier.
	assert_almost_eq(bolt.speed * bolt.lifetime, sample.range, 0.001)
	assert_eq(game.upgrades.count("Long Burn"), sample.powers.size())


func test_many_mixed_stacks_keep_growing_without_a_cap_or_compounding() -> void:
	var game := _begin()
	for _index in 20:
		if not _long(game) or not _long(game, 1.5):
			return
	_assert_bolt(_shoot(game), 7680.0, 16.8)
	assert_eq(game.upgrades.count("Long Burn"), 40)


func test_boosted_bolt_actually_moves_and_ages_in_gameplay_step() -> void:
	var game := _begin()
	if not _long(game) or not _long(game, 1.5):
		return
	var bolt := _shoot(game)
	game._step_bolts(0.125)
	assert_almost_eq(bolt.position.x, 786.0, 0.0001)
	assert_almost_eq(bolt.position.y, 400.0, 0.0001)
	_assert_bolt(bolt, 992.0, 2.995)
	assert_eq(game.bolts.size(), 1)


func test_real_lifetime_outlasts_baseline_and_eventually_expires_inside_arena() -> void:
	var game := _begin()
	var baseline := _shoot(game)
	if not _long(game) or not _long(game, 1.5):
		return
	var boosted := _shoot(game)
	_oscillate(game, 49)
	assert_true(baseline.spent)
	assert_true(baseline.is_queued_for_deletion())
	assert_eq(game.bolts.size(), 1)
	_assert_bolt(boosted, 992.0, 0.67)
	_oscillate(game, 13)
	_assert_bolt(boosted, 992.0, 0.02)
	game._step_bolts(0.03)
	assert_true(Rect2(65, 160, 1150, 500).has_point(boosted.position))
	assert_true(boosted.spent)
	assert_true(boosted.is_queued_for_deletion())
	assert_eq(game.bolts.size(), 0)


func test_long_burn_keeps_existing_arena_exit_rule() -> void:
	var game := _begin()
	if not _long(game, 1.5):
		return
	game.keeper.position = Vector2(1180, 400)
	var bolt := _shoot(game)
	game._step_bolts(0.02)
	assert_almost_eq(bolt.position.x, 1219.024, 0.001)
	assert_true(bolt.lifetime > 2.8)
	assert_true(bolt.spent)
	assert_true(bolt.is_queued_for_deletion())
	assert_eq(game.bolts.size(), 0)


func test_new_rewards_do_not_change_existing_or_partly_aged_bolts() -> void:
	var game := _begin()
	var baseline := _shoot(game)
	game._step_bolts(0.1)
	if not _long(game):
		return
	var first := _shoot(game)
	_assert_bolt(baseline, 640.0, 2.3)
	game._step_bolts(0.1)
	if not _long(game, 1.5):
		return
	_assert_bolt(baseline, 640.0, 2.2)
	_assert_bolt(first, 780.8, 2.588)
	_assert_bolt(_shoot(game), 992.0, 3.12)
	assert_eq(game.bolts.size(), 3)


func test_real_enemy_attacks_preserve_hostile_speed_lifetime_and_movement(
	kind = use_parameters(["cantor", "boss", "boss_phase_two"])
) -> void:
	var game := _begin()
	if not _long(game) or not _long(game, 1.5):
		return
	game._spawn_foe("cantor" if kind == "cantor" else "boss", Vector2(300, 300))
	var foe: VigilFoe = game.foes.back()
	if kind == "boss_phase_two":
		foe.hp = 40.0
	foe.attack_clock = 0.0
	foe.step(0.0, game.keeper)
	assert_eq(game.bolts.size(), 1 if kind == "cantor" else (15 if foe.second_phase else 11))
	var snapshots := []
	for index in game.bolts.size():
		var bolt: VigilBolt = game.bolts[index]
		var speed := (
			175.0 if kind == "cantor" else (220.0 if index == game.bolts.size() - 1 else 155.0)
		)
		assert_true(bolt.hostile)
		assert_almost_eq(bolt.speed, speed, 0.0001)
		assert_almost_eq(bolt.lifetime, 2.4, 0.0001)
		assert_almost_eq(bolt.damage, 1.0, 0.0001)
		snapshots.append(bolt.position + bolt.direction * speed * 0.1)
	game._step_bolts(0.1)
	for index in game.bolts.size():
		var bolt: VigilBolt = game.bolts[index]
		assert_almost_eq(bolt.position.x, snapshots[index].x, 0.0001)
		assert_almost_eq(bolt.position.y, snapshots[index].y, 0.0001)
		assert_almost_eq(bolt.lifetime, 2.3, 0.0001)
		assert_false(bolt.spent)


func test_pool_contains_long_burn_and_preserves_all_six_existing_kindles() -> void:
	var game := _begin()
	var names := []
	var effects := []
	for kindle: Dictionary in game.KINDLES:
		names.append(kindle.name)
		effects.append(kindle.effect)
	assert_eq(
		names,
		["Wick", "Twin Wick", "Bellows", "Spare Wick", "Light Step", "Phoenix Ash", "Long Burn"]
	)
	assert_eq(effects, ["damage", "twin", "speed", "health", "dash", "heal", "long"])
	var reward_seen := false
	var shop_seen := false
	for candidate in range(32):
		seed(candidate)
		game._show_kindles()
		assert_eq(game.offered.size(), 3)
		var unique := {}
		for kindle: Dictionary in game.offered:
			assert_has(game.KINDLES, kindle)
			unique[kindle.name] = true
			reward_seen = reward_seen or kindle.name == "Long Burn"
		assert_eq(unique.size(), 3)
		seed(candidate)
		game._enter_room("SHOP")
		assert_has(game.KINDLES, game.offered[0])
		shop_seen = shop_seen or game.offered[0].name == "Long Burn"
	assert_true(reward_seen, "available through real randomized reward offers")
	assert_true(shop_seen, "available through real randomized shop offers")
	assert_eq(game.upgrades.size(), 0, "offering a Kindle must not apply it")
	_assert_bolt(_shoot(game), 640.0, 2.4)


func test_real_combat_reward_buttons_apply_normal_and_ordeal_weights(
	first_room = use_parameters(["KINDLE", "ORDEAL"])
) -> void:
	var game := _begin()
	for room_kind: String in [first_room, "ORDEAL" if first_room == "KINDLE" else "KINDLE"]:
		game._enter_room(room_kind)
		assert_eq(game.state, "play")
		if not _offer_seed(game, false):
			return
		_clear_combat(game)
		assert_eq(game.foes.size(), 0)
		assert_eq(game.state, "reward")
		assert_eq(game.offered.size(), 3)
		if not _press(game, "Long Burn  /  "):
			return
		assert_eq(game.state, "play")
		assert_false(game.ui.overlay.visible)
		assert_true(game.doors.size() > 0)
		assert_string_contains(game.ui.hud.text, "Long Burn")
		var bolt := _shoot(game)
		if game.upgrades.size() == 2:
			_assert_bolt(bolt, 992.0, 3.12)
		elif first_room == "KINDLE":
			_assert_bolt(bolt, 780.8, 2.688)
		else:
			_assert_bolt(bolt, 851.2, 2.832)
	assert_eq(game.upgrades.count("Long Burn"), 2)


func test_shop_refuses_long_burn_without_18_embers_even_if_callback_is_emitted() -> void:
	var game := _begin()
	game.embers = 17
	if not _offer_seed(game, true):
		return
	game._enter_room("SHOP")
	var buy := _button(game, "Long Burn  /  ")
	if buy == null:
		return
	assert_true(buy.disabled)
	buy.pressed.emit()
	assert_eq(game.embers, 17)
	assert_false(game.shop_bought)
	assert_eq(game.upgrades.size(), 0)
	_assert_bolt(_shoot(game), 640.0, 2.4)
	game.embers = 18
	game._refresh_shop()
	if not _press(game, "Long Burn  /  "):
		return
	assert_eq(game.embers, 0, "exactly 18 embers is sufficient")
	assert_true(game.shop_bought)
	assert_eq(game.upgrades.count("Long Burn"), 1)
	_assert_bolt(_shoot(game), 780.8, 2.688)


func test_shop_sells_long_burn_once_per_visit_at_normal_power() -> void:
	var game := _begin()
	# A preceding ORDEAL must not make a shop purchase grant ORDEAL power.
	game._enter_room("ORDEAL")
	game.embers = 40
	if not _offer_seed(game, true):
		return
	game._enter_room("SHOP")
	if not _press(game, "Long Burn  /  "):
		return
	assert_eq(game.embers, 22)
	assert_true(game.shop_bought)
	assert_eq(game.upgrades.count("Long Burn"), 1)
	_assert_bolt(_shoot(game), 780.8, 2.688)
	var bought := _button(game, "Long Burn  /  ")
	assert_not_null(bought)
	if bought == null:
		return
	assert_true(bought.disabled)
	bought.pressed.emit()
	assert_eq(game.embers, 22)
	assert_eq(game.upgrades.count("Long Burn"), 1)
	_assert_bolt(_shoot(game), 780.8, 2.688)
	if not _press(game, "LEAVE THE CANDLEWRIGHT"):
		return
	if not _offer_seed(game, true):
		return
	game._enter_room("SHOP")
	assert_false(game.shop_bought)
	if not _press(game, "Long Burn  /  "):
		return
	assert_eq(game.embers, 4)
	assert_eq(game.upgrades.count("Long Burn"), 2)
	_assert_bolt(_shoot(game), 921.6, 2.976)


func test_real_restart_and_shore_paths_remove_long_burn_before_next_shot(
	path = use_parameters(
		["pause_restart", "loss_retry", "win_retry", "pause_shore", "loss_shore", "win_shore"]
	)
) -> void:
	var game := _begin()
	if not _long(game) or not _long(game, 1.5):
		return
	var old_bolt := _shoot(game)
	_assert_bolt(old_bolt, 992.0, 3.12)
	if path.begins_with("pause"):
		game._pause_run()
		assert_eq(game.state, "paused")
	elif path.begins_with("loss"):
		game.keeper.hp = 1
		game.keeper.hurt()
		assert_eq(game.state, "lost")
	else:
		game._enter_room("THE DROWNED TOLLING")
		_clear_combat(game)
		assert_eq(game.state, "won")
	if path.ends_with("shore"):
		if not _press(game, "RETURN TO SHORE"):
			return
		assert_eq(game.state, "title")
		assert_eq(game.bolts.size(), 0)
		# Observe reset on the shore itself; _start_run must not mask a missing title reset.
		_assert_bolt(_shoot(game), 640.0, 2.4)
		if not _press(game, "BEGIN THE VIGIL"):
			return
	else:
		var label := "RESTART"
		if path == "loss_retry":
			label = "TRY THE VIGIL AGAIN"
		elif path == "win_retry":
			label = "CARRY ANOTHER LIGHT"
		if not _press(game, label):
			return
	assert_eq(game.state, "play")
	assert_true(old_bolt.is_queued_for_deletion())
	assert_eq(game.bolts.size(), 0)
	assert_eq(game.upgrades.size(), 0)
	_assert_bolt(_shoot(game), 640.0, 2.4)
	if not _long(game):
		return
	_assert_bolt(_shoot(game), 780.8, 2.688)


func test_long_burn_composes_with_all_six_kindles_and_real_twin_wick_firing(
	order = use_parameters(["long_first", "long_last"])
) -> void:
	var game := _begin()
	game.keeper.hp = 1
	if order == "long_first" and not _long(game):
		return
	for label in ["Wick", "Twin Wick", "Bellows", "Spare Wick", "Light Step", "Phoenix Ash"]:
		game._apply_kindle(_kindle(game, label))
	if order == "long_last" and not _long(game):
		return
	assert_eq(game.keeper.max_hp, 6)
	assert_eq(game.keeper.hp, 5)
	assert_almost_eq(game.keeper.damage, 1.35, 0.0001)
	assert_almost_eq(game.keeper.fire_interval, 0.1875, 0.0001)
	assert_almost_eq(game.keeper.max_dash_cooldown, 0.6375, 0.0001)
	assert_true(game.keeper.twin_wick)
	_shoot(game)
	assert_eq(game.bolts.size(), 2)
	for index in 2:
		var bolt: VigilBolt = game.bolts[index]
		_assert_bolt(bolt, 780.8, 2.688, 1.35)
		assert_almost_eq(bolt.direction.angle(), -0.1 if index == 0 else 0.1, 0.0001)
	Input.action_press("aim_right")
	game.keeper.step(0.1874)
	assert_eq(game.bolts.size(), 2, "Bellows still obeys its fire cooldown")
	game.keeper.step(0.0002)
	Input.action_release("aim_right")
	assert_eq(game.bolts.size(), 4)
	for bolt: VigilBolt in game.bolts:
		_assert_bolt(bolt, 780.8, 2.688, 1.35)
	game._apply_kindle(_kindle(game, "Twin Wick"))
	_assert_bolt(_shoot(game), 780.8, 2.688, 1.6875)
	assert_eq(game.bolts.size(), 6)
