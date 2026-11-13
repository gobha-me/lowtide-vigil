extends GutTest
## Black-box shell protocol tests; these executables never establish gameplay acceptance.

const Sandbox = preload("res://test/helpers/desktop_wrapper_sandbox.gd")
const MARKERS := [
	"DESKTOP ACCEPTANCE: F11 press/echo/release 1",
	"DESKTOP ACCEPTANCE: F11 press/echo/release 2",
	"DESKTOP ACCEPTANCE: joypad sticks/release",
	"DESKTOP ACCEPTANCE: passed",
	"DESKTOP ACCEPTANCE: keyboard controls/back",
	"DESKTOP ACCEPTANCE: keyboard pause/resume",
	"DESKTOP ACCEPTANCE: keyboard restart",
	"DESKTOP ACCEPTANCE: keyboard lost fixture/shore",
	"DESKTOP ACCEPTANCE: keyboard won fixture/shore",
	"DESKTOP ACCEPTANCE: joypad controls/back",
	"DESKTOP ACCEPTANCE: joypad pause/resume",
	"DESKTOP ACCEPTANCE: joypad restart",
	"DESKTOP ACCEPTANCE: joypad lost fixture/shore",
	"DESKTOP ACCEPTANCE: joypad won fixture/shore",
]

var sandbox: RefCounted


func before_each() -> void:
	sandbox = Sandbox.new()


func after_each() -> void:
	assert_true(
		sandbox.destroy(), "remove only this test's owned tree after checking retained logs"
	)


func test_exact_marker_set_preserves_copies_isolation_provenance_and_both_runs() -> void:
	if not _create():
		return
	var result: Dictionary = sandbox.run()
	assert_eq(result.code, 0, result.output)
	assert_has(result.output.split("\n"), "desktop-acceptance: passed")
	assert_eq(sandbox.read("calls"), "startup\nacceptance\n")
	_assert_evidence()
	assert_string_contains(sandbox.read_evidence("startup.log"), "PROTOCOL FIXTURE: startup")
	var lines: PackedStringArray = sandbox.read_evidence("acceptance.log").split("\n")
	for marker: String in MARKERS:
		assert_has(lines, marker)
	assert_eq(
		sandbox.read_evidence("override.cfg"),
		(
			'[autoload]\nDesktopAcceptance="*'
			+ sandbox.root.path_join("tools/desktop-acceptance.gd")
			+ '"\n'
		)
	)
	for directory in ["cache", "data", "config"]:
		for phase in ["startup", "acceptance"]:
			assert_eq(sandbox.read_evidence(directory + "/" + phase + ".sentinel"), phase)
		assert_false(FileAccess.file_exists(sandbox.root.path_join("caller/" + directory)))
	var first: String = sandbox.evidence
	var first_log: String = sandbox.read_evidence("acceptance.log")
	result = sandbox.run()
	assert_eq(result.code, 0, result.output)
	assert_ne(sandbox.evidence, first, "each invocation receives a unique evidence directory")
	assert_eq(FileAccess.get_file_as_string(first.path_join("acceptance.log")), first_log)
	_assert_evidence()


func test_required_artifacts_fail_before_scratch_or_child_process(
	path = use_parameters(
		["export/input build.x86_64", "export/input build.pck", "tools/desktop-acceptance.gd"]
	)
) -> void:
	if not _create():
		return
	assert_eq(sandbox.remove(path), OK)
	_assert_preflight_rejected(sandbox.run())


func test_empty_pack_or_nonexecutable_binary_is_rejected(
	artifact = use_parameters(["pack", "binary"])
) -> void:
	if not _create():
		return
	if artifact == "pack":
		assert_true(sandbox.write("export/input build.pck", ""))
	else:
		assert_eq(
			OS.execute("chmod", ["-x", sandbox.root.path_join("export/input build.x86_64")]), 0
		)
	_assert_preflight_rejected(sandbox.run())


func test_extra_arguments_fail_usage_before_any_child_process() -> void:
	if not _create():
		return
	var result: Dictionary = sandbox.run(["unused", "unexpected"])
	assert_eq(result.code, 2, result.output)
	assert_string_contains(result.output, "usage:")
	assert_eq(sandbox.evidence, "")
	assert_eq(sandbox.read("calls"), "")


func test_nonzero_exit_cannot_pass_even_after_all_success_markers(
	phase = use_parameters(["startup", "acceptance"])
) -> void:
	if not _create({phase + "_status": 7, phase + "_output": "\n".join(MARKERS)}):
		return
	var result: Dictionary = sandbox.run()
	_assert_rejected(result, "exported process failed (7)")
	assert_string_contains(sandbox.read_evidence(phase + ".log"), MARKERS[3])
	_assert_stopped_at(phase)
	_assert_evidence()


func test_engine_and_script_errors_in_either_phase_override_success(
	case = use_parameters(
		[
			["startup", "ERROR: boot failure"],
			["startup", "SCRIPT ERROR: boot script failure"],
			["acceptance", "ERROR: traversal failure"],
			["acceptance", "SCRIPT ERROR: traversal script failure"],
			["startup", "  ERROR: indented failure"],
			["acceptance", "  SCRIPT ERROR: indented failure"],
		]
	)
) -> void:
	var phase: String = case[0]
	var content: String = "\n".join(MARKERS) + "\n" + case[1]
	if not _create({phase + "_output": content}):
		return
	_assert_rejected(sandbox.run(), "engine errors")
	assert_string_contains(sandbox.read_evidence(phase + ".log"), case[1])
	_assert_stopped_at(phase)
	_assert_evidence()


func test_each_marker_must_be_an_exact_line_in_traversal_log(
	marker = use_parameters(MARKERS)
) -> void:
	# Every final and per-path marker is independently omitted, truncated and surrounded.
	for replacement: String in [
		"", marker.left(marker.length() - 1), "prefix " + marker, marker + " suffix"
	]:
		var lines: Array = MARKERS.duplicate()
		lines[lines.find(marker)] = replacement
		if not _create(
			{"startup_output": "\n".join(MARKERS), "acceptance_output": "\n".join(lines)}
		):
			return
		_assert_rejected(sandbox.run(), "missing marker '" + marker + "'")
		assert_false(sandbox.read_evidence("acceptance.log").split("\n").has(marker))
		_assert_stopped_at("acceptance")
		_assert_evidence()
		assert_true(sandbox.destroy())


func test_each_phase_has_the_production_timeout_and_cannot_pass_after_markers(
	phase = use_parameters(["startup", "acceptance"])
) -> void:
	# Reuse the existing boundary clock shim: verify 60s/TERM/5s, then real GNU timeout.
	if not _create({phase + "_hang": true, phase + "_output": "\n".join(MARKERS)}, true):
		return
	var started := Time.get_ticks_msec()
	_assert_rejected(sandbox.run(), "exported process failed (124)")
	assert_lt(Time.get_ticks_msec() - started, 4000)
	assert_string_contains(sandbox.read_evidence(phase + ".log"), MARKERS[3])
	var count := 1 if phase == "startup" else 2
	assert_eq(sandbox.read("timeout-calls"), "--signal=TERM --kill-after=5s 60s\n".repeat(count))
	_assert_stopped_at(phase)
	_assert_evidence()


func _create(settings: Dictionary = {}, accelerated_timeout: bool = false) -> bool:
	var created: bool = sandbox.create(settings, accelerated_timeout)
	assert_true(created, "create the wrapper's isolated protocol sandbox")
	return created


func _assert_preflight_rejected(result: Dictionary) -> void:
	_assert_rejected(result, "required")
	assert_eq(sandbox.evidence, "", "artifact checks precede scratch allocation")
	assert_eq(sandbox.read("calls"), "", "artifact checks precede child launch")
	assert_true(DirAccess.get_directories_at(sandbox.root.path_join("runs")).is_empty())


func _assert_rejected(result: Dictionary, diagnostic: String) -> void:
	assert_eq(result.code, 1, result.output)
	assert_string_contains(result.output, diagnostic)
	assert_false(result.output.split("\n").has("desktop-acceptance: passed"))


func _assert_stopped_at(phase: String) -> void:
	var expected := "startup\n" if phase == "startup" else "startup\nacceptance\n"
	assert_eq(sandbox.read("calls"), expected)
	if phase == "startup":
		assert_false(FileAccess.file_exists(sandbox.evidence.path_join("acceptance.log")))
		assert_false(FileAccess.file_exists(sandbox.evidence.path_join("override.cfg")))


func _assert_evidence() -> void:
	assert_true(sandbox.evidence.begins_with(sandbox.root.path_join("runs") + "/"))
	assert_true(sandbox.originals_unchanged())
	assert_eq(
		FileAccess.get_sha256(sandbox.evidence.path_join("lowtide-vigil.x86_64")),
		sandbox.binary_hash
	)
	assert_eq(
		FileAccess.get_sha256(sandbox.evidence.path_join("lowtide-vigil.pck")), sandbox.pack_hash
	)
	var provenance: String = sandbox.read_evidence("provenance.log")
	var lines := provenance.split("\n", false)
	assert_eq(lines.size(), 5, provenance)
	if lines.size() != 5:
		return
	var utc := RegEx.new()
	assert_eq(utc.compile("^UTC: [0-9]{4}(-[0-9]{2}){2}T[0-9]{2}(:[0-9]{2}){2}Z$"), OK)
	assert_not_null(utc.search(lines[0]))
	assert_eq(lines[1], sandbox.checkout_head)
	assert_eq(
		lines[2], sandbox.binary_hash + "  " + sandbox.root.path_join("export/input build.x86_64")
	)
	assert_eq(lines[3], sandbox.pack_hash + "  " + sandbox.root.path_join("export/input build.pck"))
	assert_eq(
		lines[4], sandbox.driver_hash + "  " + sandbox.root.path_join("tools/desktop-acceptance.gd")
	)
