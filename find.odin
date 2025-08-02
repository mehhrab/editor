package editor

import rl "vendor:raylib"
import "core:fmt"
import "core:strings"
import buf "buffer"

Find :: struct {
	app: ^App,
	
	input: Editor,
	
	text: string,
	
	matches: [dynamic]Range,
	match_index: int,
	
	events: [dynamic]Find_Event,
	visible: bool,
}

Find_Event :: union {
	Find_New_Match,
	Find_All_Matches,
	Find_Confirm,
}

Find_All_Matches :: struct {
	matches: []Range,
}

Find_New_Match :: struct {
	index: int,
	range: Range,
}

Find_Confirm :: struct {}

find_init :: proc(find: ^Find, app: ^App) {
	find.app = app
	buffer: buf.Buffer; buf.init(&buffer, "")
	editor_init(&find.input, app, &buffer, "", "")
}

find_deinit :: proc(find: ^Find) {
	editor_deinit(&find.input)
	delete(find.matches)
	delete(find.events)
	delete(find.text)
}

find_calc_matches :: proc(find: ^Find) -> []Range {	
	clear(&find.matches)
	find.match_index = 0

	word := string(find.input.buffer.content[:])
	if word != "" {
		i := 0
		for i < len(find.text) {
			matched := true
			match_start := i
			for w in word {
				char := find.text[i]
				if rune(char) != w {
					matched = false
					break
				}
				i += 1
			}
			if matched {
				range := Range { match_start, i }
				append(&find.matches, range)
			}
			i += 1
		}
	}

	return find.matches[:]
}

find_next :: proc(find: ^Find) -> (int, Range) {
	index := 0
	range := Range {}
	if len(find.matches) != 0 {		
		index = find.match_index
		range = find.matches[index]
		find.match_index = (find.match_index + 1) % len(find.matches)
	}
	return index, range
}

find_input :: proc(find: ^Find) -> ([]Find_Event, bool) {	
	app := find.app
	
	clear(&find.events)

	if find.visible == false {
		return find.events[:], false
	}

	handled := false
	if rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyPressed(.ENTER) {
		append(&find.events, Find_Confirm {})
		handled = true
	}
	else if key_pressed_or_repeated(.ENTER) {
		index, range := find_next(find)
		append(&find.events, Find_New_Match {
			index = index,
			range = range
		})
		handled = true
	}
	else {
		handled = editor_input(&find.input)
		if rl.IsKeyPressed(.BACKSPACE) {
			matches := find_calc_matches(find)
			append(&find.events, Find_All_Matches {
				matches = matches,
			})

			index, range := find_next(find)
			append(&find.events, Find_New_Match {
				index = index,
				range = range
			})
			
			handled = true
		}
		for char in app.chars_pressed {
			matches := find_calc_matches(find)
			append(&find.events, Find_All_Matches {
				matches = matches,
			})

			index, range := find_next(find)
			append(&find.events, Find_New_Match {
				index = index, 
				range = range
			})
			
			handled = true
		}
	}
	return find.events[:], handled
}

find_draw :: proc(find: ^Find) {
	editor_draw(&find.input)
	rl.DrawRectangleLinesEx(find.input.rect, 1, rl.SKYBLUE)
}

find_show :: proc(find: ^Find, word := "") {
	find.visible = true

	if word != "" {
		editor_select(&find.input, editor_all(&find.input))
		editor_delete(&find.input)
		editor_insert(&find.input, word)
	}
	editor_select(&find.input, editor_all(&find.input))
}

find_hide :: proc(find: ^Find) {
	find.visible = false
}

find_set_text :: proc(find: ^Find, text: string) {
	delete(find.text)
	find.text = strings.clone(text)
}