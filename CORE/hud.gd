extends CanvasLayer

const ICON_SIZE := 16
const ICON_COLUMNS := 16
const STATUS_ICON_SIZE := 16
const FOOD_STATUS_DEFAULT_FRAME := 0
const FOOD_STATUS_KNIFE_FRAME := 1
const CUT_STATUS_CUT := "cut"
const FOOD_ITEM_STATUS_COOKED := "cooked"
const FOOD_ITEM_STATUS_EXPIRED := "expired"
const FOOD_STATUS_NORMAL_COLOR := Color(0.2, 0.95, 0.35, 1.0)
const FOOD_STATUS_COOKED_COLOR := Color(1.0, 0.08, 0.04, 1.0)
const FOOD_STATUS_SPOILED_COLOR := Color(0.68, 0.18, 1.0, 1.0)

var held_frame: int = -1
var slot_icon: Sprite2D
var status_icon: Sprite2D
var order_display: Node
var coin_label: Label
var icon_texture: Texture2D
var status_texture: Texture2D
var order_display_scene: PackedScene


func _ready() -> void:
	icon_texture = load(CorePaths.path("IconSheet 16x16.png")) as Texture2D
	status_texture = load(CorePaths.path("Prep Icons.png")) as Texture2D
	order_display_scene = load(CorePaths.path("order_display.tscn")) as PackedScene
	create_order_display()
	create_coin_display()

	var slot = get_node_or_null("slot")
	if not slot:
		return

	slot_icon = Sprite2D.new()
	slot_icon.name = "slot_icon"
	slot_icon.texture = _make_icon_texture(0)
	slot_icon.hide()
	slot.add_child(slot_icon)

	status_icon = Sprite2D.new()
	status_icon.name = "status_icon"
	status_icon.position = Vector2(5.0, 5.0)
	status_icon.scale = Vector2(0.25, 0.25)
	status_icon.texture = _make_status_texture(FOOD_STATUS_DEFAULT_FRAME)
	status_icon.hide()
	slot.add_child(status_icon)


func create_order_display() -> void:
	if order_display:
		return
	if order_display_scene == null:
		push_warning("Order display scene could not be loaded.")
		return

	order_display = order_display_scene.instantiate()
	add_child(order_display)


func create_coin_display() -> void:
	if coin_label:
		return

	coin_label = Label.new()
	coin_label.name = "coin_label"
	coin_label.position = Vector2(8.0, 86.0)
	coin_label.text = "Coins: 0"
	coin_label.add_theme_font_size_override("font_size", 10)
	add_child(coin_label)


func is_slot_free() -> bool:
	return held_frame < 0


func set_item(frame: int) -> void:
	set_item_state(frame, -1.0, -1.0, false)


func set_item_state(frame: int, prep_progress: float, oven_progress: float, is_spoiled: bool) -> void:
	held_frame = frame

	if slot_icon:
		slot_icon.texture = _make_icon_texture(frame)
		slot_icon.show()

	if status_icon:
		status_icon.texture = _make_status_texture(FOOD_STATUS_KNIFE_FRAME if prep_progress >= 100.0 else FOOD_STATUS_DEFAULT_FRAME)
		if is_spoiled:
			status_icon.modulate = FOOD_STATUS_SPOILED_COLOR
		elif oven_progress >= 100.0:
			status_icon.modulate = FOOD_STATUS_COOKED_COLOR
		else:
			status_icon.modulate = FOOD_STATUS_NORMAL_COLOR
		status_icon.show()


func clear_item() -> void:
	held_frame = -1

	if slot_icon:
		slot_icon.hide()
	if status_icon:
		status_icon.hide()


func set_order(order_items: Array) -> void:
	if not order_display:
		create_order_display()

	if order_display and order_display.has_method("set_order"):
		order_display.call("set_order", order_items)


func clear_order() -> void:
	if not order_display:
		return

	if order_display.has_method("clear_order"):
		order_display.call("clear_order")


func set_coins(coins: int) -> void:
	if not coin_label:
		create_coin_display()
	coin_label.text = "Coins: %s" % coins


func _get_food_status_color(food_status: String) -> Color:
	if food_status == FOOD_ITEM_STATUS_EXPIRED:
		return FOOD_STATUS_SPOILED_COLOR
	if food_status == FOOD_ITEM_STATUS_COOKED:
		return FOOD_STATUS_COOKED_COLOR
	return FOOD_STATUS_NORMAL_COLOR


func _make_icon_texture(frame: int) -> AtlasTexture:
	var atlas_texture := AtlasTexture.new()
	var atlas_x := frame % ICON_COLUMNS
	var atlas_y := floori(float(frame) / ICON_COLUMNS)

	atlas_texture.atlas = icon_texture
	atlas_texture.region = Rect2(atlas_x * ICON_SIZE, atlas_y * ICON_SIZE, ICON_SIZE, ICON_SIZE)
	return atlas_texture


func _make_status_texture(frame: int) -> AtlasTexture:
	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = status_texture
	atlas_texture.region = Rect2(0, (1 - clampi(frame, 0, 1)) * STATUS_ICON_SIZE, STATUS_ICON_SIZE, STATUS_ICON_SIZE)
	return atlas_texture
