class_name FoodIconRules
extends RefCounted

const FOOD_ITEM_STATUS_COOKED := "cooked"
const CUT_STATUS_CUT := "cut"

const FRIDGE_MENU: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 69, 73, 74, 85, 86, 90, 99, 110, 111, 147]

const COOKABLE_FRAMES: Array[int] = [
	14, 19, 20, 22, 23, 24, 25, 26, 36, 39, 40, 41, 43, 44, 49, 50, 52, 54, 55, 56, 58,
	81, 99, 147,
]

const MEAT_FRAMES: Array[int] = [73, 74, 101, 102, 110, 111]

const NEVER_CUT_FRAMES: Array[int] = [15, 59, 61, 63, 68, 69, 78, 91, 107, 115, 116, 121, 122, 123, 124, 125, 126, 127, 131, 132, 135, 138, 141, 143, 144, 145, 148, 149, 153, 154, 155, 156, 157, 158, 159]

const NEVER_COOK_FRAMES: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14, 15, 16, 17, 18, 19, 21, 22, 24, 25, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 48, 58, 59, 63, 78, 115, 123, 124, 125, 143, 145]

const CUT_FRAME_BY_FRAME = {
	3: 31,    # Whole Lemon -> Lemon Wedge
	8: 35,    # Whole Avocado -> Avocado Half
	17: 18,   # Whole Orange -> Orange Half
	24: 25,   # Whole Lime -> Lime Half
	29: 28,   # Whole Coconut -> Coconut Half
	48: 33,   # Whole Watermelon -> Watermelon Slice
	70: 71,   # Cheese Wheel -> Cheese Wedge
	119: 151  # Bread Loaf -> Bread Slice
}

const COOKED_FRAME_BY_FRAME = {
	69: 72,   # Raw Egg -> Fried Egg
	73: 77,   # Raw Bacon -> Cooked Bacon
	74: 75,   # Raw Whole Bird -> Cooked Whole Bird
	85: 87,   # Raw Silver Fish -> Cooked Silver Fish
	86: 88,   # Raw Blue Fish -> Cooked Fish
	99: 102,  # Raw Drumstick -> Cooked Drumstick
	110: 109, # Raw Steak -> Cooked Steak
	147: 114  # Raw Skewer -> Cooked Skewer
}


static func is_cookable_frame(frame: int) -> bool:
	return COOKABLE_FRAMES.has(frame) and not is_never_cook_frame(frame)


static func is_meat_frame(frame: int) -> bool:
	return MEAT_FRAMES.has(frame)


static func is_cuttable_frame(frame: int) -> bool:
	return not NEVER_CUT_FRAMES.has(frame)


static func is_never_cook_frame(frame: int) -> bool:
	return NEVER_COOK_FRAMES.has(frame)


static func display_frame(frame: int, food_status: String, cut_status: String = "") -> int:
	var display := frame
	if cut_status == CUT_STATUS_CUT:
		display = int(_get_cut_frame_by_frame().get(display, display))
	if food_status == FOOD_ITEM_STATUS_COOKED:
		display = int(_get_cooked_frame_by_frame().get(display, display))
	return display


static func _get_cut_frame_by_frame() -> Dictionary:
	return CUT_FRAME_BY_FRAME


static func _get_cooked_frame_by_frame() -> Dictionary:
	return COOKED_FRAME_BY_FRAME
