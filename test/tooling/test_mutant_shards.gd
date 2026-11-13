extends GutTest
## Fixture inputs exercise the real checker and runner option validation.


func test_catalog_shard_checker_rejects_incomplete_or_invalid_evidence() -> void:
	var output := []
	var status := (
		OS
		. execute(
			"/usr/bin/timeout",
			[
				"--kill-after=5s",
				"60s",
				"python3",
				ProjectSettings.globalize_path("res://test/tooling/test_mutant_shards.py"),
				"-v",
			],
			output,
			true
		)
	)
	var log := "" if output.is_empty() else str(output[0])
	assert_eq(status, 0, log)
	assert_string_contains(log, "OK")


func test_runner_options_reject_invalid_inputs_before_mutations() -> void:
	var output := []
	var status := (
		OS
		. execute(
			"/usr/bin/timeout",
			[
				"--kill-after=5s",
				"60s",
				"python3",
				ProjectSettings.globalize_path("res://test/tooling/test_mutant_runner.py"),
				"RunnerOptionsTests",
				"-v",
			],
			output,
			true
		)
	)
	var log := "" if output.is_empty() else str(output[0])
	assert_eq(status, 0, log)
	assert_string_contains(log, "OK")
