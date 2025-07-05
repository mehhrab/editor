package editor

import rl "vendor:raylib"
import fmt "core:fmt"
import "core:strings"
import "core:slice"
import "core:odin/tokenizer"
import "core:math"

Editor :: struct {
	app: ^App,
	buffer: Buffer,
	cursor: Cursor,
	hide_cursor: bool,
	scroll: f32,
	lexer: tokenizer.Tokenizer,
	highlight: bool,
	hightlight_line: bool,
	line_numbers: bool,
	rect: rl.Rectangle,
	active: bool,
}

Cursor :: struct {
	head: int,
	anchor: int,
	last_col: int,
	last_line_tabs: int,
}

editor_init :: proc(editor: ^Editor, app: ^App, buffer: ^Buffer) {
	editor.app = app
	editor.buffer = buffer^
}

editor_deinit :: proc(editor: ^Editor) {
	buffer_deinit(&editor.buffer)
}

editor_selected_text :: proc(editor: ^Editor) -> string {
	range := cursor_to_range(&editor.cursor)
	return string(editor.buffer.content[range.start:range.end])
}

editor_select :: proc(editor: ^Editor, range: Range) {
	editor_goto(editor, range.start)
	editor_goto(editor, range.end, true)
}

editor_all :: proc(editor: ^Editor) -> Range {
	return { 0, len(editor.buffer.content)}
}

editor_goto :: proc(editor: ^Editor, pos: int, select := false, remember_col := true) {
	pos := clamp(pos, 0, len(editor.buffer.content))
	if select == false {
		editor.cursor.anchor = pos
	}
	editor.cursor.head = pos	

	if remember_col {
		editor_remember_col(editor)
	}
}

cursor_to_range :: proc(cursor: ^Cursor) -> Range {
	return {
		min(cursor.head, cursor.anchor),
		max(cursor.head, cursor.anchor),
	}
}

editor_has_selection :: proc(editor: ^Editor) -> bool {
	return editor.cursor.head != editor.cursor.anchor
}

editor_remember_col :: proc(editor: ^Editor) {
	line := editor_get_cursor_line(editor)
	editor.cursor.last_col = col_real_to_visual(editor, line)
}

editor_get_cursor_line :: proc(editor: ^Editor) -> int {
	buffer := &editor.buffer
	line := 0
	for range, i in buffer.line_ranges {
		if range.start <= editor.cursor.head && editor.cursor.head <= range.end {
			line = i
			break
		} 
	}

	return line
}

editor_clamp_in_line :: proc(editor: ^Editor, pos, line: int) -> int {
	return clamp(pos, editor.buffer.line_ranges[line].start, editor.buffer.line_ranges[line].end)
}

editor_insert :: proc(editor: ^Editor, text: string, goto_end := true) {
	inject_at_elems(&editor.buffer.content, editor.cursor.head, ..transmute([]byte)text)
	buffer_calc_line_ranges(&editor.buffer)
	if goto_end {
		editor_goto(editor, editor.cursor.head + len(text))
	}
}

editor_delete :: proc(editor: ^Editor, goto_start := true) {
	cursor_range := cursor_to_range(&editor.cursor)
	remove_range(&editor.buffer.content, cursor_range.start, cursor_range.end)
	buffer_calc_line_ranges(&editor.buffer)
	if goto_start {
		editor_goto(editor, cursor_range.start)
	}
}

editor_clear :: proc(editor: ^Editor) {
	editor_goto(editor, 0)
	editor_goto(editor, len(editor.buffer.content), true)
	editor_delete(editor)
}

editor_input :: proc(editor: ^Editor) {
	buffer := &editor.buffer

	if rl.IsKeyPressed(.F1) {
		fmt.printfln("{}", editor.cursor.last_col)
	}
	
	shift_down := rl.IsKeyDown(.LEFT_SHIFT)
	if key_pressed_or_repeated(.RIGHT) {
		dest := 0
		if editor_has_selection(editor) && shift_down == false {
			cursor_range := cursor_to_range(&editor.cursor)
			dest = cursor_range.end
		}
		else {
			dest = editor.cursor.head + 1
		}
		editor_goto(editor, dest, shift_down)
	}
	else if key_pressed_or_repeated(.LEFT) {
		dest := 0
		if editor_has_selection(editor) && shift_down == false {
			cursor_range := cursor_to_range(&editor.cursor)
			dest = cursor_range.start
		}
		else {
			dest = editor.cursor.head - 1
		}
		editor_goto(editor, dest, shift_down)
	}
	else if key_pressed_or_repeated(.UP) {
		dest := 0
		line := editor_get_cursor_line(editor)
		if 0 < line {
			dest = buffer.line_ranges[line - 1].start
			dest += col_visual_to_real(editor, line - 1)
			dest = editor_clamp_in_line(editor, dest, line - 1)
		}
		editor_goto(editor, dest, shift_down, false)
	}
	else if key_pressed_or_repeated(.DOWN) {
		dest := 0
		line := editor_get_cursor_line(editor)
		if len(buffer.line_ranges) - 1 <= line {
			dest = len(buffer.content)
		}
		else {
			dest = buffer.line_ranges[line + 1].start
			dest += col_visual_to_real(editor, line + 1)
			dest = editor_clamp_in_line(editor, dest, line + 1)
		}
		editor_goto(editor, dest, shift_down, false)
	}
	else if key_pressed_or_repeated(.ENTER) {
		editor_delete(editor)
		editor_insert(editor, "\n")
	}
	else if key_pressed_or_repeated(.TAB) {
		editor_insert(editor, "\t")
	}
	else if key_pressed_or_repeated(.BACKSPACE) {
		if editor_has_selection(editor) == false {
			editor_goto(editor, editor.cursor.head - 1, true)
		} 
		editor_delete(editor)
	}
	else if rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyPressed(.L) {
		line := editor_get_cursor_line(editor)
		line_range := editor.buffer.line_ranges[line]
		editor_goto(editor, line_range.start, editor_has_selection(editor))
		editor_goto(editor, line_range.end + 1, true)
	}
	else if rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyPressed(.A) {
		editor_select(editor, editor_all(editor))
	}
	else if rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyPressed(.C) {
		if editor_has_selection(editor) {
			range := cursor_to_range(&editor.cursor)
			text := string(editor.buffer.content[range.start:range.end])
			// text = strings.join({ text, "\n" }, "", context.temp_allocator)
			rl.SetClipboardText(strings.clone_to_cstring(text, context.temp_allocator))
		}
		else {
			line := editor_get_cursor_line(editor)
			range := editor.buffer.line_ranges[line]
			text := string(editor.buffer.content[range.start:range.end])
			// text = strings.join({ text, "\n" }, "", context.temp_allocator)
			rl.SetClipboardText(strings.clone_to_cstring(text, context.temp_allocator))
		}
	}
	else if rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyPressed(.X) {
		range := Range {}
		if editor_has_selection(editor) {
			range = cursor_to_range(&editor.cursor)
			// if range.end < len(editor.buffer.content) {
			// 	range.end += 1
			// }
			text := string(editor.buffer.content[range.start:range.end])
			rl.SetClipboardText(strings.clone_to_cstring(text, context.temp_allocator))
		}
		else {
			line := editor_get_cursor_line(editor)
			range = editor.buffer.line_ranges[line]
			// if range.end < len(editor.buffer.content) {
			// 	range.end += 1
			// }
			text := string(editor.buffer.content[range.start:range.end])
			rl.SetClipboardText(strings.clone_to_cstring(text, context.temp_allocator))
		}
		editor_select(editor, range)
		editor_delete(editor)
	}
	else if rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyPressed(.V) {
		editor_delete(editor)
		text := strings.clone_from_cstring(rl.GetClipboardText(), context.temp_allocator)
		editor_insert(editor, text)
	}
	else {		
		for char in editor.app.chars_pressed {			
			editor_delete(editor)
			editor_insert(editor, fmt.tprint(char))
		}
	}
}

editor_draw :: proc(editor: ^Editor) {
	buffer := &editor.buffer
	font := &editor.app.font
	scroll := &editor.scroll

	current_line := editor_get_cursor_line(editor)
	if f32(current_line * 40) + 40 > editor.rect.height - scroll^ {
		scroll^ = -(f32((current_line + 1) * 40) - editor.rect.height)
	}
	if f32(current_line * 40) < -scroll^ {
		scroll^ = -(f32((current_line) * 40))
	}

	tokens := make([dynamic]tokenizer.Token, context.temp_allocator)
	tokenizer.init(&editor.lexer, string(editor.buffer.content[:]), "", nil)
	token := tokenizer.scan(&editor.lexer)
	for token.kind != .EOF {
		append(&tokens, token)
		token = tokenizer.scan(&editor.lexer)
	}
	if len(tokens) == 0 {
		append(&tokens, tokenizer.Token {})
	}

	// calculate visible lines
	first_line := int(math.floor(-(scroll^) / 40))
	last_line := int(math.ceil((editor.rect.height - (scroll^)) / 40))
	// HACK: for single line editors
	if len(buffer.line_ranges) == 1 {
		last_line = 0
	}
	// HACK: idk brah
	last_line = clamp(last_line, 0, len(buffer.line_ranges) - 1)
	first_line_range := buffer.line_ranges[first_line]
	last_line_range := buffer.line_ranges[last_line]

	line_num_w := f32(100)
	if editor.line_numbers == false {
		line_num_w = 0
	}

	rl.BeginScissorMode(
		i32(editor.rect.x), 
		i32(editor.rect.y), 
		i32(editor.rect.width), 
		i32(editor.rect.height))

	if editor.hightlight_line {		
		line_rec := rl.Rectangle {
			editor.rect.x,
			editor.rect.y + f32(current_line) * 40 + scroll^,
			editor.rect.width,
			40
		}
		rl.DrawRectangleRec(line_rec, { 255, 255, 255, 20 })
	}
	
	char_x := editor.rect.x + line_num_w
	char_y := f32(40 * first_line) + editor.rect.y + scroll^
	line := first_line
	token_index := 0
	for char, i in buffer.content[first_line_range.start:last_line_range.end] {		
		char_index := i + first_line_range.start 

		// highlighting
		// should only loop the first time to catch up
		for token_index < len(tokens) - 1 && tokens[token_index + 1].pos.offset <= char_index {
			token_index += 1
		} 
		token := tokens[token_index]
		char_color := rl.Color { 10, 140, 255, 255 }
		if editor.highlight { 
			char_color = get_color_for_token(token.kind)
		}

		// draw text
		char_cstring := fmt.ctprint(rune(char))
		char_w := rl.MeasureTextEx(font^, char_cstring, 40, 0)[0]
		if char == '\n' {
			char_w = rl.MeasureTextEx(font^, " ", 40, 0)[0]
		} else if char == '\t' {
			char_w = rl.MeasureTextEx(font^, "    ", 40, 0)[0]
		}
		rl.DrawTextEx(font^, char_cstring, { char_x, char_y }, 40, 0, char_color)
		
		// draw selection
		cursor_range := cursor_to_range(&editor.cursor)
		if cursor_range.start <= char_index && char_index < cursor_range.end {
			rl.DrawRectangleRec({ char_x, char_y, char_w, 40 }, { 255, 255, 255, 30 })
		} 

		if char == '\n' {
			char_x = editor.rect.x + line_num_w
			char_y += 40
			line += 1
			continue
		}
		else {
			char_x += char_w
		}
	}
	
	// draw line numbers
	if editor.line_numbers {		
		for i in first_line..=last_line {
			number_color := rl.Color { 255, 255, 255, 50 }
			if i == editor_get_cursor_line(editor) {
				number_color = rl.Color { 255, 255, 255, 150 }
			}
			pos := rl.Vector2 { editor.rect.x + 10, editor.rect.y + f32(i) * 40 + scroll^ }
			rl.DrawTextEx(font^, fmt.ctprint(i + 1), pos, 40, 0, number_color)
		}
	}

	// draw cursor
	if editor.hide_cursor == false {
		line := editor_get_cursor_line(editor)
		cursor_x := editor.rect.x + line_num_w
		cursor_y := editor.rect.y + f32(line) * 40 + scroll^
		for i in buffer.line_ranges[line].start..<editor.cursor.head {
			char := rune(buffer.content[i])
			char_cstring := fmt.ctprint(char)
			char_w := rl.MeasureTextEx(font^, char_cstring, 40, 0)[0]
			if char == '\t' {
				char_w = rl.MeasureTextEx(font^, "    ", 40, 0)[0]
			}
			cursor_x += char_w
		}
		rl.DrawRectangleRec({ cursor_x, cursor_y, 2, 40 }, rl.SKYBLUE)
	}
	rl.EndScissorMode()
}

get_color_for_token :: proc(kind: tokenizer.Token_Kind) -> rl.Color {
	color := rl.Color { 10, 140, 255, 255 }
	if kind == .Ident {
		color = rl.SKYBLUE
		color.b -= 20
	}
	else if kind == .String {
		color = rl.GREEN
	}
	else if kind == .Comment {
		color = { 10, 120, 100, 255 }
	}
	else if kind == .Float || kind == .Integer {
		color = { 170, 100, 220, 255 }
	}
	else if kind == .Pointer || kind == .And {
		color = { 100, 100, 220, 255 }
	}
	return color
}

col_visual_to_real :: proc(editor: ^Editor, line: int) -> int {
	line_range := editor.buffer.line_ranges[line]
	col := 0
	to_move := editor.cursor.last_col
	for {
		i := line_range.start + col
		if len(editor.buffer.content) <= i {
			break
		}
		if to_move < 4 {
			if editor.buffer.content[i] != '\t' {
				col += to_move
			}
			else {
				col += int(math.ceil(f32(to_move) / 4 - 0.5))
			}
			break
		}
		if editor.buffer.content[i] == '\t' {
			col += 1
			to_move -= 4
		}
		else {
			col += 1
			to_move -= 1
		}
	}
	return col
}

col_real_to_visual :: proc(editor: ^Editor, line: int) -> int {
	col := 0
	for i in editor.buffer.line_ranges[line].start..<editor.cursor.head {
		c := editor.buffer.content[i]
		if c == '\t' {
			col += 4
		}
		else {
			col += 1
		}
	}
	return col
}