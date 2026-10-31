extends GutTest
## The vigil scene: run setup, room rewards, the shop and the end of a run.


func _make_vigil() -> Node2D:
	var vigil: Node2D = load("res://scenes/vigil.tscn").instantiate()
	# Queue-freed so panel children the scene discards are gone before orphans are counted.
	add_child_autoqfree(vigil)
	# Tests drive the run directly; frame updates would let foes act between calls.
	vigil.set_process(false)
	vigil._start_run()
	return vigil


func _kindle(vigil: Node2D, kindle_name: String) -> Dictionary:
	for kindle: Dictionary in vigil.KINDLES:
		if kindle.name == kindle_name:
			return kindle
	fail_test("no kindle named " + kindle_name)
	return {}


func _door_rewards(vigil: Node2D) -> Array:
	var rewards := []
	for door: VigilDoor in vigil.doors:
		rewards.append(door.reward)
	return rewards


func test_start_run_resets_keeper_and_offers_first_doors() -> void:
	var vigil := _make_vigil()
	assert_eq(vigil.keeper.hp, 5)
	assert_eq(vigil.keeper.max_hp, 5)
	assert_eq(vigil.room, 0)
	assert_eq(vigil.embers, 0)
	assert_eq(vigil.state, "play")
	assert_eq(_door_rewards(vigil), ["KINDLE", "EMBERS", "ORDEAL"])


func test_font_relights_two_flames() -> void:
	var vigil := _make_vigil()
	vigil.keeper.hp = 2
	vigil._enter_room("FONT")
	assert_eq(vigil.keeper.hp, 4)
	assert_eq(vigil.embers, 0)


func test_font_at_full_flames_grants_12_embers() -> void:
	var vigil := _make_vigil()
	vigil._enter_room("FONT")
	assert_eq(vigil.keeper.hp, 5)
	assert_eq(vigil.embers, 12)


func test_wick_damage_scales_with_ordeal_power() -> void:
	var vigil := _make_vigil()
	vigil._apply_kindle(_kindle(vigil, "Wick"), 1.0)
	assert_almost_eq(vigil.keeper.damage, 1.35, 0.0001)
	vigil._start_run()
	assert_almost_eq(vigil.keeper.damage, 1.0, 0.0001)
	vigil._apply_kindle(_kindle(vigil, "Wick"), 1.5)
	assert_almost_eq(vigil.keeper.damage, 1.525, 0.0001)


func test_bellows_fire_interval_floors_at_0_08() -> void:
	var vigil := _make_vigil()
	var lowest: float = vigil.keeper.fire_interval
	for _index in 8:
		vigil._apply_kindle(_kindle(vigil, "Bellows"))
		lowest = minf(lowest, vigil.keeper.fire_interval)
	assert_true(lowest >= 0.08, "fire interval fell to %f" % lowest)
	assert_almost_eq(vigil.keeper.fire_interval, 0.08, 0.0001)


func test_phoenix_ash_caps_at_max_flames() -> void:
	var vigil := _make_vigil()
	vigil.keeper.hp = 4
	vigil._apply_kindle(_kindle(vigil, "Phoenix Ash"))
	assert_eq(vigil.keeper.hp, 5)
	assert_eq(vigil.keeper.max_hp, 5)


func test_shop_kindle_costs_18_and_sells_once() -> void:
	var vigil := _make_vigil()
	vigil._enter_room("SHOP")
	assert_eq(vigil.state, "shop")
	vigil.embers = 40
	vigil._buy_kindle(_kindle(vigil, "Wick"))
	assert_eq(vigil.embers, 22)
	assert_true(vigil.shop_bought)
	vigil._buy_kindle(_kindle(vigil, "Wick"))
	assert_eq(vigil.embers, 22)
	assert_true(vigil.shop_bought)
	assert_almost_eq(vigil.keeper.damage, 1.35, 0.0001)


func test_mend_refused_at_full_flames() -> void:
	var vigil := _make_vigil()
	vigil._enter_room("SHOP")
	vigil.embers = 20
	assert_eq(vigil.keeper.hp, 5)
	vigil._buy_mend()
	assert_eq(vigil.embers, 20)
	assert_eq(vigil.keeper.hp, 5)


func test_defeat_embers_elite_5_regular_3() -> void:
	var vigil := _make_vigil()
	vigil._enter_room("ORDEAL")
	var elite: VigilFoe = vigil.foes[0]
	assert_true(elite.elite)
	elite.take_hit(100.0)
	assert_false(vigil.foes.is_empty())
	assert_eq(vigil.embers, 5)

	vigil._start_run()
	vigil._enter_room("KINDLE")
	var regular: VigilFoe = vigil.foes[0]
	assert_false(regular.elite)
	regular.take_hit(100.0)
	assert_false(vigil.foes.is_empty())
	assert_eq(vigil.embers, 3)


func test_ordeal_room_spawns_one_extra_elite_foe() -> void:
	var vigil := _make_vigil()
	vigil._enter_room("ORDEAL")
	assert_eq(vigil.foes.size(), 5)
	var elites: Array = vigil.foes.filter(func(foe: VigilFoe) -> bool: return foe.elite)
	assert_eq(elites.size(), 5)

	vigil._start_run()
	vigil._enter_room("KINDLE")
	assert_eq(vigil.foes.size(), 4)
	elites = vigil.foes.filter(func(foe: VigilFoe) -> bool: return foe.elite)
	assert_eq(elites.size(), 0)


func test_room_four_offers_only_the_drowned_tolling() -> void:
	var vigil := _make_vigil()
	vigil._clear_room()
	vigil.room = 4
	vigil._open_doors()
	assert_eq(_door_rewards(vigil), ["THE DROWNED TOLLING"])


func test_boss_defeat_wins_run() -> void:
	var vigil := _make_vigil()
	vigil.room = 4
	vigil._enter_room("THE DROWNED TOLLING")
	assert_eq(vigil.foes.size(), 1)
	var boss: VigilFoe = vigil.foes[0]
	assert_eq(boss.kind, "boss")
	boss.take_hit(boss.hp)
	assert_true(boss.dead)
	assert_eq(vigil.state, "won")


func test_last_flame_loses_run() -> void:
	var vigil := _make_vigil()
	vigil.keeper.hp = 1
	vigil.keeper.hurt()
	assert_eq(vigil.keeper.hp, 0)
	assert_eq(vigil.state, "lost")
