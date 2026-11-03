extends GutTest
## Black-box tests of the real pack inspector and shell gate, without a release export.

const Sandbox := preload("res://test/helpers/export_pack_sandbox.gd")

var _sandbox: Sandbox


func before_each() -> void:
	_sandbox = Sandbox.new()
	assert_eq(_sandbox.create(), OK, "create an isolated fixture tree")


func after_each() -> void:
	assert_true(_sandbox.wrapper_scratch_is_empty(), "wrapper removes its own scratch on exit")
	assert_true(_sandbox.destroy(), "remove only the fixture tree created by this test")


func _run_pack(resources: Dictionary, project: String = Sandbox.PROJECT) -> Dictionary:
	assert_eq(_sandbox.pack("caller/fixture pack.pck", resources, project), OK, "make real PCK")
	# A relative path containing spaces also checks realpath before the wrapper changes --path.
	return _sandbox.run_gate(["fixture pack.pck"])


func _assert_rejected(result: Dictionary) -> void:
	# Timeout (124), launch errors and crashes must not masquerade as successful rejection tests.
	assert_eq(result.code, 1, result.output)


func test_clean_pack_lists_nested_hidden_and_similarly_named_allowed_resources() -> void:
	var resources := {
		"assets/nested/release.txt": "release",
		".root-hidden": "hidden",
		"assets/.hidden/.leaf": "hidden descendant",
		".godot/exported/release/game.gdc": "compiled payload",
		"test_helpers/allowed.txt": "not the test subtree",
		"addons/gut_extra/allowed.txt": "not the GUT subtree",
		"assets/test/allowed.txt": "not a root test subtree",
		"assets/addons/gut/allowed.txt": "not a root GUT subtree",
	}
	var result := _run_pack(resources)
	assert_eq(result.code, 0, result.output)
	for path: String in resources:
		assert_has(result.output.split("\n"), "res://" + path, "listed packed file " + path)
	assert_has(result.output.split("\n"), "res://project.godot")
	assert_has(result.output.split("\n"), "export-pack: passed (%d files)" % (resources.size() + 1))
	assert_false(result.output.contains("source_only"), "loose source/caller resources stay isolated")


func test_test_subtree_rejects_plain_remapped_and_hidden_resources() -> void:
	for path in ["test/unit/case.gd", "test/unit/case.gd.remap", "test/.hidden/.case"]:
		var result := _run_pack({path: "fixture"})
		_assert_rejected(result)
		assert_string_contains(result.output, "export-pack: forbidden resource: res://test/")
		assert_string_contains(result.output, "export-pack: rejected")
		assert_false(result.output.contains("export-pack: passed"), result.output)


func test_gut_subtree_rejects_plain_remapped_and_hidden_resources() -> void:
	for path in ["addons/gut/test.gd", "addons/gut/deep/test.gd.remap", "addons/gut/.hidden/.case"]:
		var result := _run_pack({path: "fixture"})
		_assert_rejected(result)
		assert_string_contains(result.output, "export-pack: forbidden resource: res://addons/gut/")
		assert_string_contains(result.output, "export-pack: rejected")
		assert_false(result.output.contains("export-pack: passed"), result.output)


func test_default_pack_path_is_resolved_from_wrapper_root() -> void:
	assert_eq(_sandbox.pack("source/build/linux/lowtide-vigil.pck", {"assets/release.txt": "ok"}), OK)
	var result := _sandbox.run_gate()
	assert_eq(result.code, 0, result.output)
	assert_string_contains(result.output, "export-pack: passed (2 files)")


func test_missing_empty_and_corrupt_packs_fail_closed() -> void:
	_assert_rejected(_sandbox.run_gate(["absent.pck"]))
	assert_eq(_sandbox.write("caller/empty.pck", ""), OK)
	_assert_rejected(_sandbox.run_gate(["empty.pck"]))
	assert_eq(_sandbox.write("caller/corrupt.pck", "not a Godot pack"), OK)
	var corrupt := _sandbox.run_gate(["corrupt.pck"])
	_assert_rejected(corrupt)
	# Godot may fall back to the scratch filesystem and the inspector may print a pass;
	# the wrapper must reject the pack-load error regardless.
	assert_string_contains(corrupt.output, "ERROR:")


func test_missing_default_pack_does_not_fall_back_to_loose_source() -> void:
	_assert_rejected(_sandbox.run_gate())


func test_real_engine_startup_errors_reject_even_when_inspector_reports_success() -> void:
	# The inspector only lists files. Godot reports the missing autoload independently;
	# its zero exit and the inspector's pass marker must not mask that engine error.
	var project := Sandbox.PROJECT + '[autoload]\nbroken="*res://absent.gd"\n'
	var result := _run_pack({"assets/release.txt": "ok"}, project)
	assert_eq(result.code, 1, result.output)
	assert_string_contains(result.output, "ERROR:")
	assert_string_contains(result.output, "export-pack: passed (2 files)")


func test_linux_preset_exclusion_contract() -> void:
	var presets := ConfigFile.new()
	assert_eq(presets.load("res://export_presets.cfg"), OK)
	assert_eq(presets.get_value("preset.0", "name"), "Linux/X11")
	assert_eq(presets.get_value("preset.0", "export_filter"), "all_resources")
	assert_eq(presets.get_value("preset.0", "export_path"), "build/linux/lowtide-vigil.x86_64")
	assert_false(presets.get_value("preset.0.options", "binary_format/embed_pck"))
	var patterns: String = presets.get_value("preset.0", "exclude_filter")
	# Exercise the configured wildcard contract, including descendants and remap sidecars.
	for path in [
		"test/unit/case.gd", "test/helpers/helper.gd", "test/term_gate/case.gd",
		"test/unit/case.gd.remap", "test/.hidden/.case",
		"addons/gut/test.gd", "addons/gut/deep/test.gd.remap", "addons/gut/.hidden/.case",
		"web/page.html", "docs/notes.md", "tools/check-export.gd", ".github/workflows/ci.yml",
	]:
		assert_true(_matches_any(path, patterns), "preset excludes " + path)
	for path in ["scenes/vigil.tscn", "scripts/vigil.gd", "assets/fonts/pixel/OFL.txt"]:
		assert_false(_matches_any(path, patterns), "preset retains " + path)
	assert_true(_matches_any(
		"assets/fonts/pixel/OFL.txt", presets.get_value("preset.0", "include_filter")
	), "font license stays included")


func _matches_any(path: String, patterns: String) -> bool:
	for pattern in patterns.split(",", false):
		if path.match(pattern.strip_edges()):
			return true
	return false
