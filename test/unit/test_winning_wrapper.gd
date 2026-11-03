extends GutTest
## Contract fixtures exercise the real wrapper; only exported runs prove gameplay wins.

const Sandbox = preload("res://test/helpers/winning_wrapper_sandbox.gd")
const MARKER := "WINNING PLAYTHROUGH: passed"

var sandbox: RefCounted


func before_each() -> void:
	sandbox = Sandbox.new()


func after_each() -> void:
	sandbox.destroy()


func test_success_retains_isolated_logs_config_and_unchanged_artifacts() -> void:
	assert_true(sandbox.create())
	var result: Dictionary = sandbox.run()
	assert_eq(result.code, 0, result.output)
	assert_true(result.output.contains("winning-playthrough: passed"))
	assert_true(sandbox.originals_unchanged())
	assert_true(sandbox.evidence.begins_with(sandbox.root.path_join("runs") + "/"))
	assert_true(sandbox.read_evidence("startup.log").contains("PROTOCOL FIXTURE: startup"))
	assert_true(sandbox.read_evidence("playthrough.log").contains(MARKER))
	var config: String = sandbox.read_evidence("override.cfg")
	assert_true(config.begins_with('[autoload]\nWinningPlaythrough="*'))
	assert_true(config.contains(sandbox.root.path_join("tools/winning-playthrough.gd")))
	assert_eq(
		FileAccess.get_sha256(sandbox.evidence.path_join("lowtide-vigil.x86_64")),
		sandbox.binary_hash
	)
	assert_eq(
		FileAccess.get_sha256(sandbox.evidence.path_join("lowtide-vigil.pck")), sandbox.pack_hash
	)
	# A second invocation keeps the first log and creates a separate config/copy.
	var first_evidence: String = sandbox.evidence
	result = sandbox.run()
	assert_eq(result.code, 0, result.output)
	assert_ne(sandbox.evidence, first_evidence)
	assert_true(FileAccess.file_exists(first_evidence.path_join("playthrough.log")))
	assert_true(sandbox.originals_unchanged())


func test_required_artifacts_are_checked(
	path = use_parameters(["export/game.x86_64", "export/game.pck", "tools/winning-playthrough.gd"])
) -> void:
	assert_true(sandbox.create())
	sandbox.remove(path)
	var result: Dictionary = sandbox.run()
	assert_ne(result.code, 0, result.output)
	assert_true(result.output.contains("required"), result.output)
	assert_eq(sandbox.evidence, "", "must reject before creating scratch or running a child")


func test_empty_pack_is_rejected() -> void:
	assert_true(sandbox.create())
	sandbox.write("export/game.pck", "")
	var result: Dictionary = sandbox.run()
	assert_ne(result.code, 0, result.output)
	assert_true(result.output.contains("required"), result.output)


func test_nonzero_child_even_with_marker_is_rejected(
	phase = use_parameters(["startup", "playthrough"])
) -> void:
	assert_true(sandbox.create({phase + "_status": 7, phase + "_output": MARKER}))
	var result: Dictionary = sandbox.run()
	assert_ne(result.code, 0, result.output)
	assert_true(result.output.contains("exported process failed (7)"), result.output)
	assert_false(result.output.contains("winning-playthrough: passed"))
	assert_true(sandbox.read_evidence(phase + ".log").contains(MARKER))
	assert_true(sandbox.originals_unchanged())


func test_engine_errors_even_with_marker_are_rejected(
	case = use_parameters(
		[
			["startup", "ERROR: startup failure"],
			["startup", "SCRIPT ERROR: startup failure"],
			["playthrough", "ERROR: combat failure"],
			["playthrough", "SCRIPT ERROR: controller failure"],
			["playthrough", "  ERROR: indented engine failure"],
		]
	)
) -> void:
	var phase: String = case[0]
	assert_true(sandbox.create({phase + "_output": MARKER + "\n" + case[1]}))
	var result: Dictionary = sandbox.run()
	assert_ne(result.code, 0, result.output)
	assert_true(result.output.contains("engine errors"), result.output)
	assert_false(result.output.contains("winning-playthrough: passed"))
	assert_true(sandbox.read_evidence(phase + ".log").contains(case[1]))
	if phase == "startup":
		assert_false(FileAccess.file_exists(sandbox.evidence.path_join("override.cfg")))
		assert_false(FileAccess.file_exists(sandbox.evidence.path_join("playthrough.log")))
	assert_true(sandbox.originals_unchanged())


func test_missing_partial_or_surrounded_marker_is_rejected(
	marker = use_parameters(
		[
			"",
			"PLAYTHROUGH PASS frame=2680 hp=3",
			"WINNING PLAYTHROUGH: pass",
			"prefix WINNING PLAYTHROUGH: passed",
			"WINNING PLAYTHROUGH: passed suffix",
		]
	)
) -> void:
	assert_true(sandbox.create({"startup_output": MARKER, "playthrough_output": marker}))
	var result: Dictionary = sandbox.run()
	assert_ne(result.code, 0, result.output)
	assert_true(result.output.contains("missing victory marker"), result.output)
	assert_false(result.output.contains("winning-playthrough: passed"))
	assert_true(sandbox.originals_unchanged())
