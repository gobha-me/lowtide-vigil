extends RefCounted
## Copy the real wrapper; only its process protocol is replaced by fixtures.

var root := ""
var evidence := ""
var binary_hash := ""
var pack_hash := ""


func create(settings: Dictionary = {}, accelerated_timeout: bool = false) -> bool:
	root = OS.get_temp_dir().path_join(
		"smoke-wrapper-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	)
	for directory in ["tools", "build/linux", "runs", "bin"]:
		if DirAccess.make_dir_recursive_absolute(root.path_join(directory)) != OK:
			return false
	var copies := [
		["tools/export-smoke.sh", "tools/export-smoke.sh"],
		["test/helpers/smoke_export_fixture.py", "build/linux/lowtide-vigil.x86_64"],
	]
	if accelerated_timeout:
		copies.append(["test/helpers/smoke_timeout_fixture.py", "bin/timeout"])
	for pair in copies:
		if (
			DirAccess.copy_absolute(
				ProjectSettings.globalize_path("res://" + pair[0]), root.path_join(pair[1])
			)
			!= OK
		):
			return false
		if OS.execute("chmod", ["+x", root.path_join(pair[1])]) != 0:
			return false
	write("build/linux/lowtide-vigil.pck", JSON.stringify(settings))
	binary_hash = FileAccess.get_sha256(root.path_join("build/linux/lowtide-vigil.x86_64"))
	pack_hash = FileAccess.get_sha256(root.path_join("build/linux/lowtide-vigil.pck"))
	return true


func write(path: String, content: String) -> void:
	var file := FileAccess.open(root.path_join(path), FileAccess.WRITE)
	file.store_string(content)


func remove(path: String) -> void:
	DirAccess.remove_absolute(root.path_join(path))


func run() -> Dictionary:
	var output := []
	var code := (
		OS
		. execute(
			"/usr/bin/timeout",
			[
				"--kill-after=1s",
				"5s",
				"env",
				"PATH=" + root.path_join("bin") + ":" + OS.get_environment("PATH"),
				"M2_SCRATCH=" + root.path_join("runs"),
				"bash",
				root.path_join("tools/export-smoke.sh"),
			],
			output,
			true
		)
	)
	var log := "" if output.is_empty() else str(output[0])
	for line in log.split("\n"):
		if line.begins_with("Export smoke logs: "):
			evidence = line.trim_prefix("Export smoke logs: ")
	return {"code": code, "output": log}


func read(path: String) -> String:
	var full := root.path_join(path)
	return FileAccess.get_file_as_string(full) if FileAccess.file_exists(full) else ""


func read_log(phase: String) -> String:
	var path := evidence.path_join(phase + ".log")
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func originals_unchanged() -> bool:
	return (
		FileAccess.get_sha256(root.path_join("build/linux/lowtide-vigil.x86_64")) == binary_hash
		and FileAccess.get_sha256(root.path_join("build/linux/lowtide-vigil.pck")) == pack_hash
	)


func destroy() -> void:
	if root.get_file().begins_with("smoke-wrapper-"):
		_remove_tree(root)


func _remove_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for child in directory.get_directories():
		_remove_tree(path.path_join(child))
	for child in directory.get_files():
		DirAccess.remove_absolute(path.path_join(child))
	DirAccess.remove_absolute(path)
