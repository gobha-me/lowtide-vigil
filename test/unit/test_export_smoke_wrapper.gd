extends GutTest
## Execute the real shell gate against isolated child-process protocol fixtures.

const Sandbox = preload("res://test/helpers/smoke_wrapper_sandbox.gd")
const MARKER := "EXPORT SMOKE: passed"
var sandbox: RefCounted


func before_each() -> void:
	sandbox = Sandbox.new()


func after_each() -> void:
	sandbox.destroy()


func test_success_requires_ordinary_boot_then_menus_and_preserves_logs_and_artifacts() -> void:
	assert_true(sandbox.create())
	var result: Dictionary = sandbox.run()
	assert_eq(result.code, 0, result.output)
	assert_string_contains(result.output, "Linux export smoke: passed")
	assert_eq(sandbox.read("calls"), "boot\nmenus\n")
	assert_string_contains(sandbox.read_log("boot"), "PROTOCOL FIXTURE: boot")
	assert_string_contains(sandbox.read_log("menus"), MARKER)
	assert_true(sandbox.originals_unchanged())
	var first: String = sandbox.evidence
	result = sandbox.run()
	assert_eq(result.code, 0, result.output)
	assert_ne(sandbox.evidence, first)
	assert_true(FileAccess.file_exists(first.path_join("menus.log")))


func test_missing_artifacts_fail_before_running_any_process(
	path = use_parameters(["build/linux/lowtide-vigil.x86_64", "build/linux/lowtide-vigil.pck"])
) -> void:
	assert_true(sandbox.create())
	sandbox.remove(path)
	var result: Dictionary = sandbox.run()
	assert_ne(result.code, 0, result.output)
	assert_eq(sandbox.read("calls"), "")
	assert_eq(sandbox.evidence, "")


func test_empty_pack_and_nonexecutable_binary_fail_closed(
	artifact = use_parameters(["pack", "binary"])
) -> void:
	assert_true(sandbox.create())
	if artifact == "pack":
		sandbox.write("build/linux/lowtide-vigil.pck", "")
	else:
		assert_eq(
			OS.execute("chmod", ["-x", sandbox.root.path_join("build/linux/lowtide-vigil.x86_64")]),
			0
		)
	var result: Dictionary = sandbox.run()
	assert_ne(result.code, 0, result.output)
	assert_eq(sandbox.read("calls"), "")
	assert_eq(sandbox.evidence, "")


func test_nonzero_exit_even_with_marker_fails(phase = use_parameters(["boot", "menus"])) -> void:
	assert_true(sandbox.create({phase + "_output": MARKER, phase + "_status": 7}))
	var result: Dictionary = sandbox.run()
	assert_eq(result.code, 7, result.output)
	assert_string_contains(result.output, "Export smoke " + phase + " exited 7")
	assert_false(result.output.contains("Linux export smoke: passed"))
	assert_string_contains(sandbox.read_log(phase), MARKER)
	if phase == "boot":
		assert_eq(sandbox.read("calls"), "boot\n")
	assert_true(sandbox.originals_unchanged())


func test_engine_and_script_errors_fail_even_with_marker(
	case = use_parameters(
		[
			["boot", "ERROR: boot failure"],
			["boot", "SCRIPT ERROR: boot script failure"],
			["menus", "ERROR: menu failure"],
			["menus", "SCRIPT ERROR: menu script failure"],
			["boot", "  ERROR: indented boot failure"],
			["menus", "  SCRIPT ERROR: indented menu failure"],
		]
	)
) -> void:
	var phase: String = case[0]
	assert_true(sandbox.create({phase + "_output": MARKER + "\n" + case[1]}))
	var result: Dictionary = sandbox.run()
	assert_ne(result.code, 0, result.output)
	assert_string_contains(result.output, "contains Godot errors")
	assert_false(result.output.contains("Linux export smoke: passed"))
	assert_string_contains(sandbox.read_log(phase), case[1])
	if phase == "boot":
		assert_eq(sandbox.read("calls"), "boot\n")


func test_missing_partial_embedded_or_boot_only_marker_is_rejected(
	marker = use_parameters(
		["", "EXPORT SMOKE: pass", "prefix EXPORT SMOKE: passed", "EXPORT SMOKE: passed suffix"]
	)
) -> void:
	assert_true(sandbox.create({"boot_output": MARKER, "menus_output": marker}))
	var result: Dictionary = sandbox.run()
	assert_ne(result.code, 0, result.output)
	assert_false(result.output.contains("Linux export smoke: passed"))
	assert_eq(sandbox.read("calls"), "boot\nmenus\n")


func test_each_process_is_bounded_and_timeout_cannot_pass_with_marker(
	phase = use_parameters(["boot", "menus"])
) -> void:
	# A protocol-only clock shim validates 60s/TERM/5s then delegates to real GNU timeout.
	assert_true(sandbox.create({phase + "_hang": true, phase + "_output": MARKER}, true))
	var started := Time.get_ticks_msec()
	var result: Dictionary = sandbox.run()
	assert_eq(result.code, 124, result.output)
	assert_lt(Time.get_ticks_msec() - started, 4000)
	assert_string_contains(result.output, "Export smoke " + phase + " exited 124")
	assert_false(result.output.contains("Linux export smoke: passed"))
	assert_string_contains(sandbox.read_log(phase), MARKER)
	var count := 1 if phase == "boot" else 2
	assert_eq(sandbox.read("timeout-calls"), "--signal=TERM --kill-after=5s 60s\n".repeat(count))
