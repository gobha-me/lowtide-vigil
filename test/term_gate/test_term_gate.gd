extends GutTest
## The real term gate, run in a temp copy of the tracked tree with one planted change.
## Planted words are assembled from pieces so this file's own literals stay clean.

const Sandbox := preload("res://test/helpers/term_gate_sandbox.gd")
const PLANTED_UI := "scripts/planted_ui.gd"
const WEB_PAGE := "web/lowtide-vigil.html"
const FIRST_TUTORIAL := "'LEFT THUMB MOVE · RIGHT THUMB AIM AND FIRE'"
const FIRST_TUTORIAL_LINE := 1560


## Copies the tree, plants a change, runs the gate and removes the copy.
func _gate_with(plant: Callable) -> Dictionary:
	var sandbox := Sandbox.new()
	var before := sandbox.repo_status()
	var problem := sandbox.create()
	var result := {"code": -1, "output": ""}
	if problem == "":
		problem = plant.call(sandbox)
	if problem == "":
		result = sandbox.run_gate()
	assert_true(sandbox.destroy(), "the temp copy is removed")
	assert_eq(problem, "", "sandbox setup")
	assert_eq(sandbox.repo_status(), before, "the real repo is unchanged")
	return result


func _plant_nothing(_sandbox: Sandbox) -> String:
	return ""


## A Label script whose text literal is exactly `literal` in the file source.
func _plant_ui_literal(sandbox: Sandbox, literal: String) -> String:
	var source := 'extends Label\n\n\nfunc _ready() -> void:\n\ttext = "%s"\n' % literal
	return "" if sandbox.write_file(PLANTED_UI, source) else "could not write " + PLANTED_UI


func _plant_tutorial_line(sandbox: Sandbox, replacement: String) -> String:
	var page := sandbox.read_file(WEB_PAGE)
	var at := page.find(FIRST_TUTORIAL)
	if at < 0:
		return "first tutorial string not found in " + WEB_PAGE
	var line := page.count("\n", 0, at) + 1
	if line != FIRST_TUTORIAL_LINE:
		return "first tutorial string is on line %d" % line
	page = page.substr(0, at) + replacement + page.substr(at + FIRST_TUTORIAL.length())
	return "" if sandbox.write_file(WEB_PAGE, page) else "could not write " + WEB_PAGE


func test_clean_copy_passes() -> void:
	var result := _gate_with(_plant_nothing)
	assert_eq(result.code, 0, result.output)
	assert_string_contains(result.output, "term-gate: tracked player-facing content is clean")


func test_planted_boon_in_ui_string_fails() -> void:
	var word := "Bo" + "on"
	var result := _gate_with(_plant_ui_literal.bind("Choose a " + word))
	assert_eq(result.code, 1, result.output)
	assert_string_contains(result.output, PLANTED_UI)
	assert_string_contains(result.output, word)


func test_red_first_escaped_newline_boon_fails() -> void:
	var result := _gate_with(_plant_ui_literal.bind("Choose a\\n" + "Bo" + "on"))
	assert_eq(result.code, 1, result.output)


func test_red_first_escaped_tab_trial_fails() -> void:
	var result := _gate_with(_plant_ui_literal.bind("\\t" + "Tri" + "al"))
	assert_eq(result.code, 1, result.output)


func test_red_first_escaped_cr_lanternwake_fails() -> void:
	var result := _gate_with(_plant_ui_literal.bind("\\r" + "Lantern" + "wake"))
	assert_eq(result.code, 1, result.output)


func test_red_first_indirect_canvas_text_fails() -> void:
	var replacement := "'WALK TO A " + "BO" + "ON'"
	var result := _gate_with(_plant_tutorial_line.bind(replacement))
	assert_eq(result.code, 1, result.output)
	assert_string_contains(result.output, WEB_PAGE)
