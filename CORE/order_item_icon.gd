extends Control

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

@onready var item_icon: TextureRect = $ItemIcon
@onready var status_badge: TextureRect = $StatusBadge
var icon_texture: Texture2D
var status_texture: Texture2D


func setup(frame: int, cut_status: String, food_status: String) -> void:
	if not is_node_ready():
		await ready
	if icon_texture == null:
		icon_texture = load(CorePaths.path("IconSheet 16x16.png")) as Texture2D
	if status_texture == null:
		status_texture = load(CorePaths.path("Prep Icons.png")) as Texture2D

	item_icon.texture = _make_icon_texture(frame)
	status_badge.texture = _make_status_texture(FOOD_STATUS_KNIFE_FRAME if cut_status == CUT_STATUS_CUT else FOOD_STATUS_DEFAULT_FRAME)
	status_badge.modulate = _get_food_status_color(food_status)


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
