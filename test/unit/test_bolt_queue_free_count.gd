extends GutTest
## Native profiling observes real calls, including Godot's typed native dispatch.

const PROBE = preload("res://test/fixtures/bolt_queue_free_probe.gd")
const DEADLINE_MS := 30000


func _calls(data: Array, signatures: Dictionary) -> int:
	# Cumulative ServersProfilerFrame: six metrics, zero servers, then 5-field records.
	if data.size() < 8 or data[6] != 0 or data[7] % 5 != 0 or data.size() != 8 + data[7]:
		fail_test("malformed native profiler total")
		return -1
	var count := 0
	for index in range(8, data.size(), 5):
		if not signatures.has(data[index]):
			fail_test("native profiler total has an unknown function signature")
			return -1
		if signatures[data[index]].ends_with(".queue_free"):
			count += int(data[index + 1])
	return count


func test_real_bolt_retirement_calls_queue_free_exactly_once() -> void:
	var server := TCPServer.new()
	var listen_result := server.listen(0, "127.0.0.1")
	assert_eq(listen_result, OK, "the native profiler observer must start")
	if listen_result != OK:
		return
	var pid := (
		OS
		. create_process(
			OS.get_executable_path(),
			[
				"--headless",
				"--path",
				ProjectSettings.globalize_path("res://"),
				"--remote-debug",
				"tcp://127.0.0.1:%s" % server.get_local_port(),
				"--script",
				"res://test/fixtures/bolt_queue_free_probe.gd",
			]
		)
	)
	assert_gt(pid, 0, "the real-unit fixture must start")
	if pid <= 0:
		server.stop()
		return
	var peer := PacketPeerStream.new()
	var connection: StreamPeerTCP
	var signatures := {}
	var counts := {}
	var lifecycle := {}
	var current_case := ""
	var finished := false
	var deadline := Time.get_ticks_msec() + DEADLINE_MS
	while not finished and Time.get_ticks_msec() < deadline:
		if connection == null and server.is_connection_available():
			connection = server.take_connection()
			peer.stream_peer = connection
		if connection != null:
			connection.poll()
			while peer.get_available_packet_count() > 0:
				var message: Variant = peer.get_var()
				if not message is Array or message.size() != 3 or not message[2] is Array:
					fail_test("malformed native profiler message")
					finished = true
					break
				var data: Array = message[2]
				match message[0]:
					"bolt_count:case":
						current_case = data[0]
						signatures.clear()
					"servers:function_signature":
						signatures[data[1]] = data[0]
					"servers:profile_total":
						counts[current_case] = _calls(data, signatures)
					"bolt_count:lifecycle":
						lifecycle[data[0]] = data.slice(1)
					"bolt_count:done":
						finished = true
					"error":
						# Godot also sends existing parser warnings as "error" packets.
						if data.size() < 10 or not data[9]:
							fail_test("real-unit fixture reported an engine error: %s" % [data])
							finished = true
					"debug_enter":
						fail_test("real-unit fixture reported an engine error: %s" % [data])
						finished = true
		await get_tree().process_frame
	assert_true(finished, "native observation must finish within 30 seconds")
	# The child exits itself; only the exact process we created can be stopped on failure.
	var exit_deadline := Time.get_ticks_msec() + 1000
	while OS.is_process_running(pid) and Time.get_ticks_msec() < exit_deadline:
		await get_tree().process_frame
	if OS.is_process_running(pid):
		OS.kill(pid)
		fail_test("real-unit fixture did not exit")
		var stop_deadline := Time.get_ticks_msec() + 1000
		while OS.is_process_running(pid) and Time.get_ticks_msec() < stop_deadline:
			await get_tree().process_frame
		assert_false(OS.is_process_running(pid), "the exact fixture process must stop")
	server.stop()
	for scenario in PROBE.SCENARIOS:
		assert_eq(counts.get(scenario + ".step", -1), 0, scenario + ": bolt must not self-queue")
		assert_eq(
			counts.get(scenario + ".owner", -1),
			1,
			scenario + ": Vigil must literally call queue_free exactly once per retired bolt"
		)
		assert_eq(
			lifecycle.get(scenario, []), [0, true, true], scenario + ": removed, queued, freed"
		)
