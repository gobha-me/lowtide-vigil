extends GutTest
## Real bolts mark retirement; Vigil removes them across expiry and callback re-entry.

const VIGIL = preload("res://scenes/vigil.tscn")
const EXPIRY_CASES := {
	"lifetime": [Vector2(640, 400), Vector2.RIGHT],
	"left": [Vector2(65, 400), Vector2.LEFT],
	"right": [Vector2(1214, 400), Vector2.RIGHT],
	"top": [Vector2(640, 160), Vector2.UP],
	"bottom": [Vector2(640, 659), Vector2.DOWN],
}


func _game() -> Node2D:
	var game: Node2D = VIGIL.instantiate()
	add_child_autoqfree(game)
	game.set_process(false)
	game._start_run()
	game._clear_room()
	return game


func _standalone_bolt(expiry: String) -> VigilBolt:
	var bolt := VigilBolt.new()
	bolt.position = EXPIRY_CASES[expiry][0]
	bolt.direction = EXPIRY_CASES[expiry][1]
	bolt.speed = 20.0
	if expiry == "lifetime":
		bolt.lifetime = 0.05
	add_child_autoqfree(bolt)
	return bolt


func _bolt_children(game: Node2D) -> Array:
	return game.get_children().filter(func(child: Node) -> bool: return child is VigilBolt)


func _watch_exits(bolts: Array, exits: Array) -> Array[int]:
	var ids: Array[int] = []
	for bolt: VigilBolt in bolts:
		var instance_id := bolt.get_instance_id()
		ids.append(instance_id)
		bolt.tree_exiting.connect(func(): exits.append(instance_id))
	return ids


func _assert_queued(bolts: Array) -> void:
	for bolt: VigilBolt in bolts:
		assert_true(bolt.is_queued_for_deletion())


func _assert_retired(game: Node2D, bolts: Array, ids: Array[int], exits: Array) -> void:
	assert_eq(game.bolts.size(), 0)
	assert_eq(_bolt_children(game).size(), 0)
	for bolt in bolts:
		assert_false(is_instance_valid(bolt))
	ids.sort()
	exits.sort()
	assert_eq(exits, ids, "each registered bolt leaves the tree exactly once")


func test_step_marks_expiry_but_keeps_deletion_with_owner(
	expiry = use_parameters(EXPIRY_CASES.keys())
) -> void:
	var bolt := _standalone_bolt(expiry)
	bolt.step(0.05)
	assert_true(bolt.spent)
	assert_false(bolt.is_queued_for_deletion(), "VigilBolt.step must not queue its own deletion")
	var position_after_expiry := bolt.position
	var lifetime_after_expiry := bolt.lifetime
	bolt.step(0.25)
	assert_eq(bolt.position, position_after_expiry, "spent bolts stop moving")
	assert_eq(bolt.lifetime, lifetime_after_expiry, "spent bolts stop aging")
	await get_tree().process_frame
	assert_true(is_instance_valid(bolt), "the caller still owns the spent bolt")


func test_already_spent_bolt_ignores_zero_positive_and_negative_delta(
	delta = use_parameters([0.0, 0.25, -0.25])
) -> void:
	var bolt := _standalone_bolt("lifetime")
	bolt.spent = true
	var position_before := bolt.position
	var lifetime_before := bolt.lifetime
	bolt.step(delta)
	assert_eq(bolt.position, position_before)
	assert_eq(bolt.lifetime, lifetime_before)
	assert_false(bolt.is_queued_for_deletion())


func test_inclusive_top_left_and_just_inside_bottom_right_are_not_expired(
	origin = use_parameters([Vector2(65, 160), Vector2(1214.5, 659.5)])
) -> void:
	var bolt := _standalone_bolt("lifetime")
	bolt.position = origin
	bolt.direction = Vector2.ZERO
	bolt.lifetime = 1.0
	bolt.step(0.05)
	assert_false(bolt.spent)
	assert_false(bolt.is_queued_for_deletion())
	assert_eq(bolt.position, origin)


func test_vigil_retires_expired_friendly_and_hostile_bolts_without_contact_damage(
	contact = use_parameters(
		[
			["lifetime", false],
			["lifetime", true],
			["left", false],
			["left", true],
			["right", false],
			["right", true],
			["top", false],
			["top", true],
			["bottom", false],
			["bottom", true],
		]
	)
) -> void:
	var game := _game()
	var origin: Vector2 = EXPIRY_CASES[contact[0]][0]
	game.keeper.position = origin
	game.keeper.invulnerable = 0.0
	game._spawn_foe("root", origin)
	var foe: VigilFoe = game.foes.back()
	watch_signals(game.keeper)
	game._make_bolt(origin, EXPIRY_CASES[contact[0]][1], 20.0, contact[1], 2.0)
	var bolt: VigilBolt = game.bolts.back()
	if contact[0] == "lifetime":
		bolt.lifetime = 0.05
	var bolts := [bolt]
	var exits := []
	var ids := _watch_exits(bolts, exits)
	game._step_bolts(0.05)
	assert_true(bolt.spent)
	assert_eq(game.bolts.size(), 0)
	_assert_queued(bolts)
	assert_eq(foe.hp, 3.0, "expiry is resolved before a friendly contact")
	assert_eq(game.keeper.hp, 5, "expiry is resolved before a hostile contact")
	assert_signal_not_emitted(game.keeper, "damaged")
	await get_tree().process_frame
	_assert_retired(game, bolts, ids, exits)


func test_hit_bolt_is_consumed_once_with_overlapping_foes() -> void:
	var game := _game()
	game._spawn_foe("root", Vector2(400, 400))
	game._spawn_foe("root", Vector2(400, 400))
	var first: VigilFoe = game.foes[0]
	var second: VigilFoe = game.foes[1]
	game._make_bolt(first.position, Vector2.RIGHT, 640.0, false, 1.25)
	var bolt: VigilBolt = game.bolts.back()
	var bolts := [bolt]
	var exits := []
	var ids := _watch_exits(bolts, exits)
	game._step_bolts(0.0)
	assert_almost_eq(first.hp, 1.75, 0.0001)
	assert_eq(second.hp, 3.0)
	assert_true(bolt.spent)
	assert_eq(game.bolts.size(), 0)
	_assert_queued(bolts)
	game._step_bolts(0.1)
	assert_almost_eq(first.hp, 1.75, 0.0001, "a consumed bolt cannot hit again")
	assert_eq(second.hp, 3.0)
	await get_tree().process_frame
	_assert_retired(game, bolts, ids, exits)


func test_last_foe_room_callback_retires_the_snapshot_without_stepping_later_bolts(
	reward = use_parameters(["EMBERS", "FONT", "SHOP"])
) -> void:
	var game := _game()
	game.reward = reward
	game._spawn_foe("root", Vector2(400, 400))
	game._spawn_foe("root", Vector2(400, 400))
	var first: VigilFoe = game.foes[0]
	var last: VigilFoe = game.foes[1]
	watch_signals(first)
	watch_signals(last)
	game._make_bolt(first.position, Vector2.RIGHT, 640.0, false, 3.0)
	game._make_bolt(last.position, Vector2.RIGHT, 640.0, false, 3.0)
	game._make_bolt(Vector2(700, 500), Vector2.RIGHT, 640.0, false, 1.0)
	game._make_bolt(Vector2(700, 450), Vector2.UP, 175.0, true, 1.0)
	var bolts: Array = game.bolts.duplicate()
	var exits := []
	var ids := _watch_exits(bolts, exits)
	var later_positions := [bolts[2].position, bolts[3].position]
	var later_lifetimes := [bolts[2].lifetime, bolts[3].lifetime]
	game._step_bolts(0.01)
	assert_signal_emit_count(first, "defeated", 1)
	assert_signal_emit_count(last, "defeated", 1)
	assert_eq(game.foes.size(), 0)
	assert_eq(game.kills, 2)
	assert_eq(game.bolts.size(), 0)
	assert_eq(game.state, "play")
	assert_eq(game.doors.size(), 3)
	_assert_queued(bolts)
	for bolt: VigilBolt in bolts:
		assert_true(bolt.spent)
	assert_eq([bolts[2].position, bolts[3].position], later_positions)
	assert_eq([bolts[2].lifetime, bolts[3].lifetime], later_lifetimes)
	await get_tree().process_frame
	_assert_retired(game, bolts, ids, exits)


func test_direct_room_cleanup_leaves_no_registered_or_child_bolts(
	cleanup = use_parameters(["_open_doors", "_clear_room"])
) -> void:
	var game := _game()
	for index in 3:
		game._make_bolt(Vector2(400 + index * 100, 400), Vector2.RIGHT, 640.0, index == 1, 1.0)
	game.bolts[2].spent = true
	var bolts: Array = game.bolts.duplicate()
	var exits := []
	var ids := _watch_exits(bolts, exits)
	game.call(cleanup)
	assert_eq(game.bolts.size(), 0)
	_assert_queued(bolts)
	await get_tree().process_frame
	_assert_retired(game, bolts, ids, exits)
