package list

import "core:strings"
import rl "vendor:raylib"
import buf "../buffer"
import ed "../editor"

List :: struct {
	content: ed.Editor,

	style: Style,
	rect: rl.Rectangle,
}

Style :: struct {
	content: ed.Style,
}

init :: proc(list: ^List, style: ^Style) {
	list.style = style^

	buffer: buf.Buffer; buf.init(&buffer) 
	ed.init(&list.content, &style.content, &buffer, "", "")
	
	list.content.hide_cursor = true
	list.content.hightlight_line = true
}

deinit :: proc(list: ^List) {
	ed.deinit(&list.content)
}

add_items :: proc(list: ^List, items: []string) {
	content := &list.content.buffer.content
	if 1 <= len(content) && content[len(content) - 1] != '\n' {
		ed.insert_raw(&list.content, &list.content.cursors[0], "\n") 
	}

	for item, i in items {
		ed.insert_raw(&list.content, &list.content.cursors[0], item) 
		if i != len(items) - 1 {
			ed.insert_raw(&list.content, &list.content.cursors[0], "\n") 
		}
	}
}

go_up :: proc(list: ^List) {
	ed.go_up(&list.content, &list.content.cursors[0])
}

go_down :: proc(list: ^List) {
	ed.go_down(&list.content, &list.content.cursors[0])
}

draw :: proc(list: ^List) {
	ed.draw(&list.content)
}

get_current_item :: proc(list: ^List, aloc := context.allocator) -> (int, string) {
	index := ed.line_from_pos(&list.content, list.content.cursors[0].head)
	line_range := list.content.buffer.line_ranges[index]
	item := string(list.content.buffer.content[line_range.start:line_range.end])
	return index, strings.clone(item, aloc)
}

set_current_item :: proc(list: ^List, index: int) {
	if 0 <= index && index <= len(list.content.buffer.line_ranges) - 1 {		
		line_range := list.content.buffer.line_ranges[index]
		ed.goto(&list.content, &list.content.cursors[0], line_range.start)	
	} 
}

clear :: proc(list: ^List) {
	ed.remove_all(&list.content)
}

set_rect :: proc(list: ^List, rect: rl.Rectangle) {
	list.rect = rect
	list.content.rect = rect
}

set_style :: proc(list: ^List, style: Style) {
	list.style = style
	ed.set_style(&list.content, style.content)
}