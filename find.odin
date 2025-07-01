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
}

find_init :: proc(find: ^Find, app: ^App, editor: ^Editor) {
	find.editor = editor
	buffer: Buffer; buffer_init(&buffer, "")
	editor_init(&find.input, app, &buffer)
}

find_deinit :: proc(find: ^Find) {
	editor_deinit(&find.input)
	delete(find.matches)
}

find_matches :: proc(find: ^Find) {
	editor := find.editor
	
	clear(&find.matches)
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
				append(&find.matches, Range { match_start, i })
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
		find.match_index = (find.match_index + 1) % len(find.matches)
	}
	else {
		fmt.printfln("no match")
	}
}

find_input :: proc(find: ^Find) -> bool {
	app := find.editor.app

	handled := false
	if rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyPressed(.N) {
		find_next(find)
		handled = true
	}
	else if rl.IsKeyPressed(.ENTER) {
		find_hide(find)
		handled = true
	}
	else if rl.IsKeyPressed(.ESCAPE) {
		find.editor.cursor = find.cursor_before_search
		find_hide(find)
		handled = true
	}
	else {
		editor_input(&find.input)
		if rl.IsKeyPressed(.BACKSPACE) {
			find_matches(find)
			find_next(find)
		}
		for char in app.chars_pressed {
			find_matches(find)
			find_next(find)
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
	find.visible = false
}