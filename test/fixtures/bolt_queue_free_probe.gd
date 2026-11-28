extends SceneTree
## A real bolt is the only node that can be queued during each measured interval.

const VIGIL = preload("res://scenes/vigil.tscn")
const SCENARIOS := ["lifetime-friendly", "lifetime-hostile", "bounds-friendly", "bounds-hostile"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for scenario in SCENARIOS:
		var game: Node2D = VIGIL.instantiate()
		root.add_child(game)
		game.set_process(false)
		game._start_run()
		game._clear_room()
		# Flush setup deletion before profiling. There are no foes or other bolts.
		await process_frame
		var origin := Vector2(1214, 400) if scenario.begins_with("bounds") else Vector2(640, 400)
		game._make_bolt(origin, Vector2.RIGHT, 20.0, scenario.ends_with("hostile"), 1.0)
		var bolt: VigilBolt = game.bolts.back()
		if scenario.begins_with("lifetime"):
			bolt.lifetime = 0.05
		EngineDebugger.send_message("bolt_count:case", [scenario + ".step"])
		EngineDebugger.profiler_enable("servers", true, [4096, true])
		bolt.step(0.05)
		EngineDebugger.profiler_enable("servers", false)
		EngineDebugger.send_message("bolt_count:case", [scenario + ".owner"])
		EngineDebugger.profiler_enable("servers", true, [4096, true])
		game._step_bolts(0.0)
		game._step_bolts(0.1)
		EngineDebugger.profiler_enable("servers", false)
		var remaining: int = game.bolts.size()
		var queued := bolt.is_queued_for_deletion()
		await process_frame
		EngineDebugger.send_message(
			"bolt_count:lifecycle", [scenario, remaining, queued, not is_instance_valid(bolt)]
		)
		game.free()
	EngineDebugger.send_message("bolt_count:done", [])
	quit()
