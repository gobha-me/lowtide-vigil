extends GutTest
## Exercise the real browser script, with browser services supplied by Node fixtures.


func test_browser_start_edges_across_menu_and_gameplay_polling() -> void:
	var output := []
	var code := OS.execute(
		"node",
		[
			ProjectSettings.globalize_path("res://test/helpers/browser_pad_harness.cjs"),
			ProjectSettings.globalize_path("res://web/lowtide-vigil.html"),
		],
		output,
		true
	)
	var log := "" if output.is_empty() else str(output[0])
	assert_eq(code, 0, "Browser pad regression harness (requires Node.js):\n" + log)
	assert_true(log.contains("BROWSER PAD: passed (8 cases)"), log)
