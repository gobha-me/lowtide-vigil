extends "res://addons/gut/hook_script.gd"
## Enforce the CI result policy through GUT's own process exit code.


func run() -> void:
	var totals: Dictionary = gut.get_summary().get_totals()
	if (
		totals.tests == 0
		or totals.failing > 0
		or totals.failing_tests > 0
		or totals.pending > 0
		or totals.risky > 0
		or totals.orphans > 0
		or totals.errors > 0
	):
		print("GUT CI: failed: ", totals)
		set_exit_code(1)
		return
	# Leave GUT's native failure exit code intact; only override to reject a run.
	print("GUT CI: passed")
