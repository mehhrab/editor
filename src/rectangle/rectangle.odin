package rectangle

import rl "vendor:raylib"

intersect :: proc(rect1, rect2: rl.Rectangle) -> rl.Rectangle {
	x1 := max(rect1.x, rect2.x)
	y1 := max(rect1.y, rect2.y)
	x2 := min(rect1.x + rect1.width, rect2.x + rect2.width)
	y2 := min(rect1.y + rect1.height, rect2.y + rect2.height)
	if x2 < x1 { x2 = x1 }
	if y2 < y1 { y2 = y1 }
	return rl.Rectangle { x1, y1, x2 - x1, y2 - y1 }
}

pad :: proc(rect: rl.Rectangle, padding: f32) -> rl.Rectangle {
	return pad_ex(rect, padding, padding, padding, padding)
}

pad_ex :: proc(rect: rl.Rectangle, left, top, right, bottom: f32) -> rl.Rectangle {
	return { rect.x + left, rect.y + top, rect.width - right * 2, rect.height - bottom * 2 }
}

get_center_point :: proc(rect: rl.Rectangle) -> (x, y: f32) {
	return rect.x + rect.width / 2, rect.y + rect.height / 2
}

// NOTE: rect x and y are not used
center_in_area :: proc(rect: rl.Rectangle, area: rl.Rectangle) -> rl.Rectangle {
	x := area.x + area.width / 2 - rect.width / 2
	y := area.y + area.height / 2 - rect.height / 2
	return { x, y, rect.width, rect.height }
}

cut_top :: proc(rect: rl.Rectangle, amount: f32) -> (rl.Rectangle, rl.Rectangle) {
	top_rect := rl.Rectangle { rect.x, rect.y, rect.width, amount }
	bottom_rect := rl.Rectangle { rect.x , rect.y + amount, rect.width, rect.height - amount }
	return top_rect, bottom_rect
}

cut_bottom :: proc(rect: rl.Rectangle, amount: f32) -> (rl.Rectangle, rl.Rectangle) {
	bottom_rect := rl.Rectangle { rect.x , rect.y + rect.height - amount, rect.width, amount }
	top_rect := rl.Rectangle { rect.x, rect.y, rect.width, rect.height - amount }
	return bottom_rect, top_rect
}

cut_left :: proc(rect: rl.Rectangle, amount: f32) -> (rl.Rectangle, rl.Rectangle) {
	left_rect := rl.Rectangle { rect.x, rect.y, amount, rect.height }
	right_rect := rl.Rectangle { rect.x + amount, rect.y, rect.width - amount, rect.height }
	return left_rect, right_rect
}

cut_right :: proc(rect: rl.Rectangle, amount: f32) -> (rl.Rectangle, rl.Rectangle) {
	right_rect := rl.Rectangle { rect.x + rect.width - amount, rect.y, amount, rect.height }
	left_rect := rl.Rectangle { rect.x, rect.y, rect.width - amount, rect.height }
	return right_rect, left_rect
}