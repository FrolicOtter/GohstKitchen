class_name FoodIconRules
extends RefCounted

const FOOD_ITEM_STATUS_COOKED := "cooked"

const COOKABLE_FRAMES: Array[int] = [
	14, 19, 20, 22, 23, 24, 25, 26, 36, 39, 40, 41, 43, 44, 49, 50, 52, 54, 55, 56, 58,
	81, 99, 147,
]

const COOKED_FRAME_BY_FRAME := {
	81: 82,
	99: 110,
	147: 114,
}


static func is_cookable_frame(frame: int) -> bool:
	return COOKABLE_FRAMES.has(frame)


static func display_frame(frame: int, food_status: String) -> int:
	if food_status != FOOD_ITEM_STATUS_COOKED:
		return frame
	return int(COOKED_FRAME_BY_FRAME.get(frame, frame))
