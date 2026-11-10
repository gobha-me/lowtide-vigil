extends GutTest
## Real combat contacts, first-hit consumption, and bolt construction.

const VIGIL = preload("res://scenes/vigil.tscn")


func _game() -> Node2D:
	var game: Node2D = VIGIL.instantiate()
	add_child_autoqfree(game)
	game.set_process(false)
	game._start_run()
	return game


func _foe(game: Node2D, origin: Vector2) -> VigilFoe:
	game._spawn_foe("root", origin)
	return game.foes.back()


func _friendly(game: Node2D, origin: Vector2) -> VigilBolt:
	game._fire_bolt(origin, Vector2.RIGHT)
	return game.bolts.back()


func test_friendly_bolt_damages_only_first_overlapping_foe_once() -> void:
	var game := _game()
	var first := _foe(game, Vector2(400, 400))
	var second := _foe(game, first.position)
	game.keeper.damage = 1.25
	var bolt := _friendly(game, first.position)
	game._step_bolts(0.0)
	assert_almost_eq(first.hp, 1.75, 0.0001)
	assert_eq(second.hp, 3.0, "one bolt cannot damage both overlapping foes")
	assert_true(bolt.spent)
	assert_true(bolt.is_queued_for_deletion())
	assert_eq(game.bolts.size(), 0)
	game._step_bolts(0.0)
	assert_almost_eq(first.hp, 1.75, 0.0001, "the consumed bolt cannot hit again")
	await get_tree().process_frame
	assert_false(is_instance_valid(bolt))


func test_lethal_first_contact_does_not_damage_next_foe_after_array_changes() -> void:
	var game := _game()
	var first := _foe(game, Vector2(400, 400))
	var second := _foe(game, first.position)
	first.hp = 1.0
	watch_signals(first)
	var bolt := _friendly(game, first.position)
	game._step_bolts(0.0)
	assert_signal_emit_count(first, "defeated", 1)
	assert_eq(game.foes, [second], "defeat removes the first foe during traversal")
	assert_eq(second.hp, 3.0)
	assert_true(bolt.spent)
	assert_eq(game.bolts.size(), 0)


func test_hostile_bolts_hurt_keeper_once_and_do_not_hurt_overlapping_foe() -> void:
	var game := _game()
	var foe := _foe(game, game.keeper.position)
	watch_signals(game.keeper)
	game._fire_hostile(game.keeper.position, Vector2.UP, 175.0)
	game._fire_hostile(game.keeper.position, Vector2.DOWN, 220.0)
	var bolts: Array = game.bolts.duplicate()
	game._step_bolts(0.0)
	assert_eq(game.keeper.hp, 4)
	assert_signal_emit_count(game.keeper, "damaged", 1)
	assert_almost_eq(game.keeper.invulnerable, 1.1, 0.0001)
	assert_eq(foe.hp, 3.0)
	assert_eq(game.bolts.size(), 0)
	for bolt: VigilBolt in bolts:
		assert_true(bolt.spent)
		assert_true(bolt.is_queued_for_deletion())


func test_hostile_contact_is_consumed_even_when_keeper_cannot_be_hurt(
	protection = use_parameters(["dash", "invulnerable"])
) -> void:
	var game := _game()
	if protection == "dash":
		game.keeper.dash_left = 0.1
	else:
		game.keeper.invulnerable = 0.1
	watch_signals(game.keeper)
	game._fire_hostile(game.keeper.position, Vector2.UP, 175.0)
	var bolt: VigilBolt = game.bolts.back()
	game._step_bolts(0.0)
	assert_eq(game.keeper.hp, 5)
	assert_signal_not_emitted(game.keeper, "damaged")
	assert_true(bolt.spent)
	assert_eq(game.bolts.size(), 0)


func test_friendly_swept_hit_excludes_exact_tangent_and_near_miss(
	contact = use_parameters([[22.5, true], [23.0, false], [23.5, false]])
) -> void:
	var game := _game()
	var foe := _foe(game, Vector2(480, 400 + contact[0]))
	var bolt := _friendly(game, Vector2(400, 400))
	game._step_bolts(0.25)
	assert_eq(bolt.position, Vector2(560, 400))
	assert_eq(foe.hp, 2.0 if contact[1] else 3.0)
	assert_eq(bolt.spent, contact[1])
	assert_eq(game.bolts.has(bolt), not contact[1])


func test_hostile_swept_hit_excludes_exact_tangent_and_near_miss(
	contact = use_parameters([[15.5, true], [16.0, false], [16.5, false]])
) -> void:
	var game := _game()
	game.keeper.position = Vector2(480, 400 + contact[0])
	game._fire_hostile(Vector2(400, 400), Vector2.RIGHT, 640.0)
	var bolt: VigilBolt = game.bolts.back()
	game._step_bolts(0.25)
	assert_eq(game.keeper.hp, 4 if contact[1] else 5)
	assert_eq(bolt.spent, contact[1])
	assert_eq(game.bolts.has(bolt), not contact[1])


func test_expired_bolt_cannot_damage_an_overlapping_target(
	hostile = use_parameters([false, true])
) -> void:
	var game := _game()
	var foe := _foe(game, game.keeper.position)
	game._make_bolt(foe.position, Vector2.UP, 0.0, hostile, 2.0)
	var bolt: VigilBolt = game.bolts.back()
	bolt.lifetime = 0.05
	watch_signals(game.keeper)
	game._step_bolts(0.05)
	assert_eq(foe.hp, 3.0)
	assert_eq(game.keeper.hp, 5)
	assert_signal_not_emitted(game.keeper, "damaged")
	assert_true(bolt.spent)
	assert_eq(game.bolts.size(), 0)


func test_fire_bolt_uses_baseline_speed_and_snapshots_current_keeper_damage() -> void:
	var game := _game()
	game.keeper.damage = 2.75
	var origin := Vector2(300, 350)
	var direction := Vector2(0.6, -0.8)
	game._fire_bolt(origin, direction)
	assert_eq(game.bolts.size(), 1)
	if game.bolts.size() != 1:
		return
	var bolt: VigilBolt = game.bolts[0]
	assert_eq(bolt.get_parent(), game)
	assert_eq(bolt.position, origin)
	assert_eq(bolt.direction, direction)
	assert_eq(bolt.speed, 640.0)
	assert_eq(bolt.damage, 2.75)
	assert_false(bolt.hostile)
	assert_false(bolt.spent)
	game.keeper.damage = 4.25
	game._fire_bolt(origin, -direction)
	assert_eq(game.bolts.size(), 2)
	assert_eq(bolt.damage, 2.75, "later upgrades cannot change bolts already in flight")
	assert_eq(game.bolts.back().damage, 4.25)


func test_fire_hostile_preserves_requested_speed_direction_and_hostility() -> void:
	var game := _game()
	game.keeper.damage = 9.0
	game._fire_hostile(Vector2(300, 350), Vector2.DOWN, 175.5)
	assert_eq(game.bolts.size(), 1)
	if game.bolts.size() != 1:
		return
	var bolt: VigilBolt = game.bolts[0]
	assert_eq(bolt.position, Vector2(300, 350))
	assert_eq(bolt.direction, Vector2.DOWN)
	assert_eq(bolt.speed, 175.5)
	assert_eq(bolt.damage, 1.0)
	assert_true(bolt.hostile)
