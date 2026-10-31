extends GutTest
## VigilKeeper: flames, the hurt window and the lantern radius.


func _make_keeper() -> VigilKeeper:
	var keeper := VigilKeeper.new()
	add_child_autofree(keeper)
	return keeper


func test_light_scale_tracks_flames() -> void:
	var keeper := _make_keeper()
	keeper.max_hp = 5
	keeper.hp = 5
	assert_almost_eq(keeper.light_scale(), 1.0, 0.0001)
	keeper.hp = 1
	assert_almost_eq(keeper.light_scale(), 0.6, 0.0001)
	keeper.hp = 0
	assert_almost_eq(keeper.light_scale(), 0.5, 0.0001)


func test_hurt_costs_one_flame_and_grants_invulnerability() -> void:
	var keeper := _make_keeper()
	watch_signals(keeper)
	keeper.hurt()
	assert_eq(keeper.hp, 4)
	assert_almost_eq(keeper.invulnerable, 1.1, 0.0001)
	assert_signal_emit_count(keeper, "damaged", 1)


func test_hurt_ignored_while_invulnerable() -> void:
	var keeper := _make_keeper()
	keeper.hurt()
	assert_eq(keeper.hp, 4)
	keeper.hurt()
	assert_eq(keeper.hp, 4)


func test_hurt_ignored_while_dashing() -> void:
	var keeper := _make_keeper()
	watch_signals(keeper)
	keeper.dash_left = 0.1
	keeper.invulnerable = 0.0
	keeper.hurt()
	assert_eq(keeper.hp, 5)
	assert_signal_not_emitted(keeper, "damaged")


func test_extinguished_emitted_once_at_zero() -> void:
	var keeper := _make_keeper()
	keeper.hp = 1
	watch_signals(keeper)
	keeper.hurt()
	assert_eq(keeper.hp, 0)
	assert_signal_emit_count(keeper, "extinguished", 1)
	keeper.invulnerable = 0.0
	keeper.hurt()
	assert_eq(keeper.hp, 0)
	assert_signal_emit_count(keeper, "extinguished", 1)
	assert_signal_emit_count(keeper, "damaged", 1)
