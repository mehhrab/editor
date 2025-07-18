package editor

import rl "vendor:raylib"
import "core:fmt"

Find :: struct {
	editor: ^Editor,
	visible: bool,
	input: Editor,
	word: string,
	matches: [dynamic]Range,
	match_index: int,
	cursor_before_search: Cursor,
	scroll_x_before_search: f32,
	scroll_y_before_search: f32,
}

find_init :: proc(find: ^Find, app: ^App, editor: ^Editor) {
	find.editor = editor
	buffer: Buffer; buffer_init(&buffer, "")
	editor_init(&find.input, app, &buffer, "", "")
}

find_deinit :: proc(find: ^Find) {
	editor_deinit(&find.input)
	delete(find.matches)
}

find_matches :: proc(find: ^Find) {
	editor := find.editor
	
	clear(&find.matches)
	clear(&find.editor.highlighted_ranges)
	find.match_index = 0

	word := string(find.input.buffer.content[:])
	if word != "" {		
		i := 0
		for i < len(editor.buffer.content) {
			matched := true
			match_start := i
			for w in word {
				char := editor.buffer.content[i]
				if rune(char) != w {
					matched = false
					break
				}
				i += 1
			}
			if matched {
				range := Range { match_start, i }
				append(&find.matches, range)
				append(&find.editor.highlighted_ranges, range)
			}
			i += 1
		}
	}
}

find_next :: proc(find: ^Find) {
	editor := find.editor
	if len(find.matches) != 0 {		
		editor_goto(editor, find.matches[find.match_index].start)	
		editor_goto(editor, find.matches[find.match_index].end, true)	

		// center found match vertically
		line_index := editor_line_from_pos(editor, find.matches[find.match_index].start)
		editor.scroll_y = -(f32(line_index) * 40 - f32(rl.GetScreenHeight()) / 2)  
		if editor.scroll_y > 0 {
			editor.scroll_y = 0
		}

		find.match_index = (find.match_index + 1) % len(find.matches)
	}
	else {
		fmt.printfln("no match")
	}
}

find_input :: proc(find: ^Find) -> bool {
	app := find.editor.app
	
	if find.visible == false {
		return false
	}

	handled := false
	if rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyPressed(.N) {
		find_next(find)
		handled = true
	}
	else if rl.IsKeyPressed(.ENTER) {
		find_hide(find)
		handled = true
	}
	else {
		handled = editor_input(&find.input)
		if rl.IsKeyPressed(.BACKSPACE) {
			find_matches(find)
			find_next(find)
			handled = true
		}
		for char in app.chars_pressed {
			find_matches(find)
			find_next(find)
			handled = true
		}
	}
	return handled
}

find_draw :: proc(find: ^Find) {
	editor_draw(&find.input)
	rl.DrawRectangleLinesEx(find.input.rect, 1, rl.SKYBLUE)
}

find_show :: proc(find: ^Find, word := "") {
	find.visible = true
	
	find.cursor_before_search = find.editor.cursor
	find.scroll_x_before_search = find.editor.scroll_x
	find.scroll_y_before_search = find.editor.scroll_y

	if word != "" {
		editor_select(&find.input, editor_all(&find.input))
		editor_delete(&find.input)
		editor_insert(&find.input, word)
	}
	editor_select(&find.input, editor_all(&find.input))
	
	find_matches(find)
	if word != "" {
		find_next(find)
	}
}

find_hide :: proc(find: ^Find) {
	clear(&find.editor.highlighted_ranges)
	find.visible = false
}

find_cancel :: proc(find: ^Find) {
	find.editor.cursor = find.cursor_before_search
	find.editor.scroll_x = find.scroll_x_before_search
	find.editor.scroll_y = find.scroll_y_before_search
	find_hide(find)
}