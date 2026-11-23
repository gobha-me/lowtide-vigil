extends "res://test/unit/test_ordeal_power_baselines.gd"
## Issue #20: ORDEAL ignores power for Twin Wick, Spare Wick and Phoenix Ash.
## Expected failures on main, pending #30. Explicit opt-in keeps CI's strict
## zero-pending policy intact; see this directory's README for both commands.


func _run_regression() -> bool:
	if OS.get_environment("LOWTIDE_RUN_KNOWN_BUGS") == "1":
		return true
	pending("Issue #20: ORDEAL reward power ignored; pending #30")
	return false


func test_ordeal_repeated_twin_wick_is_stronger_than_ordinary_repeat() -> void:
	if not _run_regression():
		return
	var ordinary := _make_vigil()
	var ordeal := _make_vigil()
	for vigil: Node2D in [ordinary, ordeal]:
		vigil.keeper.damage = 2.0
		vigil._apply_kindle(_kindle(vigil, "Twin Wick"), 1.0)
	ordinary._apply_kindle(_kindle(ordinary, "Twin Wick"), 1.0)
	ordeal._apply_kindle(_kindle(ordeal, "Twin Wick"), 1.5)
	assert_gt(
		ordeal.keeper.damage,
		ordinary.keeper.damage,
		"Issue #20, pending #30: ORDEAL must increase the repeat-Twin damage bonus"
	)


func test_ordeal_spare_wick_adds_more_flames_than_ordinary() -> void:
	if not _run_regression():
		return
	var ordinary := _make_vigil()
	var ordeal := _make_vigil()
	ordinary.keeper.hp = 1
	ordeal.keeper.hp = 1
	ordinary._apply_kindle(_kindle(ordinary, "Spare Wick"), 1.0)
	ordeal._apply_kindle(_kindle(ordeal, "Spare Wick"), 1.5)
	assert_true(
		ordeal.keeper.hp > ordinary.keeper.hp and ordeal.keeper.max_hp > ordinary.keeper.max_hp,
		(
			(
				"Issue #20, pending #30: ORDEAL Spare must grant more current and maximum flames; "
				+ "ordinary %s/%s, ORDEAL %s/%s"
			)
			% [ordinary.keeper.hp, ordinary.keeper.max_hp, ordeal.keeper.hp, ordeal.keeper.max_hp]
		)
	)


func test_ordeal_phoenix_ash_heals_more_than_ordinary_below_cap() -> void:
	if not _run_regression():
		return
	var ordinary := _make_vigil()
	var ordeal := _make_vigil()
	for vigil: Node2D in [ordinary, ordeal]:
		vigil.keeper.max_hp = 12
		vigil.keeper.hp = 1
	ordinary._apply_kindle(_kindle(ordinary, "Phoenix Ash"), 1.0)
	ordeal._apply_kindle(_kindle(ordeal, "Phoenix Ash"), 1.5)
	assert_gt(
		ordeal.keeper.hp,
		ordinary.keeper.hp,
		"Issue #20, pending #30: ORDEAL Phoenix must heal more when neither reward reaches the cap"
	)
	assert_lte(ordeal.keeper.hp, ordeal.keeper.max_hp)
	assert_eq(ordeal.keeper.max_hp, 12)
