extends Control

signal load_game_requested

# Put your GitHub repository URL here, for example:
# https://github.com/YourName/YourGameDLC
@export var GITHUB_REPO_URL: String = "https://github.com/FrolicOtter/GohstKitchen"
@export var GITHUB_DLC_ROOT_PATH: String = "DLC"
@export var DLC_INSTALL_DIR: String = "DLC"
@export var MAIN_PAGE_SCENE_PATH: String = "main_menu_page.tscn"
@export var DLC_PAGE_SCENE_PATH: String = "dlc_menu_page.tscn"
@export var CREDITS_PAGE_SCENE_PATH: String = "credits_menu_page.tscn"
@export var MORE_PAGE_SCENE_PATH: String = "more_menu_page.tscn"
@export var GIFT_PAGE_SCENE_PATH: String = "gift_menu_page.tscn"
@export var TUTORIAL_PAGE_SCENE_PATH: String = "tutorial_menu_page.tscn"

const DEFAULT_DLC_INSTALL_DIR := "DLC"
const UI_BUTTON_NORMAL_PATH := "Complete_UI_Essential_Pack_Free/01_Flat_Theme/Sprites/UI_Flat_Button01a_4.png"
const UI_BUTTON_HOVER_PATH := "Complete_UI_Essential_Pack_Free/01_Flat_Theme/Sprites/UI_Flat_Button01a_2.png"
const UI_BUTTON_PRESSED_PATH := "Complete_UI_Essential_Pack_Free/01_Flat_Theme/Sprites/UI_Flat_Button01a_3.png"
const UI_FRAME_BLUE_PATH := "Complete_UI_Essential_Pack_Free/01_Flat_Theme/Sprites/UI_Flat_Frame02a.png"
const UI_FRAME_ORANGE_PATH := "Complete_UI_Essential_Pack_Free/01_Flat_Theme/Sprites/UI_Flat_Frame03a.png"

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
var _pending_dlc_confirmation_action := ""
var _pending_dlc_confirmation_data: Dictionary = {}

var _http: HTTPRequest
var _dlc_confirmation_dialog: ConfirmationDialog
var _dlc_restart_popup_layer: CanvasLayer
var _dlc_restart_popup_message: Label
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
	_build_dlc_confirmation_dialog()
	_build_dlc_restart_popup()
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
				var dlc := _normalize_dlc_manifest(manifest, folder_name)
				dlc["install_path"] = _join_paths(dlc_dir, folder_name)
				dlc["source"] = "local"
				_installed_dlcs.append(dlc)
			else:
				var pcks := _find_pck_files(_join_paths(dlc_dir, folder_name))
				if not pcks.is_empty():
					_installed_dlcs.append({
						"id": folder_name,
						"path": folder_name,
						"name": folder_name,
						"description": "Installed local DLC pack.",
						"version": "unknown",
						"dependencies": [],
						"pck_files": pcks,
						"install_path": _join_paths(dlc_dir, folder_name),
						"source": "local",
					})
		elif not dir.current_is_dir() and folder_name.get_extension().to_lower() == "pck":
			_installed_dlcs.append({
				"id": folder_name.get_basename(),
				"path": folder_name,
				"name": folder_name.get_basename(),
				"description": "Installed local DLC pack.",
				"version": "unknown",
				"dependencies": [],
				"pck_files": [_join_paths(dlc_dir, folder_name)],
				"install_path": _join_paths(dlc_dir, folder_name),
				"source": "local",
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
		"upcoming": _get_manifest_bool(manifest, "upcoming"),
		"dependencies": _get_manifest_string_array(manifest, "dependencies"),
		"pck_files": _get_manifest_pck_files(manifest),
	}


func _get_manifest_bool(manifest: Dictionary, field_name: String) -> bool:
	var raw = manifest.get(field_name, false)
	if typeof(raw) == TYPE_BOOL:
		return bool(raw)
	if typeof(raw) == TYPE_STRING:
		var clean := str(raw).strip_edges().to_lower()
		return clean == "true" or clean == "yes" or clean == "upcoming"
	if typeof(raw) == TYPE_INT or typeof(raw) == TYPE_FLOAT:
		return float(raw) != 0.0
	return false


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


func _build_dlc_confirmation_dialog() -> void:
	_dlc_confirmation_dialog = ConfirmationDialog.new()
	_dlc_confirmation_dialog.name = "DLCConfirmationDialog"
	_dlc_confirmation_dialog.confirmed.connect(_on_dlc_confirmation_confirmed)
	add_child(_dlc_confirmation_dialog)


func _build_dlc_restart_popup() -> void:
	_dlc_restart_popup_layer = CanvasLayer.new()
	_dlc_restart_popup_layer.name = "DLCRestartPopup"
	_dlc_restart_popup_layer.visible = false
	add_child(_dlc_restart_popup_layer)

	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.color = Color(0.0, 0.0, 0.0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dlc_restart_popup_layer.add_child(shade)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dlc_restart_popup_layer.add_child(center)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(430, 230)
	panel.add_theme_stylebox_override("panel", _create_ui_texture_style(UI_FRAME_BLUE_PATH))
	center.add_child(panel)

	var stack := VBoxContainer.new()
	stack.name = "Stack"
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 14)
	panel.add_child(stack)

	var title := Label.new()
	title.text = "DLC Changed"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	stack.add_child(title)

	_dlc_restart_popup_message = Label.new()
	_dlc_restart_popup_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dlc_restart_popup_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dlc_restart_popup_message.custom_minimum_size = Vector2(340, 72)
	_dlc_restart_popup_message.add_theme_font_size_override("font_size", 20)
	stack.add_child(_dlc_restart_popup_message)

	var ok_button := _create_small_button("OK")
	ok_button.custom_minimum_size = Vector2(160, 48)
	ok_button.pressed.connect(_hide_dlc_restart_popup)
	stack.add_child(ok_button)


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
	_connect_button("Pages/MainPage/MainCenter/MainPanel/Stack/TutorialButton", _show_tutorial_page)
	_connect_button("Pages/MainPage/MainCenter/MainPanel/Stack/CreditsButton", _show_credits_page)
	_connect_button("Pages/MainPage/MainCenter/MainPanel/Stack/MoreButton", _show_more_page)
	_connect_button("Pages/MainPage/MainCenter/MainPanel/Stack/ExitButton", _on_exit_pressed)
	_connect_button("Pages/DLCPage/RootMargin/Root/TopBar/BackButton", _show_more_page)
	_connect_button("Pages/DLCPage/RootMargin/Root/TopBar/RefreshButton", _refresh_dlc_data)
	_connect_button("Pages/DLCPage/RootMargin/Root/TopBar/ClearAllButton", _request_clear_all_dlcs)
	_connect_button("Pages/DLCPage/RootMargin/Root/BottomBar/DownloadButton", _download_selected_dlc)
	_connect_button("Pages/CreditsPage/RootMargin/Root/TopBar/BackButton", _show_main_menu)
	_connect_button("Pages/MorePage/RootMargin/Root/TopBar/BackButton", _show_main_menu)
	_connect_button("Pages/MorePage/RootMargin/Root/Frame/MenuCenter/Stack/GiftInfoButton", _show_gift_page)
	_connect_button("Pages/MorePage/RootMargin/Root/Frame/MenuCenter/Stack/ManageDLCButton", _show_dlc_page)
	_connect_button("Pages/GiftPage/RootMargin/Root/TopBar/BackButton", _show_more_page)
	_connect_button("Pages/TutorialPage/RootMargin/Root/TopBar/BackButton", _show_main_menu)


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
	button.add_theme_stylebox_override("normal", _create_ui_texture_style(UI_BUTTON_NORMAL_PATH))
	button.add_theme_stylebox_override("hover", _create_ui_texture_style(UI_BUTTON_HOVER_PATH))
	button.add_theme_stylebox_override("pressed", _create_ui_texture_style(UI_BUTTON_PRESSED_PATH))
	button.add_theme_stylebox_override("disabled", _create_ui_texture_style(UI_BUTTON_NORMAL_PATH))


func _create_ui_texture_style(texture_path: String) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = load(CorePaths.path(texture_path)) as Texture2D
	style.texture_margin_left = 6.0
	style.texture_margin_top = 6.0
	style.texture_margin_right = 6.0
	style.texture_margin_bottom = 6.0
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	return style


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


func _on_exit_pressed() -> void:
	get_tree().quit()


func _refresh_dlc_data() -> void:
	_scan_installed_dlcs()
	_refresh_dlc_lists()
	_fetch_available_dlcs_from_github()


func _refresh_dlc_lists() -> void:
	_clear_container(_installed_list)
	_clear_container(_available_list)
	_sync_available_dlc_install_state()
	_refresh_selected_available_dlc_state()
	if not _selected_available_dlc.is_empty() and not _is_available_dlc_downloadable(_selected_available_dlc):
		_selected_available_dlc.clear()

	if _installed_dlcs.is_empty():
		_installed_list.add_child(_create_empty_row("No installed DLC found."))
	else:
		for dlc in _installed_dlcs:
			_installed_list.add_child(_create_dlc_row(dlc, false))

	var visible_available_dlcs := _get_visible_available_dlcs()
	if visible_available_dlcs.is_empty():
		_available_list.add_child(_create_empty_row("No downloadable DLC loaded yet."))
	else:
		for dlc in visible_available_dlcs:
			_available_list.add_child(_create_dlc_row(dlc, true))

	if _download_button != null:
		_download_button.disabled = _selected_available_dlc.is_empty()


func _clear_container(container: Node) -> void:
	if container == null:
		return
	for child in container.get_children():
		child.queue_free()


func _get_visible_available_dlcs() -> Array[Dictionary]:
	var visible_dlcs: Array[Dictionary] = []
	for dlc in _available_dlcs:
		if not _is_available_dlc_downloadable(dlc):
			continue
		visible_dlcs.append(dlc)
	return visible_dlcs


func _refresh_selected_available_dlc_state() -> void:
	if _selected_available_dlc.is_empty():
		return

	for dlc in _available_dlcs:
		if _dlc_entries_match(dlc, _selected_available_dlc):
			_selected_available_dlc = dlc.duplicate(true)
			return

	_selected_available_dlc.clear()


func _is_available_dlc_downloadable(dlc: Dictionary) -> bool:
	if bool(dlc.get("upcoming", false)):
		return true
	if bool(dlc.get("installed_current", false)):
		return false
	return true


func _create_empty_row(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.modulate = Color(0.80, 0.84, 0.88)
	return label


func _create_dlc_row(dlc: Dictionary, selectable: bool) -> Control:
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, 96)
	row.add_theme_stylebox_override("panel", _create_ui_texture_style(UI_FRAME_ORANGE_PATH))

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 4)
	row.add_child(layout)

	var header := HBoxContainer.new()
	layout.add_child(header)

	var name := Label.new()
	name.text = str(dlc.get("name", "Unnamed DLC"))
	name.add_theme_font_size_override("font_size", 18)
	header.add_child(name)

	var version := RichTextLabel.new()
	version.bbcode_enabled = true
	version.fit_content = true
	version.scroll_active = false
	version.text = "[i]%s[/i]" % _get_dlc_version_display(dlc)
	version.add_theme_font_size_override("normal_font_size", 18)
	version.add_theme_font_size_override("italics_font_size", 18)
	version.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(version)

	if bool(dlc.get("upcoming", false)):
		var upcoming_label := Label.new()
		upcoming_label.text = "Upcoming"
		upcoming_label.custom_minimum_size = Vector2(96, 34)
		upcoming_label.add_theme_font_size_override("font_size", 18)
		upcoming_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		upcoming_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		upcoming_label.modulate = Color(0.95, 0.84, 0.35)
		header.add_child(upcoming_label)
	elif selectable:
		if bool(dlc.get("installed_current", false)):
			var installed_label := _create_dlc_badge("Installed", Color(0.52, 0.95, 0.62))
			header.add_child(installed_label)
		else:
			var select_button := _create_small_button("Update" if bool(dlc.get("update_available", false)) else "Select")
			select_button.custom_minimum_size = Vector2(96, 34)
			select_button.pressed.connect(_select_available_dlc.bind(dlc))
			header.add_child(select_button)
	else:
		var installed_badge := _create_dlc_badge("Installed", Color(0.52, 0.95, 0.62))
		header.add_child(installed_badge)
		var uninstall_button := _create_small_button("Uninstall")
		uninstall_button.custom_minimum_size = Vector2(120, 34)
		_apply_button_text_color(uninstall_button, Color.WHITE)
		uninstall_button.pressed.connect(_request_uninstall_dlc.bind(dlc))
		header.add_child(uninstall_button)

	var description := Label.new()
	description.text = _get_dlc_description_display(dlc)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.modulate = Color(0.86, 0.89, 0.92)
	layout.add_child(description)

	return row


func _apply_button_text_color(button: Button, color: Color) -> void:
	button.add_theme_color_override("font_color", color)
	button.add_theme_color_override("font_hover_color", color)
	button.add_theme_color_override("font_pressed_color", color)
	button.add_theme_color_override("font_focus_color", color)
	button.add_theme_color_override("font_disabled_color", color)


func _create_dlc_badge(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(96, 34)
	label.add_theme_font_size_override("font_size", 18)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.modulate = color
	return label


func _get_dlc_version_display(dlc: Dictionary) -> String:
	var version := str(dlc.get("version", "unknown"))
	if version.is_empty():
		return ""
	if bool(dlc.get("upcoming", false)) or version.to_lower() == "upcoming":
		return version
	return "v%s" % version


func _get_dlc_description_display(dlc: Dictionary) -> String:
	var description := str(dlc.get("description", "No description provided."))
	if bool(dlc.get("update_available", false)):
		var installed_version := str(dlc.get("installed_version", "unknown"))
		return "%s\nInstalled: %s" % [description, _format_dlc_version(installed_version)]
	if bool(dlc.get("installed_current", false)):
		return "%s\nAlready installed locally." % description
	return description


func _format_dlc_version(version: String) -> String:
	if version.is_empty() or version == "unknown":
		return "unknown"
	if version.to_lower() == "upcoming":
		return version
	return "v%s" % version


func _select_available_dlc(dlc: Dictionary) -> void:
	if bool(dlc.get("upcoming", false)):
		_selected_available_dlc.clear()
		_set_status("%s is upcoming and cannot be downloaded yet." % dlc.get("name", "DLC"))
		if _download_button != null:
			_download_button.disabled = true
		return

	if bool(dlc.get("installed_current", false)):
		_selected_available_dlc.clear()
		_set_status("%s is already installed locally." % dlc.get("name", "DLC"))
		if _download_button != null:
			_download_button.disabled = true
		return

	_selected_available_dlc = dlc.duplicate(true)
	if bool(dlc.get("update_available", false)):
		_set_status("Selected update for %s." % dlc.get("name", "DLC"))
	else:
		_set_status("Selected %s." % dlc.get("name", "DLC"))
	if _download_button != null:
		_download_button.disabled = false


func _set_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message


func _request_uninstall_dlc(dlc: Dictionary) -> void:
	_pending_dlc_confirmation_action = "uninstall"
	_pending_dlc_confirmation_data = dlc.duplicate(true)
	_dlc_confirmation_dialog.title = "Uninstall DLC"
	_dlc_confirmation_dialog.dialog_text = "Uninstall %s?\n\nThis deletes its installed DLC files." % str(dlc.get("name", "this DLC"))
	_dlc_confirmation_dialog.popup_centered()


func _request_clear_all_dlcs() -> void:
	if _installed_dlcs.is_empty():
		_set_status("No installed DLC to clear.")
		return

	_pending_dlc_confirmation_action = "clear_all"
	_pending_dlc_confirmation_data = {}
	_dlc_confirmation_dialog.title = "Clear All DLC"
	_dlc_confirmation_dialog.dialog_text = "Clear all installed DLC?\n\nThis deletes every installed DLC pack in the DLC folder."
	_dlc_confirmation_dialog.popup_centered()


func _on_dlc_confirmation_confirmed() -> void:
	match _pending_dlc_confirmation_action:
		"uninstall":
			_uninstall_dlc(_pending_dlc_confirmation_data)
		"clear_all":
			_clear_all_installed_dlcs()

	_pending_dlc_confirmation_action = ""
	_pending_dlc_confirmation_data = {}


func _uninstall_dlc(dlc: Dictionary) -> void:
	var install_path := str(dlc.get("install_path", ""))
	if install_path.is_empty():
		_set_status("Could not find installed path for %s." % str(dlc.get("name", "DLC")))
		return

	var error := _remove_dlc_path(install_path)
	if error != OK:
		_set_status("Could not uninstall %s. Error code: %s" % [str(dlc.get("name", "DLC")), error])
		return

	_scan_installed_dlcs()
	_refresh_dlc_lists()
	_show_dlc_restart_notice("Uninstalled %s." % str(dlc.get("name", "DLC")))


func _clear_all_installed_dlcs() -> void:
	var errors: Array[String] = []
	var removed_count := 0

	for dlc in _installed_dlcs.duplicate(true):
		var install_path := str(dlc.get("install_path", ""))
		if install_path.is_empty():
			continue

		var error := _remove_dlc_path(install_path)
		if error == OK or error == ERR_FILE_NOT_FOUND:
			removed_count += 1
		else:
			errors.append("%s (%s)" % [str(dlc.get("name", "DLC")), error])

	_scan_installed_dlcs()
	_refresh_dlc_lists()

	if errors.is_empty():
		_show_dlc_restart_notice("Cleared %s installed DLC entr%s." % [
			removed_count,
			"y" if removed_count == 1 else "ies",
		])
	else:
		_set_status("Cleared %s DLC entr%s. Failed: %s" % [
			removed_count,
			"y" if removed_count == 1 else "ies",
			", ".join(errors),
		])
		if removed_count > 0:
			_show_dlc_restart_notice("Some DLC was cleared.")


func _remove_dlc_path(path: String) -> int:
	if not _is_path_inside_dlc_install_dir(path):
		push_warning("Refusing to delete path outside DLC install dir: %s" % path)
		return ERR_UNAUTHORIZED

	var absolute_path := _to_absolute_filesystem_path(path)
	if DirAccess.dir_exists_absolute(absolute_path):
		return _remove_directory_recursive(absolute_path)
	if FileAccess.file_exists(absolute_path):
		return DirAccess.remove_absolute(absolute_path)
	return ERR_FILE_NOT_FOUND


func _remove_directory_recursive(absolute_path: String) -> int:
	var dir := DirAccess.open(absolute_path)
	if dir == null:
		return DirAccess.get_open_error()

	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var entry_path := _join_paths(absolute_path, entry)
		var error := OK
		if dir.current_is_dir():
			error = _remove_directory_recursive(entry_path)
		else:
			error = DirAccess.remove_absolute(entry_path)
		if error != OK:
			dir.list_dir_end()
			return error
		entry = dir.get_next()
	dir.list_dir_end()

	return DirAccess.remove_absolute(absolute_path)


func _is_path_inside_dlc_install_dir(path: String) -> bool:
	var absolute_path := _normalize_filesystem_path(_to_absolute_filesystem_path(path))
	var dlc_root := _normalize_filesystem_path(_to_absolute_filesystem_path(_get_dlc_install_dir()))
	return absolute_path == dlc_root or absolute_path.begins_with(dlc_root + "/")


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
			dlc["source"] = "web"
			_apply_install_state_to_available_dlc(dlc)
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
	if bool(_selected_available_dlc.get("upcoming", false)):
		_set_status("%s is upcoming and cannot be downloaded yet." % _selected_available_dlc.get("name", "DLC"))
		return
	if _is_available_dlc_current(_selected_available_dlc):
		_set_status("%s is already installed locally." % _selected_available_dlc.get("name", "DLC"))
		_selected_available_dlc.clear()
		if _download_button != null:
			_download_button.disabled = true
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
				"manifest_path": _join_paths(_join_paths(_get_dlc_install_dir(), dlc_folder), "manifest.json"),
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


func _sync_available_dlc_install_state() -> void:
	for dlc in _available_dlcs:
		_apply_install_state_to_available_dlc(dlc)


func _apply_install_state_to_available_dlc(dlc: Dictionary) -> void:
	var installed := _find_installed_dlc_for_available(dlc)
	if installed.is_empty():
		dlc["installed"] = false
		dlc["installed_current"] = false
		dlc["update_available"] = false
		dlc.erase("installed_version")
		return

	var installed_version := str(installed.get("version", "unknown"))
	dlc["installed"] = true
	dlc["installed_version"] = installed_version
	dlc["installed_current"] = not _is_remote_version_newer(dlc, installed)
	dlc["update_available"] = _is_remote_version_newer(dlc, installed)


func _find_installed_dlc_for_available(dlc: Dictionary) -> Dictionary:
	for installed in _installed_dlcs:
		if _dlc_entries_match(installed, dlc):
			return installed
	return {}


func _is_available_dlc_current(dlc: Dictionary) -> bool:
	_apply_install_state_to_available_dlc(dlc)
	return bool(dlc.get("installed_current", false))


func _is_remote_version_newer(remote_dlc: Dictionary, installed_dlc: Dictionary) -> bool:
	var remote_version := str(remote_dlc.get("version", "unknown"))
	var installed_version := str(installed_dlc.get("version", "unknown"))
	return _compare_dlc_versions(remote_version, installed_version) > 0


func _compare_dlc_versions(left: String, right: String) -> int:
	var clean_left := left.strip_edges().to_lower()
	var clean_right := right.strip_edges().to_lower()
	if clean_left == clean_right:
		return 0
	if clean_left.is_empty() or clean_left == "unknown" or clean_left == "upcoming":
		return 0
	if clean_right.is_empty() or clean_right == "unknown" or clean_right == "upcoming":
		return 0

	var left_parts := clean_left.split(".", false)
	var right_parts := clean_right.split(".", false)
	var part_count := maxi(left_parts.size(), right_parts.size())
	for index in range(part_count):
		var left_part := int(left_parts[index]) if index < left_parts.size() and left_parts[index].is_valid_int() else 0
		var right_part := int(right_parts[index]) if index < right_parts.size() and right_parts[index].is_valid_int() else 0
		if left_part > right_part:
			return 1
		if left_part < right_part:
			return -1
	return 0


func _dlc_entries_match(left: Dictionary, right: Dictionary) -> bool:
	var identifiers: Array[String] = [
		str(right.get("id", "")),
		str(right.get("name", "")),
		str(right.get("path", "")),
		str(right.get("remote_path", "")),
	]
	for pck_file in right.get("pck_files", []):
		identifiers.append(str(pck_file))

	for identifier in identifiers:
		if not identifier.is_empty() and _dlc_matches_identifier(left, identifier):
			return true
	return false


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
		var dependency_dlc := _find_available_dlc(dependency_id)
		if dependency_dlc.is_empty() and _is_dlc_installed(dependency_id):
			continue
		if dependency_dlc.is_empty():
			missing.append(dependency_id)
		elif _is_available_dlc_current(dependency_dlc):
			continue
		else:
			_resolve_dlc_dependencies_recursive(dependency_dlc, ordered, visiting, visited, missing, circular)

	visiting.erase(id)
	visited[id] = true
	if not _is_available_dlc_current(dlc):
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
		_refresh_dlc_lists()
		_show_dlc_restart_notice("Installed DLC pack files.")
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
	_write_downloaded_dlc_manifest(download_info)
	ProjectSettings.load_resource_pack(target_path, true)
	_download_next_pck()


func _write_downloaded_dlc_manifest(download_info: Dictionary) -> void:
	var manifest_path := str(download_info.get("manifest_path", ""))
	if manifest_path.is_empty():
		return

	_make_dir_recursive(manifest_path.get_base_dir())
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if file == null:
		push_warning("Could not save DLC manifest: %s" % manifest_path)
		return

	file.store_string(JSON.stringify(_create_saved_dlc_manifest(download_info.get("dlc", {})), "\t"))
	file.close()


func _create_saved_dlc_manifest(dlc) -> Dictionary:
	if typeof(dlc) != TYPE_DICTIONARY:
		return {}

	return {
		"name": str(dlc.get("name", "")),
		"description": str(dlc.get("description", "")),
		"version": str(dlc.get("version", "unknown")),
		"upcoming": bool(dlc.get("upcoming", false)),
		"dependencies": dlc.get("dependencies", []),
		"pck_files": dlc.get("pck_files", []),
	}


func _show_dlc_restart_notice(message: String) -> void:
	_set_status("%s Restart the game to apply DLC changes." % message)
	if _dlc_restart_popup_message != null:
		_dlc_restart_popup_message.text = "%s\n\nRestart the game to apply DLC changes." % message
	if _dlc_restart_popup_layer != null:
		_dlc_restart_popup_layer.visible = true


func _hide_dlc_restart_popup() -> void:
	if _dlc_restart_popup_layer != null:
		_dlc_restart_popup_layer.visible = false


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
		path = DEFAULT_DLC_INSTALL_DIR
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


func _normalize_filesystem_path(path: String) -> String:
	return path.replace("\\", "/").trim_suffix("/").to_lower()


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
