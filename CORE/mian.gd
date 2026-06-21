extends Node2D

@export var selector_scene: PackedScene
@export var food_scene: PackedScene

# Position offsets to snap the UI above the fridge
@export var fridge_position: Vector2 = Vector2(100, 100)
@export var selector_offset: Vector2 = Vector2(0, -32)

@export var player_node: Node2D
@export var furniture_tilemap: TileMapLayer # Or TileMap for 4.2 and older
@export var items_tilemap: TileMapLayer
@export var hud_node: Node

const WRONG_ORDER_TEXTURE_PATH := "Complete_UI_Essential_Pack_Free/01_Flat_Theme/Sprites/UI_Flat_IconCross01a.png"
const SAVE_STATE_FILE_NAME := "save_state.json"
const MAIN_MENU_SCENE_PATH := "main_menu.tscn"
const UI_BUTTON_NORMAL_PATH := "Complete_UI_Essential_Pack_Free/01_Flat_Theme/Sprites/UI_Flat_Button01a_1.png"
const UI_BUTTON_HOVER_PATH := "Complete_UI_Essential_Pack_Free/01_Flat_Theme/Sprites/UI_Flat_Button01a_2.png"
const UI_BUTTON_PRESSED_PATH := "Complete_UI_Essential_Pack_Free/01_Flat_Theme/Sprites/UI_Flat_Button01a_3.png"
const UI_FRAME_PATH := "Complete_UI_Essential_Pack_Free/01_Flat_Theme/Sprites/UI_Flat_Frame02a.png"

# --- NEW: Capacity and Timer Settings ---
@export var max_item_count: int = 3
@export var restock_time: float = 5.0
@export var cutting_board_prep_time: float = 3.0
@export var oven_prep_time: float = 3.0
@export var food_spoil_time: float = 60.0
@export var counter_interaction_distance: float = 16.0
@export var regular_counter_interaction_distance: float = 24.0
@export var external_inventory_size: int = 1
@export var oven_inventory_size: int = 2
@export var external_inventory_detection_offset: Vector2 = Vector2(-8, 0)
@export var external_inventory_upward_tiles: int = 2
@export var order_idle_time: float = 3.0
@export var order_reward_min: int = 5
@export var order_reward_abs_max: int = 100
@export var order_reward_time_limit: float = 60.0

var food_items: Array = []
var item_counts: Array[int] = [] 
var fridge_menu: Array[int] = []
var current_index: int = 0
var item_restocking: Array[bool] = []

var active_selector: Node2D 
var active_storage_selector: Node2D
var active_fridge_grid_nodes: Array[Node] = []
var active_storage_grid_nodes: Array[Node] = []
var is_player_in_zone: bool = false
var held_item_frame: int = -1
var held_item_prep_progress: float = -1.0
var held_item_oven_progress: float = -1.0
var held_item_left_out_time: float = 0.0
var held_item_is_spoiled: bool = false
var held_item_cut_status: String = "uncut"
var held_item_food_status: String = "safe"
var counter_items: Dictionary = {}
var external_storage_cells: Array[Vector2i] = []
var external_storage_cell_ids: Dictionary = {}
var external_storage_positions: Dictionary = {}
var external_storage_items: Dictionary = {}
var external_storage_indices: Dictionary = {}
var external_storage_preview_nodes: Dictionary = {}
var external_storage_prep_progress: Dictionary = {}
var external_storage_oven_progress: Dictionary = {}
var external_storage_left_out_time: Dictionary = {}
var external_storage_spoiled: Dictionary = {}
var external_storage_cut_status: Dictionary = {}
var external_storage_food_status: Dictionary = {}
var current_storage_id: String = ""
var special_table_was_full: bool = false
var active_order: Array[Dictionary] = []
var order_idle_timer: float = 0.0
var active_order_elapsed_time: float = 0.0
var active_order_max_reward: int = 100
var coins: int = 0
var order_rng := RandomNumberGenerator.new()
var wrong_order_icon: Sprite2D
var wrong_order_texture: Texture2D
var pause_menu_layer: CanvasLayer
var is_pause_menu_open := false

const COUNTER_ATLAS_Y := 12
const COUNTER_ATLAS_MIN_X := 8
const COUNTER_ATLAS_MAX_X := 10
const BLOCKED_ITEM_ATLAS := Vector2i(6, 7)
const NO_COUNTER_CELL := Vector2i(-9999, -9999)
const NO_STORAGE_ID := ""
const OVEN_STORAGE_ID := "oven"
const SPECIAL_TABLE_STORAGE_ID := "special_table"
const OVEN_TOP_LEFT := Vector2i(23, 2)
const OVEN_BOTTOM_RIGHT := Vector2i(25, 6)
const TRASH_CAN_CELLS: Array[Vector2i] = [
	Vector2i(13, 6),
	Vector2i(13, 7),
]
const SPECIAL_TABLE_CELL := Vector2i(14, 6)
const SPECIAL_TABLE_CELLS: Array[Vector2i] = [
	Vector2i(14, 6),
	Vector2i(14, 7),
]
const SPECIAL_TABLE_INVENTORY_SIZE := 3
const SPECIAL_TABLE_SPOIL_TIME_MULTIPLIER := 3.0
const EXTERNAL_SLOT_SPACING := 4.0
const EXTERNAL_MIN_COLUMNS := 3
const SELECTOR_Z_INDEX := 1000
const SELECTOR_BACKGROUND_NAME := "background"
const SELECTOR_SCREEN_PADDING := 2.0
const SELECTOR_BACKGROUND_PADDING := 4.0
const FOOD_STATUS_ICON_NAME := "AnimatedSprite2D2"
const FOOD_PROGRESS_BAR_NAME := "ProgressBar"
const FOOD_STATUS_DEFAULT_FRAME := 0
const FOOD_STATUS_KNIFE_FRAME := 1
const CUT_STATUS_UNCUT := "uncut"
const CUT_STATUS_CUT := "cut"
const FOOD_ITEM_STATUS_SAFE := "safe"
const FOOD_ITEM_STATUS_COOKED := "cooked"
const FOOD_ITEM_STATUS_EXPIRED := "expired"
const FOOD_STATUS_NORMAL_COLOR := Color(0.2, 0.95, 0.35, 1.0)
const FOOD_STATUS_COOKED_COLOR := Color(1.0, 0.08, 0.04, 1.0)
const FOOD_STATUS_SPOILED_COLOR := Color(0.68, 0.18, 1.0, 1.0)
const VALID_COUNTER_CELLS: Array[Vector2i] = [
	Vector2i(20, 3),
	Vector2i(21, 3),
	Vector2i(25, 3),
]
const BANNED_COUNTER_CELLS: Array[Vector2i] = [
	Vector2i(22, 3),
]

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	fridge_menu = FoodIconRules.FRIDGE_MENU.duplicate()
	order_rng.randomize()
	load_save_state()
	wrong_order_texture = load(CorePaths.path(WRONG_ORDER_TEXTURE_PATH)) as Texture2D
	ensure_meat_frames_exposed()

	if not items_tilemap:
		items_tilemap = get_node_or_null("Items") as TileMapLayer
	if not hud_node:
		hud_node = get_node_or_null("HUD")
	update_coin_hud()

	active_selector = selector_scene.instantiate()
	active_selector.position = fridge_position + selector_offset
	add_child(active_selector)
	configure_grid_selector(active_selector)
	active_selector.hide()

	active_storage_selector = selector_scene.instantiate()
	add_child(active_storage_selector)
	configure_grid_selector(active_storage_selector)
	active_storage_selector.hide()

	# Loop through your specific menu array
	for i in range(fridge_menu.size()):
		var new_food = food_scene.instantiate()
		active_selector.add_child(new_food)
		
		var sprite = new_food.get_node("AnimatedSprite2D")
		sprite.frame = fridge_menu[i] 
		reset_food_prep_visuals(new_food)
		
		new_food.hide()
		food_items.append(new_food)
		item_counts.append(1)
		item_restocking.append(false)

	if food_items.size() > 0:
		update_labels()
		update_visuals()

	update_external_storage_areas()
	create_pause_menu()


func _process(delta):
	if is_pause_menu_open:
		return

	update_food_state_timers(delta)
	update_order_timer(delta)

	if player_node and furniture_tilemap:
		var in_fridge_zone = false
		var collision_node = player_node.get_node_or_null("CollisionShape2D")
		
		if collision_node and collision_node.shape:
			var local_rect = collision_node.shape.get_rect()
			var top_left_global = collision_node.to_global(local_rect.position)
			var bottom_right_global = collision_node.to_global(local_rect.position + local_rect.size)
			
			var top_left_cell = furniture_tilemap.local_to_map(top_left_global)
			var bottom_right_cell = furniture_tilemap.local_to_map(bottom_right_global)
			
			for x in range(top_left_cell.x, bottom_right_cell.x + 1):
				for y in range(top_left_cell.y, bottom_right_cell.y + 1):
					var cell = Vector2i(x, y)
					var atlas_coords = furniture_tilemap.get_cell_atlas_coords(cell)
					
					if atlas_coords.x >= 2 and atlas_coords.x <= 3 and atlas_coords.y >= 12 and atlas_coords.y <= 15:
						in_fridge_zone = true
						break 
				
				if in_fridge_zone:
					break 
					
		if in_fridge_zone:
			if not is_player_in_zone:
				is_player_in_zone = true
				active_selector.show()
				update_visuals()
			set_active_external_storage(NO_STORAGE_ID)
		else:
			if is_player_in_zone:
				is_player_in_zone = false
				active_selector.hide()
			set_active_external_storage(find_active_external_storage())


func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_pause_menu_open:
			return
		if handle_inventory_click():
			get_viewport().set_input_as_handled()
			return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			toggle_pause_menu()
			get_viewport().set_input_as_handled()
			return

		if is_pause_menu_open:
			return

		var index_changed = false

		if is_player_in_zone and event.keycode == KEY_Q and not food_items.is_empty():
			current_index = (current_index - 1 + food_items.size()) % food_items.size()
			index_changed = true
			
		elif is_player_in_zone and event.keycode == KEY_E and not food_items.is_empty():
			current_index = (current_index + 1) % food_items.size()
			index_changed = true

		elif current_storage_id != NO_STORAGE_ID and event.keycode == KEY_Q:
			cycle_external_storage_slot(-1)
			
		elif current_storage_id != NO_STORAGE_ID and event.keycode == KEY_E:
			cycle_external_storage_slot(1)
			
		elif event.keycode == KEY_W:
			if try_trash_held_item():
				pass
			elif is_player_in_zone:
				grab_item()
			elif current_storage_id != NO_STORAGE_ID:
				interact_with_external_storage()
			else:
				interact_with_counter()

		if index_changed:
			update_visuals()


func create_pause_menu() -> void:
	if pause_menu_layer:
		return

	pause_menu_layer = CanvasLayer.new()
	pause_menu_layer.name = "PauseMenu"
	pause_menu_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_menu_layer.visible = false
	add_child(pause_menu_layer)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_menu_layer.add_child(dim)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_menu_layer.add_child(center)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(320, 230)
	panel.add_theme_stylebox_override("panel", create_ui_texture_style(UI_FRAME_PATH))
	center.add_child(panel)

	var stack := VBoxContainer.new()
	stack.name = "Stack"
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 16)
	panel.add_child(stack)

	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	stack.add_child(title)

	var resume_button := create_pause_button("Resume")
	resume_button.pressed.connect(close_pause_menu)
	stack.add_child(resume_button)

	var exit_button := create_pause_button("Exit to Main Menu")
	exit_button.pressed.connect(exit_to_main_menu)
	stack.add_child(exit_button)


func create_pause_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(240, 54)
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", Color.BLACK)
	button.add_theme_color_override("font_hover_color", Color.BLACK)
	button.add_theme_color_override("font_pressed_color", Color.BLACK)
	button.add_theme_color_override("font_focus_color", Color.BLACK)
	button.add_theme_color_override("font_disabled_color", Color.BLACK)
	button.add_theme_stylebox_override("normal", create_ui_texture_style(UI_BUTTON_NORMAL_PATH))
	button.add_theme_stylebox_override("hover", create_ui_texture_style(UI_BUTTON_HOVER_PATH))
	button.add_theme_stylebox_override("pressed", create_ui_texture_style(UI_BUTTON_PRESSED_PATH))
	button.add_theme_stylebox_override("disabled", create_ui_texture_style(UI_BUTTON_NORMAL_PATH))
	return button


func create_ui_texture_style(texture_path: String) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = load(CorePaths.path(texture_path)) as Texture2D
	style.texture_margin_left = 6.0
	style.texture_margin_top = 6.0
	style.texture_margin_right = 6.0
	style.texture_margin_bottom = 6.0
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	return style


func toggle_pause_menu() -> void:
	if is_pause_menu_open:
		close_pause_menu()
	else:
		open_pause_menu()


func open_pause_menu() -> void:
	is_pause_menu_open = true
	if pause_menu_layer:
		pause_menu_layer.visible = true
	get_tree().paused = true


func close_pause_menu() -> void:
	load_save_state()
	update_coin_hud()
	is_pause_menu_open = false
	if pause_menu_layer:
		pause_menu_layer.visible = false
	get_tree().paused = false


func exit_to_main_menu() -> void:
	save_state()
	get_tree().paused = false
	get_tree().change_scene_to_file(CorePaths.path(MAIN_MENU_SCENE_PATH))


func update_visuals():
	clear_fridge_grid()

	if food_items.is_empty():
		return

	active_selector.position = fridge_position + selector_offset

	var selected_slot := active_selector.get_node_or_null("selected") as Sprite2D
	if not selected_slot:
		return

	var slot_count: int = food_items.size()
	var slot_step: Vector2 = get_selector_slot_step(selected_slot)
	var columns: int = get_selector_grid_columns(active_selector, selected_slot.position, slot_count, slot_step)
	var rows: int = ceili(float(slot_count) / float(columns))
	var start_position: Vector2 = get_selector_grid_start_position(selected_slot.position, columns, rows, slot_step)
	keep_selector_grid_on_screen(active_selector, start_position, columns, rows, slot_step)
	update_selector_background(active_selector, start_position, columns, rows, slot_step)

	for i in range(slot_count):
		var slot_position: Vector2 = get_selector_grid_slot_position(start_position, i, columns, slot_step)
		create_selector_slot_visual(active_selector, selected_slot, slot_position, i == current_index, active_fridge_grid_nodes)

		var food := food_items[i] as Node2D
		food.position = slot_position
		food.show()


# --- NEW: Visual Counter Logic ---
func update_labels():
	for i in range(food_items.size()):
		var label = food_items[i].get_node_or_null("CountLabel")
		if label:
			label.text = str(item_counts[i])


func update_selector_arrows(selector: Node, should_show: bool) -> void:
	var left_arrow := selector.get_node_or_null("left")
	if left_arrow:
		left_arrow.visible = should_show

	var right_arrow := selector.get_node_or_null("right")
	if right_arrow:
		right_arrow.visible = should_show


func configure_grid_selector(selector: Node2D) -> void:
	selector.z_as_relative = false
	selector.z_index = SELECTOR_Z_INDEX
	update_selector_arrows(selector, false)
	hide_selector_slot(selector)
	ensure_selector_background(selector)


func ensure_selector_background(selector: Node2D) -> Sprite2D:
	var background := selector.get_node_or_null(SELECTOR_BACKGROUND_NAME) as Sprite2D
	if not background:
		background = Sprite2D.new()
		background.name = SELECTOR_BACKGROUND_NAME
		background.texture_filter = 1
		background.z_index = -20
		selector.add_child(background)
		selector.move_child(background, 0)
	return background


func show_selector_slot(selector: Node) -> void:
	var selected_slot := selector.get_node_or_null("selected")
	if selected_slot:
		selected_slot.show()


func hide_selector_slot(selector: Node) -> void:
	var selected_slot := selector.get_node_or_null("selected")
	if selected_slot:
		selected_slot.hide()


func clear_fridge_grid() -> void:
	for node in active_fridge_grid_nodes:
		if is_instance_valid(node):
			node.queue_free()
	active_fridge_grid_nodes.clear()


func get_selector_grid_columns(selector: Node2D, center_position: Vector2, slot_count: int, slot_step: Vector2) -> int:
	if slot_count < EXTERNAL_MIN_COLUMNS:
		return slot_count

	var visible_rect: Rect2 = get_visible_world_rect()
	var columns: int = maxi(EXTERNAL_MIN_COLUMNS, ceili(sqrt(float(slot_count))))
	var best_columns: int = columns
	var best_overflow := INF
	while columns <= slot_count:
		var rows: int = ceili(float(slot_count) / float(columns))
		var start_position: Vector2 = get_selector_grid_start_position(center_position, columns, rows, slot_step)
		var grid_rect: Rect2 = get_selector_grid_rect(selector, start_position, columns, rows, slot_step)
		var overflow := get_rect_screen_overflow(grid_rect, visible_rect.grow(-SELECTOR_SCREEN_PADDING))
		if overflow < best_overflow:
			best_overflow = overflow
			best_columns = columns
		if overflow <= 0.0:
			break
		columns += 1
	return columns if columns <= slot_count else best_columns


func get_rect_screen_overflow(rect: Rect2, visible_rect: Rect2) -> float:
	var overflow := 0.0
	overflow += maxf(visible_rect.position.x - rect.position.x, 0.0)
	overflow += maxf(rect.end.x - visible_rect.end.x, 0.0)
	overflow += maxf(visible_rect.position.y - rect.position.y, 0.0)
	overflow += maxf(rect.end.y - visible_rect.end.y, 0.0)
	return overflow


func get_selector_slot_step(selected_slot: Sprite2D) -> Vector2:
	var slot_size := Vector2(16.0, 16.0)
	if selected_slot.texture:
		slot_size = selected_slot.texture.get_size() * selected_slot.scale.abs()
	return slot_size + Vector2(EXTERNAL_SLOT_SPACING, EXTERNAL_SLOT_SPACING)


func get_selector_grid_start_position(center_position: Vector2, columns: int, rows: int, slot_step: Vector2) -> Vector2:
	var grid_size := Vector2(
		float(columns - 1) * slot_step.x,
		float(rows - 1) * slot_step.y
	)
	return center_position - grid_size * 0.5


func get_selector_grid_slot_position(start_position: Vector2, index: int, columns: int, slot_step: Vector2) -> Vector2:
	var column: int = index % columns
	var row: int = floori(float(index) / float(columns))
	return start_position + Vector2(float(column) * slot_step.x, float(row) * slot_step.y)


func get_selector_grid_rect(selector: Node2D, start_position: Vector2, columns: int, rows: int, slot_step: Vector2) -> Rect2:
	var local_top_left: Vector2 = start_position - slot_step * 0.5 - Vector2(SELECTOR_BACKGROUND_PADDING, SELECTOR_BACKGROUND_PADDING)
	var size: Vector2 = get_selector_background_size(columns, rows, slot_step)
	return Rect2(selector.position + local_top_left, size)


func get_selector_background_size(columns: int, rows: int, slot_step: Vector2) -> Vector2:
	return Vector2(float(columns) * slot_step.x, float(rows) * slot_step.y) + Vector2(SELECTOR_BACKGROUND_PADDING * 2.0, SELECTOR_BACKGROUND_PADDING * 2.0)


func update_selector_background(selector: Node2D, start_position: Vector2, columns: int, rows: int, slot_step: Vector2) -> void:
	var background: Sprite2D = ensure_selector_background(selector)
	var background_size: Vector2 = get_selector_background_size(columns, rows, slot_step)
	var background_top_left: Vector2 = start_position - slot_step * 0.5 - Vector2(SELECTOR_BACKGROUND_PADDING, SELECTOR_BACKGROUND_PADDING)
	background.position = background_top_left + background_size * 0.5

	if background.texture:
		var texture_size: Vector2 = background.texture.get_size()
		if texture_size.x > 0.0 and texture_size.y > 0.0:
			background.scale = Vector2(background_size.x / texture_size.x, background_size.y / texture_size.y)


func get_visible_world_rect() -> Rect2:
	var viewport_rect: Rect2 = get_viewport_rect()
	var canvas_inverse: Transform2D = get_viewport().get_canvas_transform().affine_inverse()
	var top_left: Vector2 = canvas_inverse * viewport_rect.position
	var bottom_right: Vector2 = canvas_inverse * (viewport_rect.position + viewport_rect.size)
	return Rect2(top_left, bottom_right - top_left).abs()


func keep_selector_grid_on_screen(selector: Node2D, start_position: Vector2, columns: int, rows: int, slot_step: Vector2) -> void:
	var visible_rect: Rect2 = get_visible_world_rect().grow(-SELECTOR_SCREEN_PADDING)
	var grid_rect: Rect2 = get_selector_grid_rect(selector, start_position, columns, rows, slot_step)
	var position_adjustment: Vector2 = Vector2.ZERO

	if grid_rect.position.x < visible_rect.position.x:
		position_adjustment.x = visible_rect.position.x - grid_rect.position.x
	elif grid_rect.end.x > visible_rect.end.x:
		position_adjustment.x = visible_rect.end.x - grid_rect.end.x

	if grid_rect.position.y < visible_rect.position.y:
		position_adjustment.y = visible_rect.position.y - grid_rect.position.y
	elif grid_rect.end.y > visible_rect.end.y:
		position_adjustment.y = visible_rect.end.y - grid_rect.end.y

	selector.position += position_adjustment


func create_selector_slot_visual(
	selector: Node2D,
	template_slot: Sprite2D,
	slot_position: Vector2,
	is_selected: bool,
	tracked_nodes: Array[Node]
) -> void:
	var slot_visual := Sprite2D.new()
	slot_visual.texture_filter = template_slot.texture_filter
	slot_visual.texture = template_slot.texture
	slot_visual.position = slot_position
	slot_visual.scale = template_slot.scale
	slot_visual.z_index = -5
	if is_selected:
		slot_visual.modulate = Color.WHITE
	else:
		slot_visual.modulate = Color(1.0, 1.0, 1.0, 0.35)
	selector.add_child(slot_visual)
	tracked_nodes.append(slot_visual)


func handle_inventory_click() -> bool:
	if is_player_in_zone:
		var fridge_index := get_clicked_selector_index(active_selector, food_items.size())
		if fridge_index >= 0:
			current_index = fridge_index
			update_visuals()
			grab_item()
			return true

	if current_storage_id != NO_STORAGE_ID and external_storage_items.has(current_storage_id):
		var slots: Array = external_storage_items[current_storage_id]
		var storage_index := get_clicked_selector_index(active_storage_selector, slots.size())
		if storage_index >= 0:
			external_storage_indices[current_storage_id] = storage_index
			update_external_storage_visual()
			interact_with_external_storage()
			return true

	return false


func get_clicked_selector_index(selector: Node2D, slot_count: int) -> int:
	if slot_count <= 0 or not selector.visible:
		return -1

	var selected_slot := selector.get_node_or_null("selected") as Sprite2D
	if not selected_slot:
		return -1

	var slot_step: Vector2 = get_selector_slot_step(selected_slot)
	var columns: int = get_selector_grid_columns(selector, selected_slot.position, slot_count, slot_step)
	var rows: int = ceili(float(slot_count) / float(columns))
	var start_position: Vector2 = get_selector_grid_start_position(selected_slot.position, columns, rows, slot_step)
	var local_mouse := selector.to_local(get_global_mouse_position())

	for i in range(slot_count):
		var slot_position: Vector2 = get_selector_grid_slot_position(start_position, i, columns, slot_step)
		var slot_rect := Rect2(slot_position - slot_step * 0.5, slot_step)
		if slot_rect.has_point(local_mouse):
			return i

	return -1


func grab_item():
	if food_items.is_empty():
		return
	if item_counts[current_index] <= 0 or not is_inventory_free():
		return

	item_counts[current_index] -= 1
	held_item_frame = fridge_menu[current_index]
	held_item_prep_progress = -1.0
	held_item_oven_progress = -1.0
	held_item_left_out_time = 0.0
	held_item_is_spoiled = false
	refresh_held_item_status()
	update_held_item_hud()

	update_labels()
	
	if not item_restocking[current_index]:
		restock_loop(current_index)


func interact_with_counter():
	if not player_node or not furniture_tilemap or not items_tilemap:
		return

	if is_inventory_free():
		pick_up_counter_item()
	else:
		place_counter_item()


func try_trash_held_item() -> bool:
	if current_storage_id == SPECIAL_TABLE_STORAGE_ID:
		return false
	if is_inventory_free() or not is_player_at_trash_can():
		return false

	clear_inventory()
	return true


func is_player_at_trash_can() -> bool:
	return is_interaction_cell_in(TRASH_CAN_CELLS)


func update_external_storage_areas() -> void:
	external_storage_cells.clear()
	external_storage_cell_ids.clear()
	external_storage_positions.clear()
	if not furniture_tilemap or not items_tilemap:
		return

	for cell in items_tilemap.get_used_cells():
		if is_counter_storage_cell(cell):
			var counter_cells: Array[Vector2i] = [cell]
			register_external_storage_area(get_counter_storage_id(cell), counter_cells, cell)

	register_external_storage_area(OVEN_STORAGE_ID, get_oven_storage_cells(), OVEN_TOP_LEFT)
	register_external_storage_area(SPECIAL_TABLE_STORAGE_ID, SPECIAL_TABLE_CELLS, SPECIAL_TABLE_CELL)


func is_counter_storage_cell(cell: Vector2i) -> bool:
	return is_blocked_counter_cell(cell)


func get_counter_storage_id(cell: Vector2i) -> String:
	return "counter_%s_%s" % [cell.x, cell.y]


func register_external_storage_area(storage_id: String, cells: Array[Vector2i], anchor_cell: Vector2i) -> void:
	if get_external_storage_size(storage_id) <= 0 or cells.is_empty():
		return

	if not external_storage_items.has(storage_id):
		external_storage_items[storage_id] = create_empty_external_storage_slots(storage_id)
	else:
		external_storage_items[storage_id] = resize_external_storage_slots(storage_id, external_storage_items[storage_id])
	if not external_storage_indices.has(storage_id):
		external_storage_indices[storage_id] = 0
	else:
		external_storage_indices[storage_id] = clampi(int(external_storage_indices[storage_id]), 0, get_external_storage_size(storage_id) - 1)
	if not external_storage_prep_progress.has(storage_id):
		external_storage_prep_progress[storage_id] = create_empty_prep_progress_slots(storage_id)
	else:
		external_storage_prep_progress[storage_id] = resize_prep_progress_slots(storage_id, external_storage_prep_progress[storage_id])
	if not external_storage_oven_progress.has(storage_id):
		external_storage_oven_progress[storage_id] = create_empty_oven_progress_slots(storage_id)
	else:
		external_storage_oven_progress[storage_id] = resize_oven_progress_slots(storage_id, external_storage_oven_progress[storage_id])
	if not external_storage_left_out_time.has(storage_id):
		external_storage_left_out_time[storage_id] = create_empty_left_out_time_slots(storage_id)
	else:
		external_storage_left_out_time[storage_id] = resize_left_out_time_slots(storage_id, external_storage_left_out_time[storage_id])
	if not external_storage_spoiled.has(storage_id):
		external_storage_spoiled[storage_id] = create_empty_spoiled_slots(storage_id)
	else:
		external_storage_spoiled[storage_id] = resize_spoiled_slots(storage_id, external_storage_spoiled[storage_id])
	if not external_storage_cut_status.has(storage_id):
		external_storage_cut_status[storage_id] = create_empty_cut_status_slots(storage_id)
	else:
		external_storage_cut_status[storage_id] = resize_cut_status_slots(storage_id, external_storage_cut_status[storage_id])
	if not external_storage_food_status.has(storage_id):
		external_storage_food_status[storage_id] = create_empty_food_status_slots(storage_id)
	else:
		external_storage_food_status[storage_id] = resize_food_status_slots(storage_id, external_storage_food_status[storage_id])

	external_storage_positions[storage_id] = anchor_cell
	for cell in cells:
		external_storage_cells.append(cell)
		external_storage_cell_ids[cell] = storage_id


func create_empty_external_storage_slots(storage_id: String) -> Array[int]:
	var slots: Array[int] = []
	for _i in range(get_external_storage_size(storage_id)):
		slots.append(-1)
	return slots


func resize_external_storage_slots(storage_id: String, existing_slots: Array) -> Array[int]:
	var slots: Array[int] = []
	for i in range(get_external_storage_size(storage_id)):
		if i < existing_slots.size():
			slots.append(int(existing_slots[i]))
		else:
			slots.append(-1)
	return slots


func create_empty_prep_progress_slots(storage_id: String) -> Array[float]:
	var progress: Array[float] = []
	for _i in range(get_external_storage_size(storage_id)):
		progress.append(-1.0)
	return progress


func resize_prep_progress_slots(storage_id: String, existing_progress: Array) -> Array[float]:
	var progress: Array[float] = []
	for i in range(get_external_storage_size(storage_id)):
		if i < existing_progress.size():
			progress.append(float(existing_progress[i]))
		else:
			progress.append(-1.0)
	return progress


func create_empty_oven_progress_slots(storage_id: String) -> Array[float]:
	var progress: Array[float] = []
	for _i in range(get_external_storage_size(storage_id)):
		progress.append(-1.0)
	return progress


func resize_oven_progress_slots(storage_id: String, existing_progress: Array) -> Array[float]:
	var progress: Array[float] = []
	for i in range(get_external_storage_size(storage_id)):
		if i < existing_progress.size():
			progress.append(float(existing_progress[i]))
		else:
			progress.append(-1.0)
	return progress


func create_empty_left_out_time_slots(storage_id: String) -> Array[float]:
	var timers: Array[float] = []
	for _i in range(get_external_storage_size(storage_id)):
		timers.append(0.0)
	return timers


func resize_left_out_time_slots(storage_id: String, existing_timers: Array) -> Array[float]:
	var timers: Array[float] = []
	for i in range(get_external_storage_size(storage_id)):
		if i < existing_timers.size():
			timers.append(float(existing_timers[i]))
		else:
			timers.append(0.0)
	return timers


func create_empty_spoiled_slots(storage_id: String) -> Array[bool]:
	var spoiled: Array[bool] = []
	for _i in range(get_external_storage_size(storage_id)):
		spoiled.append(false)
	return spoiled


func resize_spoiled_slots(storage_id: String, existing_spoiled: Array) -> Array[bool]:
	var spoiled: Array[bool] = []
	for i in range(get_external_storage_size(storage_id)):
		if i < existing_spoiled.size():
			spoiled.append(bool(existing_spoiled[i]))
		else:
			spoiled.append(false)
	return spoiled


func create_empty_cut_status_slots(storage_id: String) -> Array[String]:
	var cut_status: Array[String] = []
	for _i in range(get_external_storage_size(storage_id)):
		cut_status.append(CUT_STATUS_UNCUT)
	return cut_status


func resize_cut_status_slots(storage_id: String, existing_status: Array) -> Array[String]:
	var cut_status: Array[String] = []
	for i in range(get_external_storage_size(storage_id)):
		if i < existing_status.size():
			cut_status.append(String(existing_status[i]))
		else:
			cut_status.append(CUT_STATUS_UNCUT)
	return cut_status


func create_empty_food_status_slots(storage_id: String) -> Array[String]:
	var food_status: Array[String] = []
	for _i in range(get_external_storage_size(storage_id)):
		food_status.append(FOOD_ITEM_STATUS_SAFE)
	return food_status


func resize_food_status_slots(storage_id: String, existing_status: Array) -> Array[String]:
	var food_status: Array[String] = []
	for i in range(get_external_storage_size(storage_id)):
		if i < existing_status.size():
			food_status.append(String(existing_status[i]))
		else:
			food_status.append(FOOD_ITEM_STATUS_SAFE)
	return food_status


func ensure_meat_frames_exposed() -> void:
	if fridge_menu_has_meat():
		return

	for frame in FoodIconRules.MEAT_FRAMES:
		if not fridge_menu.has(frame):
			fridge_menu.append(frame)


func fridge_menu_has_meat() -> bool:
	for frame in fridge_menu:
		if is_meat_frame(frame):
			return true
	return false


func is_meat_frame(frame: int) -> bool:
	return FoodIconRules.is_meat_frame(frame)


func can_order_cut(frame: int) -> bool:
	return is_cuttable_frame(frame)


func can_order_cooked(frame: int) -> bool:
	if is_never_cook_frame(frame):
		return false
	return is_meat_frame(frame) or FoodIconRules.is_cookable_frame(frame)


func is_cuttable_frame(frame: int) -> bool:
	return FoodIconRules.is_cuttable_frame(frame)


func is_never_cook_frame(frame: int) -> bool:
	return FoodIconRules.is_never_cook_frame(frame)


func update_order_timer(delta: float) -> void:
	if not active_order.is_empty():
		active_order_elapsed_time += delta
		order_idle_timer = 0.0
		return

	order_idle_timer += delta
	if order_idle_timer >= order_idle_time:
		create_order()


func create_order() -> void:
	active_order.clear()
	order_idle_timer = 0.0
	active_order_elapsed_time = 0.0
	var reward_min := clampi(order_reward_min, 0, 100)
	var reward_max := clampi(order_reward_abs_max, reward_min, 100)
	active_order_max_reward = order_rng.randi_range(reward_min, reward_max)

	var candidates: Array[int] = []
	for frame in fridge_menu:
		if not candidates.has(frame):
			candidates.append(frame)
	if candidates.is_empty():
		for frame in FoodIconRules.MEAT_FRAMES:
			if not candidates.has(frame):
				candidates.append(frame)
	if candidates.is_empty():
		return

	for i in range(SPECIAL_TABLE_INVENTORY_SIZE):
		var candidate_index := order_rng.randi_range(0, candidates.size() - 1)
		var frame := int(candidates[candidate_index])
		if candidates.size() > 1:
			candidates.remove_at(candidate_index)
		active_order.append(create_order_item(frame, i))

	update_order_hud()
	print("New order: ", active_order)
	if external_storage_items.has(SPECIAL_TABLE_STORAGE_ID) and is_external_storage_full(SPECIAL_TABLE_STORAGE_ID):
		special_table_was_full = false
		update_special_table_full_state()


func create_order_item(frame: int, _order_index: int) -> Dictionary:
	var cut_status := CUT_STATUS_UNCUT
	if can_order_cut(frame) and order_rng.randi_range(0, 1) == 1:
		cut_status = CUT_STATUS_CUT
	var food_status := FOOD_ITEM_STATUS_SAFE
	if is_meat_frame(frame) and can_order_cooked(frame):
		food_status = FOOD_ITEM_STATUS_COOKED
	elif can_order_cooked(frame) and order_rng.randi_range(0, 1) == 1:
		food_status = FOOD_ITEM_STATUS_COOKED

	return {
		"frame": frame,
		"cut_status": cut_status,
		"food_status": food_status
	}


func update_order_hud() -> void:
	if not hud_node:
		return

	if active_order.is_empty():
		if hud_node.has_method("clear_order"):
			hud_node.call("clear_order")
	elif hud_node.has_method("set_order"):
		hud_node.call("set_order", active_order)


func update_coin_hud() -> void:
	if hud_node and hud_node.has_method("set_coins"):
		hud_node.call("set_coins", coins)


func load_save_state() -> void:
	var save_path := get_local_save_state_path()
	if not FileAccess.file_exists(save_path):
		return

	var text := FileAccess.get_file_as_string(save_path)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return

	var core_save = parsed.get("core", {})
	if typeof(core_save) == TYPE_DICTIONARY and core_save.has("coins"):
		coins = maxi(0, int(core_save.get("coins", 0)))
	elif parsed.has("coins"):
		coins = maxi(0, int(parsed.get("coins", 0)))


func save_state() -> void:
	var file := FileAccess.open(get_local_save_state_path(), FileAccess.WRITE)
	if file == null:
		push_warning("Could not save game state.")
		return

	file.store_string(JSON.stringify({
		"core": {
			"coins": coins,
		},
	}))
	file.close()


func get_local_save_state_path() -> String:
	if OS.has_feature("editor"):
		return "res://%s" % SAVE_STATE_FILE_NAME
	return "%s/%s" % [OS.get_executable_path().get_base_dir(), SAVE_STATE_FILE_NAME]


func complete_order() -> void:
	var reward := calculate_order_reward()
	coins += reward
	save_state()
	print("Order complete: ", active_order)
	print("Coins earned: ", reward, " Total coins: ", coins)
	active_order.clear()
	order_idle_timer = 0.0
	active_order_elapsed_time = 0.0
	hide_wrong_order_indicator()
	update_order_hud()
	update_coin_hud()


func calculate_order_reward() -> int:
	var reward_min := clampi(order_reward_min, 0, 100)
	var reward_max := clampi(order_reward_abs_max, reward_min, 100)
	var reward_range := maxi(active_order_max_reward - reward_min, 0)
	var time_ratio := clampf(active_order_elapsed_time / maxf(order_reward_time_limit, 0.001), 0.0, 1.0)
	var reward := active_order_max_reward - roundi(float(reward_range) * time_ratio)
	return clampi(reward, reward_min, reward_max)


func get_external_storage_size(storage_id: String = current_storage_id) -> int:
	if storage_id == OVEN_STORAGE_ID:
		return oven_inventory_size
	if storage_id == SPECIAL_TABLE_STORAGE_ID:
		return SPECIAL_TABLE_INVENTORY_SIZE
	return external_inventory_size


func update_special_table_full_state() -> void:
	if not external_storage_items.has(SPECIAL_TABLE_STORAGE_ID):
		special_table_was_full = false
		hide_wrong_order_indicator()
		return

	var is_full := is_external_storage_full(SPECIAL_TABLE_STORAGE_ID)
	if not is_full:
		hide_wrong_order_indicator()
	if is_full and not special_table_was_full:
		on_special_table_filled()
	special_table_was_full = is_full


func is_external_storage_full(storage_id: String) -> bool:
	if not external_storage_items.has(storage_id):
		return false

	var slots: Array = external_storage_items[storage_id]
	if slots.is_empty():
		return false

	for slot in slots:
		if int(slot) < 0:
			return false

	return true


func on_special_table_filled() -> void:
	if active_order.is_empty():
		print("Special table is full, but there is no active order.")
		hide_wrong_order_indicator()
		return

	if not does_special_table_match_active_order():
		print("Special table does not match active order.")
		show_wrong_order_indicator()
		return

	hide_wrong_order_indicator()
	var slots: Array = external_storage_items[SPECIAL_TABLE_STORAGE_ID]
	for i in range(slots.size()):
		slots[i] = -1
		clear_external_storage_item_state(SPECIAL_TABLE_STORAGE_ID, i)

	external_storage_items[SPECIAL_TABLE_STORAGE_ID] = slots
	special_table_was_full = false
	complete_order()
	update_external_storage_visual()


func show_wrong_order_indicator() -> void:
	if not furniture_tilemap:
		return

	if not wrong_order_icon:
		if not wrong_order_texture:
			return
		wrong_order_icon = Sprite2D.new()
		wrong_order_icon.name = "wrong_order_icon"
		wrong_order_icon.texture = wrong_order_texture
		wrong_order_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		wrong_order_icon.scale = Vector2(0.75, 0.75)
		wrong_order_icon.z_index = SELECTOR_Z_INDEX
		add_child(wrong_order_icon)

	var table_position := furniture_tilemap.to_global(furniture_tilemap.map_to_local(SPECIAL_TABLE_CELL))
	wrong_order_icon.position = to_local(table_position) + Vector2(0.0, -18.0)
	wrong_order_icon.show()


func hide_wrong_order_indicator() -> void:
	if wrong_order_icon:
		wrong_order_icon.hide()


func does_special_table_match_active_order() -> bool:
	var slots: Array = external_storage_items[SPECIAL_TABLE_STORAGE_ID]
	if active_order.size() != slots.size():
		return false

	var matched_slots: Array[int] = []
	for order_item in active_order:
		var found_slot := -1
		for i in range(slots.size()):
			if matched_slots.has(i):
				continue
			if order_item_matches_special_table_slot(order_item, i):
				found_slot = i
				break

		if found_slot < 0:
			return false
		matched_slots.append(found_slot)

	return true


func order_item_matches_special_table_slot(order_item: Dictionary, slot_index: int) -> bool:
	var slots: Array = external_storage_items[SPECIAL_TABLE_STORAGE_ID]
	if slot_index < 0 or slot_index >= slots.size():
		return false

	var frame := int(order_item.get("frame", -1))
	var cut_status := String(order_item.get("cut_status", CUT_STATUS_UNCUT))
	var food_status := String(order_item.get("food_status", FOOD_ITEM_STATUS_SAFE))
	var slot_cut_status := get_external_storage_slot_string(external_storage_cut_status, SPECIAL_TABLE_STORAGE_ID, slot_index, CUT_STATUS_UNCUT)
	var slot_food_status := get_external_storage_slot_string(external_storage_food_status, SPECIAL_TABLE_STORAGE_ID, slot_index, FOOD_ITEM_STATUS_SAFE)

	return int(slots[slot_index]) == frame and slot_cut_status == cut_status and slot_food_status == food_status


func get_oven_storage_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(OVEN_TOP_LEFT.y, OVEN_BOTTOM_RIGHT.y + 1):
		cells.append(Vector2i(OVEN_TOP_LEFT.x, y))
	return cells


func find_active_external_storage() -> String:
	if external_storage_cells.is_empty() or not player_node or not furniture_tilemap:
		return NO_STORAGE_ID

	if is_interaction_cell_in(SPECIAL_TABLE_CELLS):
		return SPECIAL_TABLE_STORAGE_ID

	var interaction_position := get_external_inventory_detection_position()
	var interaction_cell := furniture_tilemap.local_to_map(furniture_tilemap.to_local(interaction_position))

	for y_offset in range(0, external_inventory_upward_tiles + 1):
		var target_cell := interaction_cell + Vector2i(0, -y_offset)
		if external_storage_cell_ids.has(target_cell):
			var storage_id := String(external_storage_cell_ids[target_cell])
			if storage_id != SPECIAL_TABLE_STORAGE_ID:
				return storage_id

	return NO_STORAGE_ID


func get_nearby_interaction_cell(tilemap: TileMapLayer, cells: Array[Vector2i]) -> Vector2i:
	return get_nearby_interaction_cell_at_position(tilemap, cells, get_tile_in_front_position())


func is_interaction_cell_in(cells: Array[Vector2i]) -> bool:
	if cells.is_empty():
		return false

	var positions: Array[Vector2] = [
		get_tile_in_front_position(),
		get_external_inventory_detection_position(),
	]
	var tilemaps: Array[TileMapLayer] = []
	if furniture_tilemap:
		tilemaps.append(furniture_tilemap)
	if items_tilemap:
		tilemaps.append(items_tilemap)

	for tilemap in tilemaps:
		for position in positions:
			var cell := tilemap.local_to_map(tilemap.to_local(position))
			if cells.has(cell):
				return true

	return false


func is_player_near_cells(cells: Array[Vector2i]) -> bool:
	if cells.is_empty() or not player_node:
		return false

	var tilemaps: Array[TileMapLayer] = []
	if furniture_tilemap:
		tilemaps.append(furniture_tilemap)
	if items_tilemap:
		tilemaps.append(items_tilemap)

	for tilemap in tilemaps:
		if get_nearby_interaction_cell_at_position(tilemap, cells, get_tile_in_front_position()) != NO_COUNTER_CELL:
			return true
		if get_nearby_interaction_cell_at_position(tilemap, cells, get_external_inventory_detection_position()) != NO_COUNTER_CELL:
			return true

		var player_cells := get_player_cells(tilemap, 1)
		for cell in cells:
			if player_cells.has(cell):
				return true

	return false


func get_nearby_interaction_cell_at_position(tilemap: TileMapLayer, cells: Array[Vector2i], interaction_position: Vector2) -> Vector2i:
	if not tilemap or cells.is_empty():
		return NO_COUNTER_CELL

	var selected_cell := NO_COUNTER_CELL
	var selected_distance: float = INF
	var max_distance_squared := counter_interaction_distance * counter_interaction_distance

	for cell in cells:
		var cell_position := tilemap.to_global(tilemap.map_to_local(cell))
		var distance := interaction_position.distance_squared_to(cell_position)
		if distance <= max_distance_squared and distance < selected_distance:
			selected_distance = distance
			selected_cell = cell

	return selected_cell


func get_closest_external_storage_id(cells: Array[Vector2i]) -> String:
	var selected_id := NO_STORAGE_ID
	var selected_distance: float = INF
	var selected_priority := -1
	var interaction_position := get_external_inventory_detection_position()

	for cell in cells:
		if not external_storage_cell_ids.has(cell):
			continue

		var storage_id := String(external_storage_cell_ids[cell])
		var cell_position := furniture_tilemap.to_global(furniture_tilemap.map_to_local(cell))
		var distance := interaction_position.distance_squared_to(cell_position)
		var priority := get_external_storage_priority(storage_id)

		if distance < selected_distance or (is_equal_approx(distance, selected_distance) and priority > selected_priority):
			selected_distance = distance
			selected_priority = priority
			selected_id = storage_id

	return selected_id


func get_external_storage_priority(storage_id: String) -> int:
	if storage_id.begins_with("counter_"):
		return 1
	return 0


func get_external_inventory_detection_position() -> Vector2:
	return get_tile_in_front_position() + external_inventory_detection_offset


func set_active_external_storage(storage_id: String) -> void:
	if current_storage_id == storage_id:
		return

	var previous_storage_id := current_storage_id
	current_storage_id = storage_id
	if storage_id == NO_STORAGE_ID:
		active_storage_selector.hide()
		update_external_storage_visual()
		update_external_storage_preview(previous_storage_id)
		return

	update_external_storage_preview(previous_storage_id)
	hide_external_storage_preview(storage_id)

	var anchor_cell: Vector2i = external_storage_positions[storage_id]
	var counter_global_position := furniture_tilemap.to_global(furniture_tilemap.map_to_local(anchor_cell))
	var storage_position := to_local(counter_global_position)
	storage_position.x -= 16.0
	storage_position.y = fridge_position.y + selector_offset.y
	active_storage_selector.position = storage_position
	active_storage_selector.show()
	update_selector_arrows(active_storage_selector, false)
	hide_selector_slot(active_storage_selector)
	update_external_storage_visual()


func cycle_external_storage_slot(direction: int) -> void:
	var storage_size := get_external_storage_size(current_storage_id)
	if current_storage_id == NO_STORAGE_ID or storage_size <= 1:
		return

	var current_slot: int = int(external_storage_indices.get(current_storage_id, 0))
	external_storage_indices[current_storage_id] = (current_slot + direction + storage_size) % storage_size
	update_external_storage_visual()
	hide_external_storage_preview(current_storage_id)


func interact_with_external_storage() -> void:
	if current_storage_id == NO_STORAGE_ID:
		return

	if is_inventory_free():
		take_from_external_storage()
	else:
		place_in_external_storage()


func place_in_external_storage() -> void:
	if held_item_is_spoiled:
		return
	if not can_place_held_item_in_external_storage(current_storage_id):
		return

	var slots: Array = external_storage_items[current_storage_id]
	var slot_index: int = int(external_storage_indices.get(current_storage_id, 0))
	if slots[slot_index] >= 0:
		return

	slots[slot_index] = held_item_frame
	external_storage_items[current_storage_id] = slots
	set_external_storage_state_from_held_item(current_storage_id, slot_index)
	clear_inventory()
	update_external_storage_visual()
	hide_external_storage_preview(current_storage_id)
	update_special_table_full_state()


func can_place_held_item_in_external_storage(storage_id: String) -> bool:
	if storage_id == OVEN_STORAGE_ID:
		return can_order_cooked(held_item_frame)
	if is_cutting_board_storage(storage_id):
		return can_order_cut(held_item_frame)
	return true


func take_from_external_storage() -> void:
	var slots: Array = external_storage_items[current_storage_id]
	var slot_index: int = int(external_storage_indices.get(current_storage_id, 0))
	if slots[slot_index] < 0:
		return

	held_item_frame = slots[slot_index]
	held_item_prep_progress = get_external_storage_slot_float(external_storage_prep_progress, current_storage_id, slot_index, -1.0)
	held_item_oven_progress = get_external_storage_slot_float(external_storage_oven_progress, current_storage_id, slot_index, -1.0)
	held_item_left_out_time = get_external_storage_slot_float(external_storage_left_out_time, current_storage_id, slot_index, 0.0)
	held_item_is_spoiled = get_external_storage_slot_bool(external_storage_spoiled, current_storage_id, slot_index, false)
	held_item_cut_status = get_external_storage_slot_string(external_storage_cut_status, current_storage_id, slot_index, get_cut_status_from_prep_progress(held_item_prep_progress))
	held_item_food_status = get_external_storage_slot_string(external_storage_food_status, current_storage_id, slot_index, get_food_status_from_state(held_item_oven_progress, held_item_is_spoiled))
	slots[slot_index] = -1
	external_storage_items[current_storage_id] = slots
	clear_external_storage_item_state(current_storage_id, slot_index)

	update_held_item_hud()

	update_external_storage_visual()
	hide_external_storage_preview(current_storage_id)
	update_special_table_full_state()


func update_external_storage_visual() -> void:
	clear_external_storage_grid()

	if current_storage_id == NO_STORAGE_ID or not external_storage_items.has(current_storage_id):
		return

	var slots: Array = external_storage_items[current_storage_id]
	if slots.is_empty():
		return

	var selected_slot := active_storage_selector.get_node_or_null("selected") as Sprite2D
	if not selected_slot:
		return

	var slot_count: int = slots.size()
	var selected_index: int = clampi(int(external_storage_indices.get(current_storage_id, 0)), 0, slot_count - 1)
	external_storage_indices[current_storage_id] = selected_index

	var slot_step: Vector2 = get_selector_slot_step(selected_slot)
	var columns: int = get_selector_grid_columns(active_storage_selector, selected_slot.position, slot_count, slot_step)
	var rows: int = ceili(float(slot_count) / float(columns))
	var start_position: Vector2 = get_selector_grid_start_position(selected_slot.position, columns, rows, slot_step)
	keep_selector_grid_on_screen(active_storage_selector, start_position, columns, rows, slot_step)
	update_selector_background(active_storage_selector, start_position, columns, rows, slot_step)

	for i in range(slot_count):
		var slot_position: Vector2 = get_selector_grid_slot_position(start_position, i, columns, slot_step)
		create_selector_slot_visual(active_storage_selector, selected_slot, slot_position, i == selected_index, active_storage_grid_nodes)

		if int(slots[i]) >= 0:
			create_external_storage_food_visual(int(slots[i]), slot_position, current_storage_id, i)


func clear_external_storage_grid() -> void:
	for node in active_storage_grid_nodes:
		if is_instance_valid(node):
			node.queue_free()
	active_storage_grid_nodes.clear()


func create_external_storage_food_visual(frame: int, slot_position: Vector2, storage_id: String, slot_index: int) -> void:
	var storage_food := food_scene.instantiate() as Node2D
	active_storage_selector.add_child(storage_food)
	storage_food.position = slot_position
	active_storage_grid_nodes.append(storage_food)

	var sprite := storage_food.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite:
		var food_status := get_external_storage_slot_string(external_storage_food_status, storage_id, slot_index, FOOD_ITEM_STATUS_SAFE)
		var cut_status := get_external_storage_slot_string(external_storage_cut_status, storage_id, slot_index, CUT_STATUS_UNCUT)
		set_food_base_frame(storage_food, frame)
		update_food_display_frame(storage_food, food_status, cut_status)

	var label := storage_food.get_node_or_null("CountLabel")
	if label:
		label.hide()
	apply_external_storage_prep_visuals(storage_food, storage_id, slot_index)


func update_external_storage_preview(storage_id: String) -> void:
	hide_external_storage_preview(storage_id)
	if storage_id == NO_STORAGE_ID or storage_id == current_storage_id:
		return
	if not external_storage_items.has(storage_id) or not external_storage_positions.has(storage_id):
		return

	var slot_index := get_external_storage_preview_slot_index(storage_id)
	if slot_index < 0:
		return
	var slots: Array = external_storage_items[storage_id]
	var frame := int(slots[slot_index])

	var anchor_cell: Vector2i = external_storage_positions[storage_id]
	var food_status := get_external_storage_slot_string(external_storage_food_status, storage_id, slot_index, FOOD_ITEM_STATUS_SAFE)
	var cut_status := get_external_storage_slot_string(external_storage_cut_status, storage_id, slot_index, CUT_STATUS_UNCUT)
	var preview := create_counter_food_item(frame, anchor_cell, food_status, cut_status)
	if storage_id == OVEN_STORAGE_ID:
		preview.position.y += 16.0
	apply_external_storage_prep_visuals(preview, storage_id, slot_index)
	external_storage_preview_nodes[storage_id] = preview


func hide_external_storage_preview(storage_id: String) -> void:
	if storage_id == NO_STORAGE_ID or not external_storage_preview_nodes.has(storage_id):
		return

	var preview_node: Node = external_storage_preview_nodes[storage_id]
	if is_instance_valid(preview_node):
		preview_node.queue_free()
	external_storage_preview_nodes.erase(storage_id)


func get_external_storage_preview_frame(storage_id: String) -> int:
	var slot_index := get_external_storage_preview_slot_index(storage_id)
	if slot_index < 0:
		return -1

	var slots: Array = external_storage_items[storage_id]
	return int(slots[slot_index])


func get_external_storage_preview_slot_index(storage_id: String) -> int:
	var slots: Array = external_storage_items[storage_id]
	if slots.is_empty():
		return -1

	var slot_index: int = clampi(int(external_storage_indices.get(storage_id, 0)), 0, slots.size() - 1)
	if int(slots[slot_index]) >= 0:
		return slot_index

	for i in range(slot_index - 1, -1, -1):
		if int(slots[i]) >= 0:
			return i

	return -1


func place_counter_item():
	var cell := find_counter_cell_for_placement()
	if cell == NO_COUNTER_CELL:
		return

	var counter_food := create_counter_food_item(held_item_frame, cell, held_item_food_status, held_item_cut_status)
	var prep_progress := held_item_prep_progress
	counter_items[cell] = {
		"frame": held_item_frame,
		"node": counter_food,
		"prep_progress": prep_progress,
		"oven_progress": held_item_oven_progress,
		"left_out_time": held_item_left_out_time,
		"is_spoiled": held_item_is_spoiled,
		"cut_status": held_item_cut_status,
		"food_status": held_item_food_status
	}
	apply_food_state_visuals(counter_food, get_regular_counter_visual_prep_progress(prep_progress), held_item_oven_progress, held_item_is_spoiled)
	clear_inventory()


func pick_up_counter_item():
	var cell := find_counter_cell_with_item()
	if cell == NO_COUNTER_CELL:
		return

	var counter_item: Dictionary = counter_items[cell]
	held_item_frame = counter_item["frame"]
	held_item_prep_progress = float(counter_item.get("prep_progress", -1.0))
	held_item_oven_progress = float(counter_item.get("oven_progress", -1.0))
	held_item_left_out_time = float(counter_item.get("left_out_time", 0.0))
	held_item_is_spoiled = bool(counter_item.get("is_spoiled", false))
	held_item_cut_status = String(counter_item.get("cut_status", get_cut_status_from_prep_progress(held_item_prep_progress)))
	held_item_food_status = String(counter_item.get("food_status", get_food_status_from_state(held_item_oven_progress, held_item_is_spoiled)))

	var counter_food: Node = counter_item["node"]
	if is_instance_valid(counter_food):
		counter_food.queue_free()
	counter_items.erase(cell)

	update_held_item_hud()


func find_counter_cell_for_placement() -> Vector2i:
	return get_hardcoded_counter_cell(false)


func find_counter_cell_with_item() -> Vector2i:
	return get_hardcoded_counter_cell(true)


func get_hardcoded_counter_cell(needs_counter_item: bool) -> Vector2i:
	if not needs_counter_item and is_banned_counter_area_closest():
		return NO_COUNTER_CELL

	var selected_cell := get_regular_counter_interaction_cell(VALID_COUNTER_CELLS)
	if selected_cell == NO_COUNTER_CELL:
		return NO_COUNTER_CELL

	for target_cell in VALID_COUNTER_CELLS:
		if target_cell != selected_cell:
			continue
		if not is_counter_cell(target_cell):
			continue
		if is_blocked_counter_cell(target_cell):
			continue
		if needs_counter_item != counter_items.has(target_cell):
			continue

		return target_cell

	return NO_COUNTER_CELL


func is_banned_counter_area_closest() -> bool:
	var counter_cells: Array[Vector2i] = []
	counter_cells.append_array(VALID_COUNTER_CELLS)
	counter_cells.append_array(BANNED_COUNTER_CELLS)
	var closest_cell := get_regular_counter_interaction_cell(counter_cells)

	return BANNED_COUNTER_CELLS.has(closest_cell)


func get_regular_counter_interaction_cell(cells: Array[Vector2i]) -> Vector2i:
	if not furniture_tilemap or cells.is_empty():
		return NO_COUNTER_CELL

	var selected_cell := NO_COUNTER_CELL
	var selected_distance: float = INF
	var max_distance_squared := regular_counter_interaction_distance * regular_counter_interaction_distance
	var positions: Array[Vector2] = [
		get_tile_in_front_position(),
		get_external_inventory_detection_position(),
	]

	for position in positions:
		for cell in cells:
			var cell_position := furniture_tilemap.to_global(furniture_tilemap.map_to_local(cell))
			var distance := position.distance_squared_to(cell_position)
			if distance <= max_distance_squared and distance < selected_distance:
				selected_distance = distance
				selected_cell = cell

	return selected_cell


func get_tile_in_front_position() -> Vector2:
	var collision_node := player_node.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_node:
		return collision_node.global_position

	return player_node.global_position


func get_tile_in_front(tilemap: TileMapLayer) -> Vector2i:
	var interaction_position := get_tile_in_front_position()
	return tilemap.local_to_map(tilemap.to_local(interaction_position))


func get_tile_in_front_from_cells(tilemap: TileMapLayer, cells: Array[Vector2i]) -> Vector2i:
	return get_tile_in_front_from_cells_at_position(tilemap, cells, get_tile_in_front_position())


func get_tile_in_front_from_cells_at_position(tilemap: TileMapLayer, cells: Array[Vector2i], interaction_position: Vector2) -> Vector2i:
	var selected_cell := NO_COUNTER_CELL
	var selected_distance: float = INF

	for cell in cells:
		var cell_position := tilemap.to_global(tilemap.map_to_local(cell))
		var distance := interaction_position.distance_squared_to(cell_position)
		if distance < selected_distance:
			selected_distance = distance
			selected_cell = cell

	return selected_cell


func is_blocked_counter_cell(cell: Vector2i) -> bool:
	return items_tilemap.get_cell_atlas_coords(cell) == BLOCKED_ITEM_ATLAS


func create_counter_food_item(frame: int, cell: Vector2i, food_status: String = FOOD_ITEM_STATUS_SAFE, cut_status: String = CUT_STATUS_UNCUT) -> Node2D:
	var counter_food := food_scene.instantiate() as Node2D
	add_child(counter_food)

	var sprite := counter_food.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite:
		set_food_base_frame(counter_food, frame)
		update_food_display_frame(counter_food, food_status, cut_status)

	var label := counter_food.get_node_or_null("CountLabel")
	if label:
		label.hide()
	reset_food_prep_visuals(counter_food)

	var counter_global_position := furniture_tilemap.to_global(furniture_tilemap.map_to_local(cell))
	counter_food.position = to_local(counter_global_position)
	counter_food.z_index = 10
	return counter_food


func reset_food_prep_visuals(food_node: Node) -> void:
	var status_icon := food_node.get_node_or_null(FOOD_STATUS_ICON_NAME) as AnimatedSprite2D
	if status_icon:
		status_icon.z_index = 20
		status_icon.stop()
		status_icon.frame = FOOD_STATUS_DEFAULT_FRAME
		status_icon.modulate = FOOD_STATUS_NORMAL_COLOR

	var progress_bar := food_node.get_node_or_null(FOOD_PROGRESS_BAR_NAME) as ProgressBar
	if progress_bar:
		configure_food_progress_bar(progress_bar)
		progress_bar.min_value = 0.0
		progress_bar.max_value = 100.0
		progress_bar.value = 0.0
		progress_bar.visible = false


func configure_food_progress_bar(progress_bar: ProgressBar) -> void:
	progress_bar.z_index = 25
	progress_bar.custom_minimum_size = Vector2(8.0, 18.0)

	update_food_progress_fill(progress_bar, Color(0.2, 0.95, 0.35, 1.0))

	var background_style := StyleBoxFlat.new()
	background_style.bg_color = Color(1.0, 1.0, 1.0, 0.0)
	progress_bar.add_theme_stylebox_override("background", background_style)


func is_cutting_board_storage(storage_id: String) -> bool:
	return storage_id.begins_with("counter_")


func get_cut_status_from_prep_progress(prep_progress: float) -> String:
	if prep_progress >= 100.0:
		return CUT_STATUS_CUT
	return CUT_STATUS_UNCUT


func get_food_status_from_state(oven_progress: float, is_spoiled: bool) -> String:
	if is_spoiled:
		return FOOD_ITEM_STATUS_EXPIRED
	if oven_progress >= 100.0:
		return FOOD_ITEM_STATUS_COOKED
	return FOOD_ITEM_STATUS_SAFE


func refresh_held_item_status() -> void:
	held_item_cut_status = get_cut_status_from_prep_progress(held_item_prep_progress)
	held_item_food_status = get_food_status_from_state(held_item_oven_progress, held_item_is_spoiled)


func get_external_storage_slot_string(state_dictionary: Dictionary, storage_id: String, slot_index: int, fallback: String) -> String:
	if not state_dictionary.has(storage_id):
		return fallback

	var values: Array = state_dictionary[storage_id]
	if slot_index < 0 or slot_index >= values.size():
		return fallback

	return String(values[slot_index])


func set_external_storage_slot_string(state_dictionary: Dictionary, storage_id: String, slot_index: int, value: String) -> void:
	if not state_dictionary.has(storage_id):
		return

	var values: Array = state_dictionary[storage_id]
	if slot_index < 0 or slot_index >= values.size():
		return

	values[slot_index] = value
	state_dictionary[storage_id] = values


func update_external_storage_slot_status(storage_id: String, slot_index: int, prep_progress: float, oven_progress: float, is_spoiled: bool) -> void:
	set_external_storage_slot_string(external_storage_cut_status, storage_id, slot_index, get_cut_status_from_prep_progress(prep_progress))
	set_external_storage_slot_string(external_storage_food_status, storage_id, slot_index, get_food_status_from_state(oven_progress, is_spoiled))


func set_external_storage_state_from_held_item(storage_id: String, slot_index: int) -> void:
	if not external_storage_prep_progress.has(storage_id):
		external_storage_prep_progress[storage_id] = create_empty_prep_progress_slots(storage_id)
	if not external_storage_oven_progress.has(storage_id):
		external_storage_oven_progress[storage_id] = create_empty_oven_progress_slots(storage_id)
	if not external_storage_left_out_time.has(storage_id):
		external_storage_left_out_time[storage_id] = create_empty_left_out_time_slots(storage_id)
	if not external_storage_spoiled.has(storage_id):
		external_storage_spoiled[storage_id] = create_empty_spoiled_slots(storage_id)
	if not external_storage_cut_status.has(storage_id):
		external_storage_cut_status[storage_id] = create_empty_cut_status_slots(storage_id)
	if not external_storage_food_status.has(storage_id):
		external_storage_food_status[storage_id] = create_empty_food_status_slots(storage_id)

	var prep_progress: Array = external_storage_prep_progress[storage_id]
	var oven_progress: Array = external_storage_oven_progress[storage_id]
	var left_out_time: Array = external_storage_left_out_time[storage_id]
	var spoiled: Array = external_storage_spoiled[storage_id]
	if slot_index < 0 or slot_index >= prep_progress.size():
		return

	if held_item_prep_progress >= 0.0:
		prep_progress[slot_index] = held_item_prep_progress
	elif is_cutting_board_storage(storage_id):
		prep_progress[slot_index] = 0.0
	else:
		prep_progress[slot_index] = -1.0

	if held_item_oven_progress >= 0.0:
		oven_progress[slot_index] = held_item_oven_progress
	elif storage_id == OVEN_STORAGE_ID:
		oven_progress[slot_index] = 0.0
	else:
		oven_progress[slot_index] = -1.0

	left_out_time[slot_index] = held_item_left_out_time
	spoiled[slot_index] = held_item_is_spoiled
	refresh_held_item_status()

	external_storage_prep_progress[storage_id] = prep_progress
	external_storage_oven_progress[storage_id] = oven_progress
	external_storage_left_out_time[storage_id] = left_out_time
	external_storage_spoiled[storage_id] = spoiled
	update_external_storage_slot_status(storage_id, slot_index, float(prep_progress[slot_index]), float(oven_progress[slot_index]), bool(spoiled[slot_index]))


func clear_external_storage_item_state(storage_id: String, slot_index: int) -> void:
	set_external_storage_slot_float(external_storage_prep_progress, storage_id, slot_index, -1.0)
	set_external_storage_slot_float(external_storage_oven_progress, storage_id, slot_index, -1.0)
	set_external_storage_slot_float(external_storage_left_out_time, storage_id, slot_index, 0.0)
	set_external_storage_slot_bool(external_storage_spoiled, storage_id, slot_index, false)
	set_external_storage_slot_string(external_storage_cut_status, storage_id, slot_index, CUT_STATUS_UNCUT)
	set_external_storage_slot_string(external_storage_food_status, storage_id, slot_index, FOOD_ITEM_STATUS_SAFE)


func get_external_storage_slot_float(state_dictionary: Dictionary, storage_id: String, slot_index: int, fallback: float) -> float:
	if not state_dictionary.has(storage_id):
		return fallback

	var values: Array = state_dictionary[storage_id]
	if slot_index < 0 or slot_index >= values.size():
		return fallback

	return float(values[slot_index])


func set_external_storage_slot_float(state_dictionary: Dictionary, storage_id: String, slot_index: int, value: float) -> void:
	if not state_dictionary.has(storage_id):
		return

	var values: Array = state_dictionary[storage_id]
	if slot_index < 0 or slot_index >= values.size():
		return

	values[slot_index] = value
	state_dictionary[storage_id] = values


func get_external_storage_slot_bool(state_dictionary: Dictionary, storage_id: String, slot_index: int, fallback: bool) -> bool:
	if not state_dictionary.has(storage_id):
		return fallback

	var values: Array = state_dictionary[storage_id]
	if slot_index < 0 or slot_index >= values.size():
		return fallback

	return bool(values[slot_index])


func set_external_storage_slot_bool(state_dictionary: Dictionary, storage_id: String, slot_index: int, value: bool) -> void:
	if not state_dictionary.has(storage_id):
		return

	var values: Array = state_dictionary[storage_id]
	if slot_index < 0 or slot_index >= values.size():
		return

	values[slot_index] = value
	state_dictionary[storage_id] = values


func get_regular_counter_visual_prep_progress(prep_progress: float) -> float:
	if prep_progress >= 100.0:
		return prep_progress
	return -1.0


func update_food_state_timers(delta: float) -> void:
	var should_refresh_active_storage := false
	var cutting_progress_per_second := 100.0 / maxf(cutting_board_prep_time, 0.001)
	var oven_progress_per_second := 100.0 / maxf(oven_prep_time, 0.001)

	if held_item_frame >= 0 and not held_item_is_spoiled:
		held_item_left_out_time += delta
		if held_item_left_out_time >= food_spoil_time:
			held_item_is_spoiled = true
			refresh_held_item_status()
			update_held_item_hud()

	for cell in counter_items.keys():
		var counter_item: Dictionary = counter_items[cell]
		var progress := float(counter_item.get("prep_progress", -1.0))
		var oven_progress := float(counter_item.get("oven_progress", -1.0))
		var left_out_time := float(counter_item.get("left_out_time", 0.0))
		var is_spoiled := bool(counter_item.get("is_spoiled", false))

		if not is_spoiled:
			left_out_time += delta
			if left_out_time >= food_spoil_time:
				is_spoiled = true
			counter_item["left_out_time"] = left_out_time
			counter_item["is_spoiled"] = is_spoiled

		counter_item["cut_status"] = get_cut_status_from_prep_progress(progress)
		counter_item["food_status"] = get_food_status_from_state(oven_progress, is_spoiled)

		counter_items[cell] = counter_item

		var counter_food := counter_item.get("node", null) as Node
		if is_instance_valid(counter_food):
			apply_food_state_visuals(counter_food, get_regular_counter_visual_prep_progress(progress), oven_progress, is_spoiled)

	for storage_id in external_storage_items.keys():
		var storage_id_string := String(storage_id)
		if not external_storage_prep_progress.has(storage_id_string):
			continue
		if not external_storage_oven_progress.has(storage_id_string):
			continue
		if not external_storage_left_out_time.has(storage_id_string):
			continue
		if not external_storage_spoiled.has(storage_id_string):
			continue

		var slots: Array = external_storage_items[storage_id_string]
		var prep_progress: Array = external_storage_prep_progress[storage_id_string]
		var oven_progress: Array = external_storage_oven_progress[storage_id_string]
		var left_out_time: Array = external_storage_left_out_time[storage_id_string]
		var spoiled: Array = external_storage_spoiled[storage_id_string]
		var spoil_time := food_spoil_time * SPECIAL_TABLE_SPOIL_TIME_MULTIPLIER if storage_id_string == SPECIAL_TABLE_STORAGE_ID else food_spoil_time

		for i in range(mini(slots.size(), prep_progress.size())):
			if int(slots[i]) < 0:
				continue

			if is_cutting_board_storage(storage_id_string) and is_cuttable_frame(int(slots[i])) and float(prep_progress[i]) >= 0.0 and float(prep_progress[i]) < 100.0:
				prep_progress[i] = minf(100.0, float(prep_progress[i]) + cutting_progress_per_second * delta)
				if storage_id_string == current_storage_id:
					should_refresh_active_storage = true

			if storage_id_string == OVEN_STORAGE_ID and can_order_cooked(int(slots[i])) and float(oven_progress[i]) >= 0.0 and float(oven_progress[i]) < 100.0:
				oven_progress[i] = minf(100.0, float(oven_progress[i]) + oven_progress_per_second * delta)
				if storage_id_string == current_storage_id:
					should_refresh_active_storage = true

			if not bool(spoiled[i]):
				left_out_time[i] = float(left_out_time[i]) + delta
				if float(left_out_time[i]) >= spoil_time:
					spoiled[i] = true
				if storage_id_string == current_storage_id:
					should_refresh_active_storage = true

			update_external_storage_slot_status(storage_id_string, i, float(prep_progress[i]), float(oven_progress[i]), bool(spoiled[i]))

		external_storage_prep_progress[storage_id_string] = prep_progress
		external_storage_oven_progress[storage_id_string] = oven_progress
		external_storage_left_out_time[storage_id_string] = left_out_time
		external_storage_spoiled[storage_id_string] = spoiled
		update_external_storage_preview_prep_visual(storage_id_string)

	if should_refresh_active_storage:
		update_external_storage_visual()


func update_external_storage_preview_prep_visual(storage_id: String) -> void:
	if not external_storage_preview_nodes.has(storage_id):
		return

	var preview_node: Node = external_storage_preview_nodes[storage_id]
	if not is_instance_valid(preview_node):
		return

	var slot_index := get_external_storage_preview_slot_index(storage_id)
	if slot_index < 0:
		return

	apply_external_storage_prep_visuals(preview_node, storage_id, slot_index)


func apply_external_storage_prep_visuals(food_node: Node, storage_id: String, slot_index: int) -> void:
	reset_food_prep_visuals(food_node)
	if not external_storage_prep_progress.has(storage_id):
		return
	if not external_storage_oven_progress.has(storage_id):
		return
	if not external_storage_spoiled.has(storage_id):
		return

	var prep_progress: Array = external_storage_prep_progress[storage_id]
	var oven_progress: Array = external_storage_oven_progress[storage_id]
	var spoiled: Array = external_storage_spoiled[storage_id]
	if slot_index < 0 or slot_index >= prep_progress.size():
		return

	apply_food_state_visuals(food_node, float(prep_progress[slot_index]), float(oven_progress[slot_index]), bool(spoiled[slot_index]))


func apply_food_state_visuals(food_node: Node, prep_progress: float, oven_progress: float, is_spoiled: bool) -> void:
	update_food_display_frame(food_node, get_food_status_from_state(oven_progress, is_spoiled), get_cut_status_from_prep_progress(prep_progress))

	var status_icon := food_node.get_node_or_null(FOOD_STATUS_ICON_NAME) as AnimatedSprite2D
	if status_icon:
		status_icon.stop()
		status_icon.frame = FOOD_STATUS_KNIFE_FRAME if prep_progress >= 100.0 else FOOD_STATUS_DEFAULT_FRAME
		if is_spoiled:
			status_icon.modulate = FOOD_STATUS_SPOILED_COLOR
		elif oven_progress >= 100.0:
			status_icon.modulate = FOOD_STATUS_COOKED_COLOR
		else:
			status_icon.modulate = FOOD_STATUS_NORMAL_COLOR

	var progress_bar := food_node.get_node_or_null(FOOD_PROGRESS_BAR_NAME) as ProgressBar
	if progress_bar:
		var active_progress := 100.0
		var active_color := Color(0.2, 0.95, 0.35, 1.0)
		if is_spoiled:
			progress_bar.visible = false
			return
		elif oven_progress >= 0.0 and oven_progress < 100.0:
			active_progress = oven_progress
			active_color = FOOD_STATUS_COOKED_COLOR
		elif prep_progress >= 0.0 and prep_progress < 100.0:
			active_progress = prep_progress

		update_food_progress_fill(progress_bar, active_color)
		progress_bar.value = clampf(active_progress, 0.0, 100.0)
		progress_bar.visible = active_progress < 100.0


func set_food_base_frame(food_node: Node, frame: int) -> void:
	food_node.set_meta("base_frame", frame)


func update_food_display_frame(food_node: Node, food_status: String, cut_status: String = CUT_STATUS_UNCUT) -> void:
	var sprite := food_node.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite == null:
		return

	var base_frame := int(food_node.get_meta("base_frame", sprite.frame))
	sprite.frame = FoodIconRules.display_frame(base_frame, food_status, cut_status)


func update_food_progress_fill(progress_bar: ProgressBar, fill_color: Color) -> void:
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = fill_color
	fill_style.corner_radius_top_left = 2
	fill_style.corner_radius_top_right = 2
	fill_style.corner_radius_bottom_left = 2
	fill_style.corner_radius_bottom_right = 2
	progress_bar.add_theme_stylebox_override("fill", fill_style)


func get_player_cells(tilemap: TileMapLayer, padding_cells: int = 1, position_offset: Vector2 = Vector2.ZERO) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var collision_node = player_node.get_node_or_null("CollisionShape2D")
	if not collision_node or not collision_node.shape:
		return cells

	var local_rect = collision_node.shape.get_rect()
	var top_left_global = collision_node.to_global(local_rect.position) + position_offset
	var bottom_right_global = collision_node.to_global(local_rect.position + local_rect.size) + position_offset
	var top_left_cell = tilemap.local_to_map(tilemap.to_local(top_left_global))
	var bottom_right_cell = tilemap.local_to_map(tilemap.to_local(bottom_right_global))

	for x in range(top_left_cell.x - padding_cells, bottom_right_cell.x + padding_cells + 1):
		for y in range(top_left_cell.y - padding_cells, bottom_right_cell.y + padding_cells + 1):
			cells.append(Vector2i(x, y))

	return cells


func is_counter_cell(cell: Vector2i) -> bool:
	var atlas_coords := furniture_tilemap.get_cell_atlas_coords(cell)
	return atlas_coords.y == COUNTER_ATLAS_Y and atlas_coords.x >= COUNTER_ATLAS_MIN_X and atlas_coords.x <= COUNTER_ATLAS_MAX_X


func is_inventory_free() -> bool:
	if hud_node and hud_node.has_method("is_slot_free"):
		return bool(hud_node.call("is_slot_free"))
	return held_item_frame < 0


func update_held_item_hud() -> void:
	if held_item_frame < 0 or not hud_node:
		return
	refresh_held_item_status()

	if hud_node.has_method("set_item_state"):
		hud_node.call("set_item_state", held_item_frame, held_item_prep_progress, held_item_oven_progress, held_item_is_spoiled, held_item_cut_status)
	elif hud_node.has_method("set_item"):
		hud_node.call("set_item", held_item_frame)


func clear_inventory():
	held_item_frame = -1
	held_item_prep_progress = -1.0
	held_item_oven_progress = -1.0
	held_item_left_out_time = 0.0
	held_item_is_spoiled = false
	refresh_held_item_status()
	if hud_node and hud_node.has_method("clear_item"):
		hud_node.call("clear_item")


# --- NEW: Continuous Queue Logic ---
func restock_loop(index: int):
	item_restocking[index] = true
	# Keep looping and refilling as long as we are below max capacity
	while item_counts[index] < max_item_count:
		var sprite = food_items[index].get_node("AnimatedSprite2D")
		
		# Snap to dark gray to indicate the start of a new charge
		sprite.modulate = Color(0.3, 0.3, 0.3) 
		
		var tween = get_tree().create_tween()
		tween.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0), restock_time)
		
		# Wait 5 seconds for the charge to complete
		await tween.finished
		
		# Add 1 to inventory and refresh the UI numbers
		item_counts[index] += 1
		update_labels()
	item_restocking[index] = false
