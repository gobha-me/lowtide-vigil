extends RefCounted
## The actual shell wrapper runs copied executables in disposable directories.

var root := ""
var evidence := ""
var binary_hash := ""
var pack_hash := ""


func create(settings: Dictionary = {}) -> bool:
	var unique := "winning-wrapper-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	root = OS.get_environment("TMPDIR").path_join(unique)
	if not root.is_absolute_path():
		root = OS.get_temp_dir().path_join(unique)
	for directory in ["tools", "export", "runs"]:
		if DirAccess.make_dir_recursive_absolute(root.path_join(directory)) != OK:
			return false
	var repo := ProjectSettings.globalize_path("res://")
	for pair in [
		["tools/winning-playthrough.sh", "tools/winning-playthrough.sh"],
		["test/helpers/winning_export_fixture.py", "export/game.x86_64"],
	]:
		if DirAccess.copy_absolute(repo.path_join(pair[0]), root.path_join(pair[1])) != OK:
			return false
	settings = settings.duplicate()
	settings.original = root.path_join("export")
	settings.driver = root.path_join("tools/winning-playthrough.gd")
	write("export/game.pck", JSON.stringify(settings))
	write("tools/winning-playthrough.gd", "extends Node\n")
	if OS.execute("chmod", ["+x", root.path_join("export/game.x86_64")]) != 0:
		return false
	binary_hash = FileAccess.get_sha256(root.path_join("export/game.x86_64"))
	pack_hash = FileAccess.get_sha256(root.path_join("export/game.pck"))
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
			"timeout",
			[
				"--kill-after=2s",
				"15s",
				"env",
				"TMPDIR=" + root.path_join("runs"),
				"bash",
				root.path_join("tools/winning-playthrough.sh"),
				root.path_join("export/game.x86_64"),
			],
			output,
			true
		)
	)
	var log := "" if output.is_empty() else str(output[0])
	for line in log.split("\n"):
		if line.begins_with("winning-playthrough: evidence "):
			evidence = line.trim_prefix("winning-playthrough: evidence ")
	return {"code": code, "output": log}


func read_evidence(path: String) -> String:
	return FileAccess.get_file_as_string(evidence.path_join(path))


func originals_unchanged() -> bool:
	return (
		FileAccess.get_sha256(root.path_join("export/game.x86_64")) == binary_hash
		and FileAccess.get_sha256(root.path_join("export/game.pck")) == pack_hash
		and not FileAccess.file_exists(root.path_join("export/override.cfg"))
		and not FileAccess.file_exists(root.path_join("tools/override.cfg"))
	)


func destroy() -> void:
	if root != "" and root.get_file().begins_with("winning-wrapper-"):
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
