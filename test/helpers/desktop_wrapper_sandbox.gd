extends RefCounted
## Copy the actual wrapper and driver; replace only the export process boundary.

var root := ""
var evidence := ""
var binary_hash := ""
var pack_hash := ""
var driver_hash := ""
var checkout_head := ""


func create(settings: Dictionary = {}, accelerated_timeout: bool = false) -> bool:
	if not _create_tree():
		return false
	if not _copy_artifacts(accelerated_timeout):
		return false
	settings = settings.duplicate()
	settings.original = root.path_join("export")
	settings.driver = root.path_join("tools/desktop-acceptance.gd")
	settings.sandbox = root
	if not write("export/input build.pck", JSON.stringify(settings)):
		return false
	for path in ["override.cfg", "export/override.cfg", "caller/override.cfg"]:
		if not write(path, "original override sentinel\n"):
			return false
	var output := []
	if OS.execute("git", ["-C", root, "rev-parse", "HEAD"], output, true) != 0:
		return false
	checkout_head = str(output[0]).strip_edges()
	binary_hash = FileAccess.get_sha256(root.path_join("export/input build.x86_64"))
	pack_hash = FileAccess.get_sha256(root.path_join("export/input build.pck"))
	driver_hash = FileAccess.get_sha256(root.path_join("tools/desktop-acceptance.gd"))
	return true


func _create_tree() -> bool:
	if not root.is_empty():
		return false
	# Stay beneath the checkout so the wrapper obtains real git provenance without a shim.
	var parent := ProjectSettings.globalize_path("res://.codex-run")
	if DirAccess.make_dir_recursive_absolute(parent) != OK:
		return false
	var candidate := parent.path_join(
		"desktop wrapper-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	)
	if DirAccess.make_dir_absolute(candidate) != OK:
		return false
	root = candidate
	evidence = ""
	for directory in ["tools", "export", "runs", "bin", "caller"]:
		if DirAccess.make_dir_recursive_absolute(root.path_join(directory)) != OK:
			return false
	return true


func _copy_artifacts(accelerated_timeout: bool) -> bool:
	var copies := [
		["tools/desktop-acceptance.sh", "tools/desktop-acceptance.sh"],
		["tools/desktop-acceptance.gd", "tools/desktop-acceptance.gd"],
		["test/helpers/desktop_export_fixture.py", "export/input build.x86_64"],
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
	return true


func write(path: String, content: String) -> bool:
	var file := FileAccess.open(root.path_join(path), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(content)
	return true


func remove(path: String) -> Error:
	return DirAccess.remove_absolute(root.path_join(path))


func run(arguments: Array = []) -> Dictionary:
	var output := []
	evidence = ""
	if arguments.is_empty():
		arguments = [root.path_join("export/input build.x86_64")]
	var command := [
		"--kill-after=1s",
		"5s",
		"env",
		"PATH=" + root.path_join("bin") + ":" + OS.get_environment("PATH"),
		"TMPDIR=" + root.path_join("runs"),
		"XDG_CACHE_HOME=" + root.path_join("caller"),
		"XDG_DATA_HOME=" + root.path_join("caller"),
		"XDG_CONFIG_HOME=" + root.path_join("caller"),
		"bash",
		root.path_join("tools/desktop-acceptance.sh"),
	]
	command.append_array(arguments)
	var code := OS.execute("/usr/bin/timeout", command, output, true)
	var log := "".join(output)
	for line in log.split("\n"):
		if line.begins_with("desktop-acceptance: evidence "):
			evidence = line.trim_prefix("desktop-acceptance: evidence ")
	return {"code": code, "output": log}


func read(path: String) -> String:
	var full := root.path_join(path)
	return FileAccess.get_file_as_string(full) if FileAccess.file_exists(full) else ""


func read_evidence(path: String) -> String:
	var full := evidence.path_join(path)
	return FileAccess.get_file_as_string(full) if FileAccess.file_exists(full) else ""


func originals_unchanged() -> bool:
	for path in ["override.cfg", "export/override.cfg", "caller/override.cfg"]:
		if read(path) != "original override sentinel\n":
			return false
	return (
		FileAccess.get_sha256(root.path_join("export/input build.x86_64")) == binary_hash
		and FileAccess.get_sha256(root.path_join("export/input build.pck")) == pack_hash
		and FileAccess.get_sha256(root.path_join("tools/desktop-acceptance.gd")) == driver_hash
	)


func destroy() -> bool:
	if root.is_empty():
		return true
	var removed := _remove_owned_tree(root)
	if removed:
		root = ""
	return removed


func _remove_owned_tree(path: String) -> bool:
	if path != root and not path.begins_with(root + "/"):
		return false
	var directory := DirAccess.open(path)
	if directory == null:
		return false
	directory.include_hidden = true
	var removed := true
	for child in directory.get_directories():
		var target := path.path_join(child)
		if directory.is_link(child):
			removed = (DirAccess.remove_absolute(target) == OK) and removed
		else:
			removed = _remove_owned_tree(target) and removed
	for child in directory.get_files():
		removed = (DirAccess.remove_absolute(path.path_join(child)) == OK) and removed
	return (DirAccess.remove_absolute(path) == OK) and removed
