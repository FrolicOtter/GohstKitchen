extends Control

signal load_game_requested

# Put your GitHub repository URL here, for example:
# https://github.com/YourName/YourGameDLC
@export var GITHUB_REPO_URL: String = ""
@export var GITHUB_DLC_ROOT_PATH: String = ""
@export var DLC_INSTALL_DIR: String = "user://DLC"
@export var MAIN_PAGE_SCENE_PATH: String = "main_menu_page.tscn"
@export var DLC_PAGE_SCENE_PATH: String = "dlc_menu_page.tscn"
@export var CREDITS_PAGE_SCENE_PATH: String = "credits_menu_page.tscn"
@export var MORE_PAGE_SCENE_PATH: String = "more_menu_page.tscn"
@export var GIFT_PAGE_SCENE_PATH: String = "gift_menu_page.tscn"
@export var TUTORIAL_PAGE_SCENE_PATH: String = "tutorial_menu_page.tscn"

const DEFAULT_DLC_INSTALL_DIR := "user://DLC"

var _installed_dlcs: Array[Dictionary] = []
var _available_dlcs: Array[Dictionary] = []
var _github_owner := ""
var _github_repo := ""
var _selected_available_dlc: Dictionary = {}
var _pending_manifest_dirs: Array[Dictionary] = []
var _pending_pck_downloads: Array[Dictionary] = []
var _current_request_kind := ""
var _current_request_meta: Dictionary = {}
var _runtime_content_mode := ""

var _http: HTTPRequest
var _pages_root: Control
var _main_page: Control
var _dlc_page: Control
var _credits_page: Control
var _more_page: Control
var _gift_page: Control
var _tutorial_page: Control
var _installed_list: VBoxContainer
var _available_list: VBoxContainer
var _status_label: Label
var _download_button: Button
var _dlc_title_label: Label
var _credits_label: Label
var _gift_label: Label
var _tutorial_label: Label


func _ready() -> void:
	_runtime_content_mode = _get_runtime_content_mode()
	_ensure_dlc_folder()
	_scan_installed_dlcs()
	_load_installed_dlc_pcks()
	_instance_menu_pages()
	_build_http_request()
	_cache_scene_nodes()
	_wire_scene_buttons()
	_load_scene_text()
	_refresh_dlc_lists()
	_show_main_menu()


func _ensure_dlc_folder() -> void:
	var error := DirAccess.make_dir_recursive_absolute(_to_absolute_filesystem_path(_get_dlc_install_dir()))
	if error != OK:
		push_error("Could not create DLC directory. Error code: %s" % error)


func _scan_installed_dlcs() -> void:
	_installed_dlcs.clear()

	var dlc_dir := _get_dlc_install_dir()
	var dir := DirAccess.open(dlc_dir)
	if dir == null:
		return

	dir.list_dir_begin()
	var folder_name := dir.get_next()
	while folder_name != "":
		if dir.current_is_dir() and not folder_name.begins_with("."):
			var manifest_path := _join_paths(_join_paths(dlc_dir, folder_name), "manifest.json")
			var manifest := _read_json_file(manifest_path)
			if not manifest.is_empty():
				_installed_dlcs.append(_normalize_dlc_manifest(manifest, folder_name))
			else:
				var pcks := _find_pck_files(_join_paths(dlc_dir, folder_name))
				if not pcks.is_empty():
					_installed_dlcs.append({
						"id": folder_name,
						"path": folder_name,
						"name": folder_name,
						"description": "Installed DLC pack.",
						"version": "unknown",
						"dependencies": [],
						"pck_files": pcks,
					})
		elif not dir.current_is_dir() and folder_name.get_extension().to_lower() == "pck":
			_installed_dlcs.append({
				"id": folder_name.get_basename(),
				"path": folder_name,
				"name": folder_name.get_basename(),
				"description": "Installed DLC pack.",
				"version": "unknown",
				"dependencies": [],
				"pck_files": [_join_paths(dlc_dir, folder_name)],
			})
		folder_name = dir.get_next()
	dir.list_dir_end()


func _read_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}

	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Invalid DLC manifest JSON: %s" % path)
		return {}

	return parsed


func _normalize_dlc_manifest(manifest: Dictionary, folder_path: String) -> Dictionary:
	return {
		"id": folder_path.get_file(),
		"path": folder_path,
		"name": str(manifest.get("name", folder_path.get_file())),
		"description": str(manifest.get("description", "No description provided.")),
		"version": _get_manifest_version(manifest),
		"dependencies": _get_manifest_string_array(manifest, "dependencies"),
		"pck_files": _get_manifest_pck_files(manifest),
	}


func _get_manifest_string_array(manifest: Dictionary, field_name: String) -> Array[String]:
	var values: Array[String] = []
	var raw = manifest.get(field_name, [])
	if typeof(raw) == TYPE_STRING:
		values.append(str(raw))
	elif typeof(raw) == TYPE_ARRAY:
		for value in raw:
			values.append(str(value))
	return values


func _get_manifest_pck_files(manifest: Dictionary) -> Array[String]:
	var pcks: Array[String] = []
	for field_name in ["pck_files", "pcks", "pck", "pck_file", "pck_path"]:
		for value in _get_manifest_string_array(manifest, field_name):
			if value.get_extension().to_lower() == "pck" and not pcks.has(value):
				pcks.append(value)
	return pcks


func _get_manifest_version(manifest: Dictionary) -> String:
	if manifest.has("current_version"):
		return str(manifest["current_version"])
	if manifest.has("current verssion"):
		return str(manifest["current verssion"])
	if manifest.has("version"):
		return str(manifest["version"])
	return "unknown"


func _get_runtime_content_mode() -> String:
	if OS.has_feature("editor"):
		return "source_tree"
	return "base_pack"


func _load_installed_dlc_pcks() -> void:
	for pck_path in _find_pck_files(_get_dlc_install_dir()):
		var loaded := ProjectSettings.load_resource_pack(pck_path, true)
		if not loaded:
			push_warning("Could not load DLC pack: %s" % pck_path)


func _find_pck_files(path: String) -> Array[String]:
	var pcks: Array[String] = []
	var dir := DirAccess.open(path)
	if dir == null:
		return pcks

	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var entry_path := _join_paths(path, entry)
		if dir.current_is_dir() and not entry.begins_with("."):
			pcks.append_array(_find_pck_files(entry_path))
		elif not dir.current_is_dir() and entry.get_extension().to_lower() == "pck":
			pcks.append(entry_path)
		entry = dir.get_next()
	dir.list_dir_end()
	return pcks


func _build_http_request() -> void:
	_http = HTTPRequest.new()
	_http.name = "DLC_HTTPRequest"
	_http.timeout = 30.0
	_http.request_completed.connect(_on_http_request_completed)
	add_child(_http)


func _instance_menu_pages() -> void:
	_pages_root = get_node_or_null("Pages") as Control
	if _pages_root == null:
		push_error("Main menu Pages node is missing.")
		return

	for child in _pages_root.get_children():
		_pages_root.remove_child(child)
		child.queue_free()

	_add_menu_page(MAIN_PAGE_SCENE_PATH, "MainPage")
	_add_menu_page(DLC_PAGE_SCENE_PATH, "DLCPage")
	_add_menu_page(CREDITS_PAGE_SCENE_PATH, "CreditsPage")
	_add_menu_page(MORE_PAGE_SCENE_PATH, "MorePage")
	_add_menu_page(GIFT_PAGE_SCENE_PATH, "GiftPage")
	_add_menu_page(TUTORIAL_PAGE_SCENE_PATH, "TutorialPage")


func _add_menu_page(scene_path: String, expected_name: String) -> void:
	var scene := load(_resolve_menu_scene_path(scene_path)) as PackedScene
	if scene == null:
		push_error("Could not load menu page scene: %s" % scene_path)
		return

	var page := scene.instantiate() as Control
	if page == null:
		push_error("Menu page scene root must be a Control: %s" % scene_path)
		return

	page.name = expected_name
	_pages_root.add_child(page)


func _resolve_menu_scene_path(scene_path: String) -> String:
	var clean_path := scene_path.strip_edges()
	if clean_path.begins_with("res://") or clean_path.begins_with("user://"):
		return clean_path
	return CorePaths.path(clean_path)


func _cache_scene_nodes() -> void:
	_main_page = get_node("Pages/MainPage") as Control
	_dlc_page = get_node("Pages/DLCPage") as Control
	_credits_page = get_node("Pages/CreditsPage") as Control
	_more_page = get_node("Pages/MorePage") as Control
	_gift_page = get_node("Pages/GiftPage") as Control
	_tutorial_page = get_node("Pages/TutorialPage") as Control
	_installed_list = get_node("Pages/DLCPage/RootMargin/Root/Columns/InstalledPanel/Frame/Scroll/List") as VBoxContainer
	_available_list = get_node("Pages/DLCPage/RootMargin/Root/Columns/AvailablePanel/Frame/Scroll/List") as VBoxContainer
	_status_label = get_node("Pages/DLCPage/RootMargin/Root/BottomBar/StatusLabel") as Label
	_download_button = get_node("Pages/DLCPage/RootMargin/Root/BottomBar/DownloadButton") as Button
	_dlc_title_label = get_node("Pages/DLCPage/RootMargin/Root/TopBar/Title") as Label
	_credits_label = get_node("Pages/CreditsPage/RootMargin/Root/Frame/Scroll/CreditsLabel") as Label
	_gift_label = get_node("Pages/GiftPage/RootMargin/Root/Frame/Scroll/GiftLabel") as Label
	_tutorial_label = get_node("Pages/TutorialPage/RootMargin/Root/Frame/Scroll/TutorialLabel") as Label


func _wire_scene_buttons() -> void:
	_connect_button("Pages/MainPage/MainCenter/MainPanel/Stack/LoadGameButton", _on_load_game_pressed)
	_connect_button("Pages/MainPage/MainCenter/MainPanel/Stack/ManageDLCButton", _show_dlc_page)
	_connect_button("Pages/MainPage/MainCenter/MainPanel/Stack/CreditsButton", _show_credits_page)
	_connect_button("Pages/MainPage/MainCenter/MainPanel/Stack/MoreButton", _show_more_page)
	_connect_button("Pages/DLCPage/RootMargin/Root/TopBar/BackButton", _show_main_menu)
	_connect_button("Pages/DLCPage/RootMargin/Root/TopBar/RefreshButton", _refresh_dlc_data)
	_connect_button("Pages/DLCPage/RootMargin/Root/BottomBar/DownloadButton", _download_selected_dlc)
	_connect_button("Pages/CreditsPage/RootMargin/Root/TopBar/BackButton", _show_main_menu)
	_connect_button("Pages/MorePage/RootMargin/Root/TopBar/BackButton", _show_main_menu)
	_connect_button("Pages/MorePage/RootMargin/Root/Frame/MenuCenter/Stack/GiftInfoButton", _show_gift_page)
	_connect_button("Pages/MorePage/RootMargin/Root/Frame/MenuCenter/Stack/TutorialButton", _show_tutorial_page)
	_connect_button("Pages/GiftPage/RootMargin/Root/TopBar/BackButton", _show_more_page)
	_connect_button("Pages/TutorialPage/RootMargin/Root/TopBar/BackButton", _show_more_page)


func _connect_button(path: NodePath, callback: Callable) -> void:
	var button := get_node_or_null(path) as Button
	if button == null:
		push_warning("Main menu button missing: %s" % path)
		return
	if not button.pressed.is_connected(callback):
		button.pressed.connect(callback)


func _load_scene_text() -> void:
	if _credits_label != null:
		_credits_label.text = _load_credits_text()
	if _gift_label != null:
		_gift_label.text = _load_gift_text()
	if _tutorial_label != null:
		_tutorial_label.text = _load_tutorial_text()


func _load_credits_text() -> String:
	var credits_path := CorePaths.path("CREDITS.md")
	if not FileAccess.file_exists(credits_path):
		return "Credits file missing."

	var file := FileAccess.open(credits_path, FileAccess.READ)
	if file == null:
		return "Could not load credits."

	return file.get_as_text()


func _load_gift_text() -> String:
	var gift_path := CorePaths.path("GIFT.md")
	if not FileAccess.file_exists(gift_path):
		return "Gift info file missing."

	var file := FileAccess.open(gift_path, FileAccess.READ)
	if file == null:
		return "Could not load gift info."

	return file.get_as_text()


func _load_tutorial_text() -> String:
	var tutorial_path := CorePaths.path("tutorial.md")
	if not FileAccess.file_exists(tutorial_path):
		return "Tutorial file missing."

	var file := FileAccess.open(tutorial_path, FileAccess.READ)
	if file == null:
		return "Could not load tutorial."

	return file.get_as_text()


func _create_small_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(150, 42)
	button.add_theme_font_size_override("font_size", 18)
	_apply_button_sprites(button)
	return button


func _apply_button_sprites(button: Button) -> void:
	button.add_theme_color_override("font_color", Color.BLACK)
	button.add_theme_color_override("font_hover_color", Color.BLACK)
	button.add_theme_color_override("font_pressed_color", Color.BLACK)
	button.add_theme_color_override("font_focus_color", Color.BLACK)
	button.add_theme_color_override("font_disabled_color", Color.BLACK)


func _show_main_menu() -> void:
	_main_page.visible = true
	_dlc_page.visible = false
	_credits_page.visible = false
	_more_page.visible = false
	_gift_page.visible = false
	_tutorial_page.visible = false


func _show_dlc_page() -> void:
	_main_page.visible = false
	_dlc_page.visible = true
	_credits_page.visible = false
	_more_page.visible = false
	_gift_page.visible = false
	_tutorial_page.visible = false
	_refresh_dlc_data()


func _show_credits_page() -> void:
	_main_page.visible = false
	_dlc_page.visible = false
	_credits_page.visible = true
	_more_page.visible = false
	_gift_page.visible = false
	_tutorial_page.visible = false
	if _credits_label != null:
		_credits_label.text = _load_credits_text()


func _show_more_page() -> void:
	_main_page.visible = false
	_dlc_page.visible = false
	_credits_page.visible = false
	_more_page.visible = true
	_gift_page.visible = false
	_tutorial_page.visible = false


func _show_gift_page() -> void:
	_main_page.visible = false
	_dlc_page.visible = false
	_credits_page.visible = false
	_more_page.visible = false
	_gift_page.visible = true
	_tutorial_page.visible = false
	if _gift_label != null:
		_gift_label.text = _load_gift_text()


func _show_tutorial_page() -> void:
	_main_page.visible = false
	_dlc_page.visible = false
	_credits_page.visible = false
	_more_page.visible = false
	_gift_page.visible = false
	_tutorial_page.visible = true
	if _tutorial_label != null:
		_tutorial_label.text = _load_tutorial_text()


func _on_load_game_pressed() -> void:
	load_game_requested.emit()
	get_tree().change_scene_to_file(CorePaths.path("mian.tscn"))


func _refresh_dlc_data() -> void:
	_scan_installed_dlcs()
	_refresh_dlc_lists()
	_fetch_available_dlcs_from_github()


func _refresh_dlc_lists() -> void:
	_clear_container(_installed_list)
	_clear_container(_available_list)

	if _installed_dlcs.is_empty():
		_installed_list.add_child(_create_empty_row("No installed DLC found."))
	else:
		for dlc in _installed_dlcs:
			_installed_list.add_child(_create_dlc_row(dlc, false))

	if _available_dlcs.is_empty():
		_available_list.add_child(_create_empty_row("No available DLC loaded yet."))
	else:
		for dlc in _available_dlcs:
			_available_list.add_child(_create_dlc_row(dlc, true))

	if _download_button != null:
		_download_button.disabled = _selected_available_dlc.is_empty()


func _clear_container(container: Node) -> void:
	if container == null:
		return
	for child in container.get_children():
		child.queue_free()


func _create_empty_row(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.modulate = Color(0.80, 0.84, 0.88)
	return label


func _create_dlc_row(dlc: Dictionary, selectable: bool) -> Control:
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, 96)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 4)
	row.add_child(layout)

	var header := HBoxContainer.new()
	layout.add_child(header)

	var name := Label.new()
	name.text = "%s  v%s" % [dlc.get("name", "Unnamed DLC"), dlc.get("version", "unknown")]
	name.add_theme_font_size_override("font_size", 18)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name)

	if selectable:
		var select_button := _create_small_button("Select")
		select_button.custom_minimum_size = Vector2(96, 34)
		select_button.pressed.connect(_select_available_dlc.bind(dlc))
		header.add_child(select_button)

	var description := Label.new()
	description.text = str(dlc.get("description", "No description provided."))
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.modulate = Color(0.86, 0.89, 0.92)
	layout.add_child(description)

	return row


func _select_available_dlc(dlc: Dictionary) -> void:
	_selected_available_dlc = dlc.duplicate(true)
	_set_status("Selected %s." % dlc.get("name", "DLC"))
	if _download_button != null:
		_download_button.disabled = false


func _set_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message


func _fetch_available_dlcs_from_github() -> void:
	_available_dlcs.clear()
	_selected_available_dlc.clear()
	_refresh_dlc_lists()

	var repo_info := _parse_github_repo_url(GITHUB_REPO_URL)
	if repo_info.is_empty():
		_set_status("Set GITHUB_REPO_URL before fetching available DLC.")
		return

	_github_owner = repo_info["owner"]
	_github_repo = repo_info["repo"]
	_set_status("Fetching available DLC from GitHub...")

	var dlc_root := _get_github_dlc_root_path()
	var url := "https://api.github.com/repos/%s/%s/contents" % [_github_owner, _github_repo]
	if not dlc_root.is_empty():
		url = "%s/%s" % [url, _url_encode_path(dlc_root)]
	_start_json_request("root_contents", url, {})


func _parse_github_repo_url(url: String) -> Dictionary:
	var clean := url.strip_edges().trim_suffix("/")
	if clean.is_empty():
		return {}

	if clean.begins_with("git@github.com:"):
		clean = clean.replace("git@github.com:", "")
	elif clean.begins_with("https://github.com/"):
		clean = clean.replace("https://github.com/", "")
	elif clean.begins_with("http://github.com/"):
		clean = clean.replace("http://github.com/", "")

	clean = clean.trim_suffix(".git")
	var parts := clean.split("/", false)
	if parts.size() < 2:
		return {}

	return {
		"owner": parts[0],
		"repo": parts[1],
	}


func _start_json_request(kind: String, url: String, meta: Dictionary) -> void:
	if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_http.cancel_request()

	_current_request_kind = kind
	_current_request_meta = meta

	var headers := PackedStringArray([
		"Accept: application/vnd.github+json",
		"User-Agent: Godot-DLC-Manager",
	])
	var error := _http.request(url, headers)
	if error != OK:
		_set_status("Could not start GitHub request. Error code: %s" % error)


func _on_http_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_set_status("Network request failed. Result code: %s" % result)
		return

	if response_code < 200 or response_code >= 300:
		if _current_request_kind == "dlc_manifest":
			_request_next_remote_manifest()
			return
		_set_status("GitHub returned HTTP %s." % response_code)
		return

	if _current_request_kind == "download_pck":
		_finish_pck_download(body)
		return

	var text := body.get_string_from_utf8()
	var parsed = JSON.parse_string(text)
	if parsed == null:
		_set_status("GitHub response was not valid JSON.")
		return

	match _current_request_kind:
		"root_contents":
			_on_root_contents_loaded(parsed)
		"dlc_manifest":
			_on_remote_manifest_loaded(parsed, _current_request_meta)
		"pck_file_info":
			_on_pck_file_info_loaded(parsed, _current_request_meta)
		_:
			_set_status("Unknown request finished: %s" % _current_request_kind)


func _on_root_contents_loaded(parsed) -> void:
	if typeof(parsed) != TYPE_ARRAY:
		_set_status("GitHub root contents response was not a list.")
		return

	_pending_manifest_dirs.clear()
	var dlc_root := _get_github_dlc_root_path()
	for item in parsed:
		if typeof(item) == TYPE_DICTIONARY and item.get("type", "") == "dir":
			var item_path := str(item.get("path", ""))
			if not dlc_root.is_empty() and not item_path.begins_with(dlc_root + "/"):
				item_path = "%s/%s" % [dlc_root, item_path.get_file()]
			_pending_manifest_dirs.append({
				"path": item_path,
				"name": str(item.get("name", "")),
			})

	_request_next_remote_manifest()


func _request_next_remote_manifest() -> void:
	if _pending_manifest_dirs.is_empty():
		_set_status("Loaded %s available DLC entr%s." % [
			_available_dlcs.size(),
			"y" if _available_dlcs.size() == 1 else "ies",
		])
		_refresh_dlc_lists()
		return

	var dir_info: Dictionary = _pending_manifest_dirs.pop_front()
	var encoded_path := _url_encode_path("%s/manifest.json" % dir_info["path"])
	var url := "https://api.github.com/repos/%s/%s/contents/%s" % [
		_github_owner,
		_github_repo,
		encoded_path,
	]
	_start_json_request("dlc_manifest", url, dir_info)


func _on_remote_manifest_loaded(parsed, dir_info: Dictionary) -> void:
	if typeof(parsed) == TYPE_DICTIONARY and parsed.has("content"):
		var encoded_content := str(parsed["content"]).replace("\n", "")
		var manifest_text := Marshalls.base64_to_utf8(encoded_content)
		var manifest = JSON.parse_string(manifest_text)
		if typeof(manifest) == TYPE_DICTIONARY:
			var dlc := _normalize_dlc_manifest(manifest, str(dir_info["path"]))
			dlc["remote_path"] = str(dir_info["path"])
			_available_dlcs.append(dlc)

	# A folder without manifest.json is ignored, then the next folder is checked.
	_request_next_remote_manifest()


func _url_encode_path(path: String) -> String:
	var parts := path.split("/", false)
	for index in parts.size():
		parts[index] = parts[index].uri_encode()
	return "/".join(parts)


func _download_selected_dlc() -> void:
	if _selected_available_dlc.is_empty():
		_set_status("Choose an available DLC first.")
		return

	if _github_owner.is_empty() or _github_repo.is_empty():
		var repo_info := _parse_github_repo_url(GITHUB_REPO_URL)
		if repo_info.is_empty():
			_set_status("Set GITHUB_REPO_URL before downloading DLC.")
			return
		_github_owner = repo_info["owner"]
		_github_repo = repo_info["repo"]

	var required_dlcs := _resolve_dlc_download_order(_selected_available_dlc)
	if required_dlcs.is_empty():
		return

	_pending_pck_downloads.clear()
	for dlc in required_dlcs:
		var pck_files: Array = dlc.get("pck_files", [])
		for pck_file in pck_files:
			var pck_path := str(pck_file)
			if pck_path.get_extension().to_lower() != "pck":
				continue

			var remote_path := _resolve_remote_pck_path(dlc, pck_path)
			var dlc_folder := _sanitize_path_segment(str(dlc.get("id", dlc.get("name", "dlc"))))
			var target_path := _join_paths(_join_paths(_get_dlc_install_dir(), dlc_folder), pck_path.get_file())
			_pending_pck_downloads.append({
				"dlc": dlc,
				"remote_path": remote_path,
				"target_path": target_path,
			})

	if _pending_pck_downloads.is_empty():
		_set_status("Selected DLC has no .pck files listed in its manifest.")
		return

	_set_status("Downloading %s DLC pack file%s..." % [
		_pending_pck_downloads.size(),
		"" if _pending_pck_downloads.size() == 1 else "s",
	])
	_download_next_pck()


func _resolve_dlc_download_order(root_dlc: Dictionary) -> Array[Dictionary]:
	var ordered: Array[Dictionary] = []
	var visiting: Dictionary = {}
	var visited: Dictionary = {}
	var missing: Array[String] = []
	var circular: Array[String] = []

	_resolve_dlc_dependencies_recursive(root_dlc, ordered, visiting, visited, missing, circular)
	if not missing.is_empty():
		_set_status("Missing DLC dependencies: %s" % ", ".join(missing))
		return []
	if not circular.is_empty():
		_set_status("Circular DLC dependency found: %s" % ", ".join(circular))
		return []

	return ordered


func _resolve_dlc_dependencies_recursive(
	dlc: Dictionary,
	ordered: Array[Dictionary],
	visiting: Dictionary,
	visited: Dictionary,
	missing: Array[String],
	circular: Array[String]
) -> void:
	var id := str(dlc.get("id", dlc.get("name", "")))
	if id.is_empty() or visited.has(id):
		return
	if visiting.has(id):
		if not circular.has(id):
			circular.append(id)
		return

	visiting[id] = true
	var dependencies: Array = dlc.get("dependencies", [])
	for dependency in dependencies:
		var dependency_id := str(dependency)
		if _is_dlc_installed(dependency_id):
			continue
		var dependency_dlc := _find_available_dlc(dependency_id)
		if dependency_dlc.is_empty():
			missing.append(dependency_id)
		else:
			_resolve_dlc_dependencies_recursive(dependency_dlc, ordered, visiting, visited, missing, circular)

	visiting.erase(id)
	visited[id] = true
	if not _is_dlc_installed(id):
		ordered.append(dlc)


func _find_available_dlc(identifier: String) -> Dictionary:
	for dlc in _available_dlcs:
		if _dlc_matches_identifier(dlc, identifier):
			return dlc
	return {}


func _is_dlc_installed(identifier: String) -> bool:
	for dlc in _installed_dlcs:
		if _dlc_matches_identifier(dlc, identifier):
			return true
	return false


func _dlc_matches_identifier(dlc: Dictionary, identifier: String) -> bool:
	var candidates: Array[String] = [
		str(dlc.get("id", "")),
		str(dlc.get("name", "")),
		str(dlc.get("path", "")),
		str(dlc.get("remote_path", "")),
	]
	for pck_file in dlc.get("pck_files", []):
		candidates.append(str(pck_file))

	for candidate in candidates:
		if candidate == identifier or candidate.get_file() == identifier:
			return true
	return false


func _resolve_remote_pck_path(dlc: Dictionary, pck_path: String) -> String:
	var normalized := pck_path.trim_prefix("/")
	var dlc_root := _get_github_dlc_root_path()
	if not dlc_root.is_empty() and normalized.begins_with(dlc_root + "/"):
		return normalized
	var remote_root := str(dlc.get("remote_path", "")).trim_suffix("/")
	if not remote_root.is_empty() and normalized.begins_with(remote_root + "/"):
		return normalized
	return _join_paths(remote_root if not remote_root.is_empty() else str(dlc.get("path", "")), normalized)


func _download_next_pck() -> void:
	if _pending_pck_downloads.is_empty():
		_scan_installed_dlcs()
		_load_installed_dlc_pcks()
		_refresh_dlc_lists()
		_set_status("Installed DLC pack files.")
		return

	var download_info: Dictionary = _pending_pck_downloads.pop_front()
	var encoded_path := _url_encode_path(str(download_info["remote_path"]))
	var url := "https://api.github.com/repos/%s/%s/contents/%s" % [
		_github_owner,
		_github_repo,
		encoded_path,
	]
	_start_json_request("pck_file_info", url, download_info)


func _on_pck_file_info_loaded(parsed, download_info: Dictionary) -> void:
	if typeof(parsed) != TYPE_DICTIONARY:
		_set_status("DLC .pck lookup did not return file metadata.")
		return
	if str(parsed.get("type", "")) != "file":
		_set_status("DLC manifest points to a non-file .pck path.")
		return

	var download_url := str(parsed.get("download_url", ""))
	if download_url.is_empty():
		_set_status("GitHub did not provide a .pck download URL.")
		return

	_start_binary_request("download_pck", download_url, download_info)


func _start_binary_request(kind: String, url: String, meta: Dictionary) -> void:
	if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_http.cancel_request()

	_current_request_kind = kind
	_current_request_meta = meta

	var headers := PackedStringArray(["User-Agent: Godot-DLC-Manager"])
	var error := _http.request(url, headers)
	if error != OK:
		_set_status("Could not start DLC pack download. Error code: %s" % error)


func _finish_pck_download(body: PackedByteArray) -> void:
	var download_info: Dictionary = _current_request_meta
	var target_path := str(download_info.get("target_path", ""))
	if target_path.is_empty() or target_path.get_extension().to_lower() != "pck":
		_set_status("Invalid DLC .pck target path.")
		return

	_make_dir_recursive(target_path.get_base_dir())
	var file := FileAccess.open(target_path, FileAccess.WRITE)
	if file == null:
		_set_status("Could not create DLC .pck file.")
		return

	file.store_buffer(body)
	file.close()
	ProjectSettings.load_resource_pack(target_path, true)
	_download_next_pck()


func _strip_configured_dlc_root(path: String) -> String:
	var dlc_root := _get_github_dlc_root_path()
	if dlc_root.is_empty():
		return path

	var prefix := dlc_root + "/"
	if path.begins_with(prefix):
		return path.substr(prefix.length())
	return path


func _get_dlc_install_dir() -> String:
	var path := DLC_INSTALL_DIR.strip_edges().trim_suffix("/")
	if path.is_empty():
		return DEFAULT_DLC_INSTALL_DIR
	if path.begins_with("res://") or path.begins_with("user://") or path.is_absolute_path():
		return path
	if OS.has_feature("editor"):
		return "res://%s" % path.trim_prefix("/")
	return _join_paths(OS.get_executable_path().get_base_dir(), path)


func _get_github_dlc_root_path() -> String:
	return GITHUB_DLC_ROOT_PATH.strip_edges().trim_prefix("/").trim_suffix("/")


func _make_dir_recursive(path: String) -> void:
	var normalized := path.trim_suffix("/")
	if normalized.is_empty():
		return

	DirAccess.make_dir_recursive_absolute(_to_absolute_filesystem_path(normalized))


func _to_absolute_filesystem_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path


func _join_paths(base: String, child: String) -> String:
	if base.is_empty():
		return child
	return "%s/%s" % [base.trim_suffix("/"), child.trim_prefix("/")]


func _sanitize_path_segment(value: String) -> String:
	var clean := value.strip_edges()
	for character in ["\\", "/", ":", "*", "?", "\"", "<", ">", "|"]:
		clean = clean.replace(character, "_")
	if clean.is_empty():
		return "dlc"
	return clean
