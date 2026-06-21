class_name CorePaths
extends RefCounted


static func path(relative_path: String) -> String:
	var clean_path := relative_path.strip_edges().trim_prefix("/")
	var editor_path := "res://CORE/%s" % clean_path
	if OS.has_feature("editor") or ResourceLoader.exists(editor_path) or FileAccess.file_exists(editor_path):
		return editor_path
	return "res://%s" % clean_path
