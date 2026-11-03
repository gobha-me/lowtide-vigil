extends RefCounted
## Create real packs and an isolated source/caller tree; never mount into the test runner.

const PROJECT := 'config_version=5\n[application]\nconfig/name="Pack gate fixture"\n'

var root := ""


func create() -> Error:
	var name := "lowtide-export-test-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var candidate := OS.get_temp_dir().path_join(name)
	# Only claim ownership after creating a previously absent directory.
	var error := DirAccess.make_dir_absolute(candidate)
	if error != OK:
		return error
	root = candidate
	for path in ["source/tools", "caller", "wrapper temp"]:
		error = DirAccess.make_dir_recursive_absolute(root.path_join(path))
		if error != OK:
			return error
	for name_in_tools in ["check-export.sh", "check-export.gd"]:
		error = DirAccess.copy_absolute(
			ProjectSettings.globalize_path("res://tools/" + name_in_tools),
			root.path_join("source/tools/" + name_in_tools)
		)
		if error != OK:
			return error
	# Poison both possible source trees. A clean PCK must not see these loose resources.
	for tree in ["source", "caller"]:
		for path in ["project.godot", "test/source_only.txt", "addons/gut/source_only.txt"]:
			error = write(tree.path_join(path), PROJECT if path == "project.godot" else "loose")
			if error != OK:
				return error
	return OK


func write(path: String, contents: String) -> Error:
	var destination := root.path_join(path)
	var error := DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
	if error != OK:
		return error
	var file := FileAccess.open(destination, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(contents)
	file.close()
	return OK


func pack(path: String, resources: Dictionary, project: String = PROJECT) -> Error:
	var error := write("pack input/project.godot", project)
	if error != OK:
		return error
	error = DirAccess.make_dir_recursive_absolute(root.path_join(path).get_base_dir())
	if error != OK:
		return error
	var packer := PCKPacker.new()
	error = packer.pck_start(root.path_join(path))
	if error != OK:
		return error
	error = packer.add_file("res://project.godot", root.path_join("pack input/project.godot"))
	if error != OK:
		return error
	for resource: String in resources:
		var input := "pack input/resources/" + resource
		error = write(input, resources[resource])
		if error == OK:
			error = packer.add_file("res://" + resource, root.path_join(input))
		if error != OK:
			return error
	return packer.flush()


func run_gate(arguments: Array = []) -> Dictionary:
	var output := []
	var runner := ProjectSettings.globalize_path("res://test/helpers/run_export_gate.py")
	var code := OS.execute("python3", [runner, root] + arguments, output, true)
	return {"code": code, "output": "".join(output)}


func wrapper_scratch_is_empty() -> bool:
	var directory := DirAccess.open(root.path_join("wrapper temp"))
	if directory == null:
		return false
	directory.include_hidden = true
	return directory.get_files().is_empty() and directory.get_directories().is_empty()


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
	directory.include_navigational = false
	var removed := true
	for child in directory.get_directories():
		var target := path.path_join(child)
		if directory.is_link(child):
			removed = (DirAccess.remove_absolute(target) == OK) and removed
		else:
			removed = _remove_owned_tree(target) and removed
	for file in directory.get_files():
		removed = (DirAccess.remove_absolute(path.path_join(file)) == OK) and removed
	return (DirAccess.remove_absolute(path) == OK) and removed
