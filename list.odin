package editor

import rl "vendor:raylib"
import "core:strings"

List :: struct {
	app: ^App,
	content: Editor,
	rect: rl.Rectangle,
}

list_init :: proc(list: ^List, app: ^App) {
	list.app = app

	buffer: Buffer; buffer_init(&buffer) 
	editor_init(&list.content, app, &buffer, "", "")
	
	list.content.hide_cursor = true
	list.content.hightlight_line = true
}

list_deinit :: proc(list: ^List) {
	editor_deinit(&list.content)
}

list_add_items :: proc(list: ^List, items: []string) {
	content := &list.content.buffer.content
	if 1 <= len(content) && content[len(content) - 1] != '\n' {
		editor_insert_raw(&list.content, "\n") 
	}

	for item, i in items {
		editor_insert_raw(&list.content, item)
		if i != len(items) - 1 {
			editor_insert_raw(&list.content, "\n") 
		}
	}
}

list_input :: proc(list: ^List) -> bool {
	handled := false
	
	if rl.IsKeyDown(.LEFT_SHIFT) == false &&
	(key_pressed_or_repeated(.DOWN) ||
	key_pressed_or_repeated(.UP)) {
		editor_input(&list.content)
		handled = true
	}

	return handled
}

list_draw :: proc(list: ^List) {
	editor_draw(&list.content)
	rl.DrawRectangleLinesEx(list.rect, 1, list.app.theme.selection)
}

list_get_current_item :: proc(list: ^List, aloc := context.allocator) -> (int, string) {
	index := editor_line_from_pos(&list.content, list.content.cursor.head)
	line_range := list.content.buffer.line_ranges[index]
	item := string(list.content.buffer.content[line_range.start:line_range.end])
	return index, strings.clone(item, aloc)
}

list_set_current_item :: proc(list: ^List, index: int) {
	if 0 <= index && index <= len(list.content.buffer.line_ranges) - 1 {		
		line_range := list.content.buffer.line_ranges[index]
		editor_goto(&list.content, line_range.start)	
	} 
}

list_clear :: proc(list: ^List) {
	editor_clear(&list.content)
}

list_set_rect :: proc(list: ^List, rect: rl.Rectangle) {
	list.rect = rect
	list.content.rect = rect
}