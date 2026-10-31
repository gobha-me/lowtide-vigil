extends GutTest
## VigilFoe: stat setup, the boss's second toll and defeat.


func _make_foe(kind: String, elite: bool = false) -> VigilFoe:
	var foe := VigilFoe.new()
	foe.setup(kind, elite)
	add_child_autofree(foe)
	return foe


func _far_keeper() -> VigilKeeper:
	var keeper := VigilKeeper.new()
	keeper.position = Vector2(1150, 600)
	add_child_autofree(keeper)
	return keeper


func test_setup_boss_stats() -> void:
	var boss := _make_foe("boss")
	assert_almost_eq(boss.max_hp, 100.0, 0.0001)
	assert_almost_eq(boss.hp, 100.0, 0.0001)
	assert_almost_eq(boss.radius, 40.0, 0.0001)
	assert_almost_eq(boss.speed, 48.0, 0.0001)


func test_setup_elite_cantor_multipliers() -> void:
	var cantor := _make_foe("cantor", true)
	assert_true(cantor.elite)
	assert_almost_eq(cantor.max_hp, 7.2, 0.0001)
	assert_almost_eq(cantor.hp, 7.2, 0.0001)
	assert_almost_eq(cantor.speed, 44.0 * 1.15, 0.0001)
	assert_almost_eq(cantor.radius, 18.0 * 1.2, 0.0001)


func test_boss_enters_second_phase_below_half() -> void:
	var keeper := _far_keeper()
	var boss := _make_foe("boss")
	boss.position = Vector2(200, 250)
	boss.hp = 49.0
	watch_signals(boss)
	boss.step(0.016, keeper)
	assert_true(boss.second_phase)
	assert_signal_emit_count(boss, "toll_changed", 1)

	var calm := _make_foe("boss")
	calm.position = Vector2(200, 250)
	calm.hp = 51.0
	watch_signals(calm)
	calm.step(0.016, keeper)
	assert_false(calm.second_phase)
	assert_signal_not_emitted(calm, "toll_changed")
	assert_eq(keeper.hp, 5)


func test_take_hit_defeats_at_exactly_zero() -> void:
	var foe := _make_foe("root")
	foe.hp = 1.0
	watch_signals(foe)
	foe.take_hit(1.0)
	assert_true(foe.dead)
	assert_signal_emit_count(foe, "defeated", 1)
	assert_signal_emitted_with_parameters(foe, "defeated", [foe])


func test_take_hit_ignored_when_dead() -> void:
	var foe := _make_foe("root")
	watch_signals(foe)
	foe.take_hit(5.0)
	assert_true(foe.dead)
	var hp_after_defeat := foe.hp
	foe.take_hit(1.0)
	assert_almost_eq(foe.hp, hp_after_defeat, 0.0001)
	assert_signal_emit_count(foe, "defeated", 1)
