extends PanelContainer

@onready var items: HBoxContainer = $Content/Items
var order_item_icon_scene: PackedScene


func _ready() -> void:
	order_item_icon_scene = load(CorePaths.path("order_item_icon.tscn")) as PackedScene
	hide()


func set_order(order_items: Array) -> void:
	clear_order_items()
	if order_item_icon_scene == null:
		push_warning("Order item icon scene could not be loaded.")
		return

	for order_item in order_items:
		var icon := order_item_icon_scene.instantiate()
		items.add_child(icon)
		if icon.has_method("setup"):
			icon.call(
				"setup",
				int(order_item.get("frame", -1)),
				String(order_item.get("cut_status", "uncut")),
				String(order_item.get("food_status", "safe"))
			)

	visible = not order_items.is_empty()


func clear_order() -> void:
	clear_order_items()
	hide()


func clear_order_items() -> void:
	for child in items.get_children():
		child.queue_free()
