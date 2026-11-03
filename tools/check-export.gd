extends SceneTree
## List the mounted release pack and reject development-only resources.

var _failed := false
var _files := 0


func _init() -> void:
	_list_pack("res://")
	if _failed or _files == 0:
		printerr("export-pack: rejected")
		quit(1)
		return
	print("export-pack: passed (%d files)" % _files)
	quit(0)


func _list_pack(path: String) -> void:
	if path.begins_with("res://test/") or path.begins_with("res://addons/gut/"):
		printerr("export-pack: forbidden resource: ", path)
		_failed = true
	var directory := DirAccess.open(path)
	if directory == null:
		printerr("export-pack: cannot list: ", path)
		_failed = true
		return
	directory.include_hidden = true
	for file in directory.get_files():
		print(path.path_join(file))
		_files += 1
	for child in directory.get_directories():
		_list_pack(path.path_join(child) + "/")
