extends GutTest
## VigilInterface: the HUD line for flames and embers.


func test_hud_shows_lit_and_spent_flames_and_embers() -> void:
	var ui := VigilInterface.new()
	add_child_autofree(ui)
	var keeper := VigilKeeper.new()
	add_child_autofree(keeper)
	keeper.max_hp = 5
	keeper.hp = 3
	var upgrades: Array[String] = []
	ui.update_hud(keeper, 17, 1, upgrades)
	assert_string_contains(ui.hud.text, "* * * . . ")
	assert_string_contains(ui.hud.text, "EMBERS  17")
