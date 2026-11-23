extends GutTest
## Issue #20: ordinary rewards retain their documented power == 1.0 results.


func _make_vigil() -> Node2D:
	var vigil: Node2D = load("res://scenes/vigil.tscn").instantiate()
	add_child_autoqfree(vigil)
	# Exercise the packed scene directly, without foes acting between reward calls.
	vigil.set_process(false)
	vigil._start_run()
	return vigil


func _kindle(vigil: Node2D, kindle_name: String) -> Dictionary:
	for kindle: Dictionary in vigil.KINDLES:
		if kindle.name == kindle_name:
			return kindle
	fail_test("missing Kindle: " + kindle_name)
	return {}


func test_ordinary_repeated_twin_wick_preserves_one_quarter_damage_bonus() -> void:
	var vigil := _make_vigil()
	vigil.keeper.damage = 2.0
	var twin := _kindle(vigil, "Twin Wick")
	vigil._apply_kindle(twin, 1.0)
	vigil._apply_kindle(twin, 1.0)
	assert_true(vigil.keeper.twin_wick)
	assert_almost_eq(vigil.keeper.damage, 2.5, 0.0001)


func test_ordinary_spare_wick_adds_one_current_and_maximum_flame() -> void:
	var vigil := _make_vigil()
	vigil.keeper.hp = 1
	vigil._apply_kindle(_kindle(vigil, "Spare Wick"), 1.0)
	assert_eq(vigil.keeper.hp, 2)
	assert_eq(vigil.keeper.max_hp, 6)


func test_ordinary_phoenix_ash_heals_three_without_increasing_capacity() -> void:
	var vigil := _make_vigil()
	# Leave ample room so the maximum-flame cap cannot hide the heal amount.
	vigil.keeper.max_hp = 12
	vigil.keeper.hp = 1
	vigil._apply_kindle(_kindle(vigil, "Phoenix Ash"), 1.0)
	assert_eq(vigil.keeper.hp, 4)
	assert_eq(vigil.keeper.max_hp, 12)
