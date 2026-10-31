extends RefCounted
## A throwaway copy of the tracked tree for running the real term gate.
## Nothing is ever planted in the real repository: every change goes to the copy.

const PREFIX := "lowtide-termgate-"

var repo_root := ""
var copy_dir := ""
var _created := ""


func _init() -> void:
	repo_root = ProjectSettings.globalize_path("res://").trim_suffix("/")


## Copies every tracked file into a fresh temp dir and stages it in a new git repo there.
## Returns an empty string on success, otherwise what went wrong.
func create() -> String:
	var problem := _make_temp_dir()
	if problem == "":
		problem = _copy_tracked_files()
	if problem == "" and (_git(["init", "-q"]) != 0 or _git(["add", "-A"]) != 0):
		problem = "git init/add failed in the copy"
	return problem


## Writes a file into the copy, creating its directory. Returns false if it could not.
func write_file(path: String, text: String) -> bool:
	var destination := copy_dir.path_join(path)
	DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
	var file := FileAccess.open(destination, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	return true


func read_file(path: String) -> String:
	return FileAccess.get_file_as_string(copy_dir.path_join(path))


## Stages any planted change and runs the gate from inside the copy.
## Returns {"code": exit code, "output": stdout and stderr}.
func run_gate() -> Dictionary:
	# With captured output, OS.execute hands a double-quoted command line to /bin/sh, so a
	# "$1" placeholder would expand to nothing there. Inline the path, but only a plain one.
	if not RegEx.create_from_string("^/[A-Za-z0-9_./-]+$").search(copy_dir):
		return {"code": -1, "output": "unsafe temp path " + copy_dir}
	_git(["add", "-A"])
	var output := []
	var command := "cd %s && bash tools/term-gate.sh" % copy_dir
	var code := OS.execute("bash", ["-c", command], output, true)
	return {"code": code, "output": _first(output)}


## The real repository's porcelain status, to show the case left it untouched.
func repo_status() -> String:
	var output := []
	OS.execute("git", ["-C", repo_root, "status", "--porcelain", "--untracked-files=all"], output)
	return _first(output)


## Deletes the temp dir this sandbox created, and nothing else.
func destroy() -> bool:
	if _created == "" or copy_dir != _created:
		return false
	var temp_root := OS.get_temp_dir().trim_suffix("/")
	if not _created.begins_with(temp_root.path_join(PREFIX)) or _is_inside_repo(_created):
		return false
	var removed := _remove_tree(_created)
	_created = ""
	return removed


func _git(arguments: Array) -> int:
	return OS.execute("git", ["-C", copy_dir] + arguments, [])


func _make_temp_dir() -> String:
	var temp_root := OS.get_temp_dir().trim_suffix("/")
	var unique := "%d-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec(), randi()]
	var target := temp_root.path_join(PREFIX + unique)
	if _is_inside_repo(target):
		return "temp dir %s is inside the repo" % target
	if DirAccess.dir_exists_absolute(target):
		return "temp dir %s already exists" % target
	if DirAccess.make_dir_absolute(target) != OK:
		return "could not create %s" % target
	_created = target
	copy_dir = target
	return ""


func _copy_tracked_files() -> String:
	var listing := []
	var list_arguments := ["-C", repo_root, "-c", "core.quotePath=false", "ls-files"]
	if OS.execute("git", list_arguments, listing) != 0:
		return "git ls-files failed in " + repo_root
	var paths := _first(listing).split("\n", false)
	if paths.is_empty():
		return "git ls-files listed nothing in " + repo_root
	for path in paths:
		var destination := copy_dir.path_join(path)
		DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
		if DirAccess.copy_absolute(repo_root.path_join(path), destination) != OK:
			return "could not copy " + path
	if not FileAccess.file_exists(copy_dir.path_join("tools/term-gate.sh")):
		return "copy in %s has no tools/term-gate.sh" % copy_dir
	return ""


func _first(output: Array) -> String:
	return str(output[0]) if not output.is_empty() else ""


func _is_inside_repo(path: String) -> bool:
	return path == repo_root or path.begins_with(repo_root + "/")


func _remove_tree(path: String) -> bool:
	if path != _created and not path.begins_with(_created + "/"):
		return false
	var dir := DirAccess.open(path)
	if dir == null:
		return false
	dir.include_hidden = true
	dir.include_navigational = false
	var removed := true
	for name in dir.get_directories():
		var child := path.path_join(name)
		if dir.is_link(name):
			removed = DirAccess.remove_absolute(child) == OK and removed
		else:
			removed = _remove_tree(child) and removed
	for name in dir.get_files():
		removed = DirAccess.remove_absolute(path.path_join(name)) == OK and removed
	return DirAccess.remove_absolute(path) == OK and removed
