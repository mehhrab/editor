package editor

import rl "vendor:raylib"
import fmt "core:fmt"
import "core:strings"
import "core:slice"
import "core:odin/tokenizer"
import "core:math"
import buf "../buffer"
import "../range"
import "../syntax"

Range :: range.Range

Editor :: struct {
	// TODO: move these two outta here
	path: string,
	name: string,

	buffer: buf.Buffer,
	
	cursor: Cursor,
	hide_cursor: bool,
	scroll_x: f32,
	scroll_y: f32,

	syntax: syntax.Syntax,
	lexer: tokenizer.Tokenizer,
	highlighted_ranges: [dynamic]Range,
	
	highlight: bool,
	hightlight_line: bool,
	line_numbers: bool,
	
	undos: [dynamic]Undo,
	undo_index: int,

	style: Style,
	rect: rl.Rectangle,
	active: bool,
}

Cursor :: struct {
	head: int,
	anchor: int,
	last_col: int,
}

Undo :: struct {
	kind: Undo_Kind,
	text: string,
	change_range: Range,
	time: f32,
}

Undo_Kind :: enum {
	Insert,
	Delete,
}

Style :: struct {
	font: rl.Font,
	font_size: f32,
	text_color: rl.Color,
	text_color2: rl.Color,
	bg_color: rl.Color,
	select_color: rl.Color,
	highlight_color: rl.Color,
	caret_color: rl.Color,
}

init :: proc(editor: ^Editor, style: ^Style, buffer: ^buf.Buffer, path, name: string) {
	editor.style = style^
	editor.buffer = buffer^
	editor.path = strings.clone(path)
	editor.name = strings.clone(name)
}

deinit :: proc(editor: ^Editor) {
	buf.deinit(&editor.buffer)
	delete(editor.path)
	delete(editor.name)
	delete(editor.highlighted_ranges)
	for &undo in editor.undos {
		undo_deinit(&undo)
	}
	delete(editor.undos)
}

selected_text :: proc(editor: ^Editor) -> string {
	range := cursor_to_range(&editor.cursor)
	return string(editor.buffer.content[range.start:range.end])
}

select :: proc(editor: ^Editor, range: Range) {
	goto(editor, range.start)
	goto(editor, range.end, true)
}

all :: proc(editor: ^Editor) -> Range {
	return { 0, len(editor.buffer.content)}
}

goto :: proc(editor: ^Editor, pos: int, select := false, remember_col := true) {
	pos := clamp(pos, 0, len(editor.buffer.content))
	if select == false {
		editor.cursor.anchor = pos
	}
	editor.cursor.head = pos	

	if remember_col {
		save_col(editor)
	}
}

cursor_to_range :: proc(cursor: ^Cursor) -> Range {
	return {
		min(cursor.head, cursor.anchor),
		max(cursor.head, cursor.anchor),
	}
}

has_selection :: proc(editor: ^Editor) -> bool {
	return editor.cursor.head != editor.cursor.anchor
}

save_col :: proc(editor: ^Editor) {
	line := line_from_pos(editor, editor.cursor.head)
	editor.cursor.last_col = col_real_to_visual(editor, line)
}

line_from_pos :: proc(editor: ^Editor, pos: int) -> int {
	buffer := &editor.buffer
	line := 0
	for range, i in buffer.line_ranges {
		if range.start <= pos && pos <= range.end {
			line = i
			break
		} 
	}

	return line
}

clamp_in_line :: proc(editor: ^Editor, pos, line: int) -> int {
	return clamp(pos, editor.buffer.line_ranges[line].start, editor.buffer.line_ranges[line].end)
}

insert :: proc(editor: ^Editor, text: string, goto_end := true) -> Range {
	change_range := insert_raw(editor, text, goto_end)
	push_undo(editor, .Insert, change_range, text)
	return change_range
}

insert_raw :: proc(editor: ^Editor, text: string, goto_end := true) -> Range {
	change_range := Range { editor.cursor.head, editor.cursor.head + len(text) }
	
	inject_at_elems(&editor.buffer.content, editor.cursor.head, ..transmute([]byte)text)
	buf.calc_line_ranges(&editor.buffer)
	if goto_end {
		goto(editor, editor.cursor.head + len(text))
	}

	return change_range
}

remove :: proc(editor: ^Editor, goto_start := true) {
	// clone this since we are gonna remove the selection one line later
	text := strings.clone(selected_text(editor), context.temp_allocator)
	change_range := remove_raw(editor, goto_start)	
	push_undo(editor, .Delete, change_range, text)
}

remove_raw :: proc(editor: ^Editor, goto_start := true) -> Range {
	change_range := cursor_to_range(&editor.cursor)
	remove_range(&editor.buffer.content, change_range.start, change_range.end)
	buf.calc_line_ranges(&editor.buffer)
	if goto_start {
		goto(editor, change_range.start)
	}
	return change_range
}

replace :: proc(editor: ^Editor, text: string) {
	remove(editor)
	insert(editor, text)
}

clear :: proc(editor: ^Editor) {
	goto(editor, 0)
	goto(editor, len(editor.buffer.content), true)
	remove(editor)
}

go_right :: proc(editor: ^Editor, select := false) {
	dest := 0
	if has_selection(editor) && select == false {
		cursor_range := cursor_to_range(&editor.cursor)
		dest = cursor_range.end
	}
	else {
		dest = editor.cursor.head + 1
	}
	goto(editor, dest, select)
}

go_left :: proc(editor: ^Editor, select := false) {
	dest := 0
	if has_selection(editor) && select == false {
		cursor_range := cursor_to_range(&editor.cursor)
		dest = cursor_range.start
	}
	else {
		dest = editor.cursor.head - 1
	}
	goto(editor, dest, select)	
}

go_up :: proc(editor: ^Editor, select := false) {
	dest := 0
	line := line_from_pos(editor, editor.cursor.head)
	if 0 < line {
		dest = editor.buffer.line_ranges[line - 1].start
		dest += col_visual_to_real(editor, line - 1)
		dest = clamp_in_line(editor, dest, line - 1)
	}
	goto(editor, dest, select, false)	
}

go_down :: proc(editor: ^Editor, select := false) {
	dest := 0
	line := line_from_pos(editor, editor.cursor.head)
	if len(editor.buffer.line_ranges) - 1 <= line {
		dest = len(editor.buffer.content)
	}
	else {
		dest = editor.buffer.line_ranges[line + 1].start
		dest += col_visual_to_real(editor, line + 1)
		dest = clamp_in_line(editor, dest, line + 1)
	}
	goto(editor, dest, select, false)	
}

back_space :: proc(editor: ^Editor) {
	if has_selection(editor) == false {
		goto(editor, editor.cursor.head - 1, true)
	} 
	remove(editor)
}

select_line :: proc(editor: ^Editor) {
	line := line_from_pos(editor, editor.cursor.head)
	line_range := editor.buffer.line_ranges[line]
	goto(editor, line_range.start, has_selection(editor))
	goto(editor, line_range.end + 1, true)
}

copy :: proc(editor: ^Editor) {
	if has_selection(editor) {
		range := cursor_to_range(&editor.cursor)
		text := string(editor.buffer.content[range.start:range.end])
		rl.SetClipboardText(strings.clone_to_cstring(text, context.temp_allocator))
	}
	else {
		line := line_from_pos(editor, editor.cursor.head)
		range := editor.buffer.line_ranges[line]
		text := string(editor.buffer.content[range.start:range.end])
		rl.SetClipboardText(strings.clone_to_cstring(text, context.temp_allocator))
	}
}

cut :: proc(editor: ^Editor) {
	range := Range {}
	if has_selection(editor) {
		range = cursor_to_range(&editor.cursor)
		text := string(editor.buffer.content[range.start:range.end])
		rl.SetClipboardText(strings.clone_to_cstring(text, context.temp_allocator))
	}
	else {
		line := line_from_pos(editor, editor.cursor.head)
		range = editor.buffer.line_ranges[line]
		text := string(editor.buffer.content[range.start:range.end])
		rl.SetClipboardText(strings.clone_to_cstring(text, context.temp_allocator))
	}
	select(editor, range)
	remove(editor)
}

paste :: proc(editor: ^Editor) {
	remove(editor)
	text := strings.clone_from_cstring(rl.GetClipboardText(), context.temp_allocator)
	insert(editor, text)
}

// insert_char :: proc(editor: ^Editor, char: rune) {
// 	remove(editor)
// 	insert(editor, fmt.tprint(char))
// }

// input :: proc(editor: ^Editor) -> bool {
// 	buffer := &editor.buffer

// 	handled := false
	
// 	shift_down := rl.IsKeyDown(.LEFT_SHIFT)
// 	if key_pressed_or_repeated(.RIGHT) {
		
// 		handled = true
// 	}
// 	else if key_pressed_or_repeated(.LEFT) {
// 		handled = true
// 	}
// 	else if key_pressed_or_repeated(.UP) {
// 		handled = true
// 	}
// 	else if key_pressed_or_repeated(.DOWN) {
// 		handled = true
// 	}
// 	else if key_pressed_or_repeated(.ENTER) {
// 		remove(editor)
// 		insert(editor, "\n")
// 		handled = true
// 	}
// 	else if key_pressed_or_repeated(.TAB) {
// 		insert(editor, "\t")
// 		handled = true
// 	}
// 	else if key_pressed_or_repeated(.BACKSPACE) {
		
// 		handled = true
// 	}
// 	else if rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyPressed(.L) {
// 		handled = true
// 	}
// 	else if rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyPressed(.A) {
// 		select(editor, all(editor))
// 		handled = true
// 	}
// 	else if rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyPressed(.C) {
		
// 		handled = true
// 	}
// 	else if rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyPressed(.X) {
// 		handled = true
// 	}
// 	else if rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyPressed(.V) {
// 		handled = true
// 	}
// 	else if rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyPressed(.Z) {
// 		undo(editor)
// 		handled = true
// 	}
// 	else if rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyPressed(.Y) {
// 		redo(editor)
// 		handled = true
// 	}
// 	else {		
// 		for char in editor.app.chars_pressed {			
			
// 			handled = true
// 		}
// 	}

// 	return handled
// }

draw :: proc(editor: ^Editor) {
	buffer := &editor.buffer
	style := &editor.style
	scroll_x := &editor.scroll_x
	scroll_y := &editor.scroll_y

	pad := f32(20)
	
	lines_rect := rl.Rectangle {
		editor.rect.x,
		editor.rect.y,
		editor.line_numbers ? 100 : 0,
		editor.rect.height,
	}
	code_rect := rl.Rectangle {
		editor.rect.x + lines_rect.width + pad,
		editor.rect.y,
		editor.rect.width - lines_rect.width - pad,
		editor.rect.height,
	}

	rl.DrawRectangleRec(editor.rect, style.bg_color)
	
	current_line := line_from_pos(editor, editor.cursor.head)
	
	look_ahead_x := f32(80)
	look_ahead_y := f32(80)

	// calculate scroll_x
	cursor_x := f32(0)
	for i in buffer.line_ranges[current_line].start..<editor.cursor.head {
		char := buffer.content[i]
		char_cstring := fmt.ctprint(rune(char))
		char_w := rl.MeasureTextEx(style.font, char_cstring, 40, 0)[0]
		if char == '\t' {
			char_w = rl.MeasureTextEx(style.font, "    ", 40, 0)[0]
		}
		cursor_x += char_w
	}

	if code_rect.width < cursor_x + scroll_x^ + look_ahead_x {
		scroll_x^ = code_rect.width - cursor_x - look_ahead_y
	}
	else if cursor_x < -scroll_x^ {
		scroll_x^ = -cursor_x
	}

	// calculate scroll_y
	current_line_y := f32(current_line * 40)
	if code_rect.height - scroll_y^ < current_line_y + look_ahead_y {
		scroll_y^ = -(current_line_y - code_rect.height + look_ahead_y)
	}
	if current_line_y < -scroll_y^ {
		scroll_y^ = -current_line_y
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
	first_line := int(math.floor(-(scroll_y^) / 40))
	last_line := int(math.ceil((code_rect.height - (scroll_y^)) / 40))
	// HACK: for single line editors
	if len(buffer.line_ranges) == 1 {
		last_line = 0
	}
	// HACK: idk brah
	first_line = clamp(first_line, 0, len(buffer.line_ranges) - 1)
	last_line = clamp(last_line, 0, len(buffer.line_ranges) - 1)
	first_line_range := buffer.line_ranges[first_line]
	last_line_range := buffer.line_ranges[last_line]

	rl.BeginScissorMode(
		i32(editor.rect.x), 
		i32(editor.rect.y), 
		i32(editor.rect.width), 
		i32(editor.rect.height))

	if editor.hightlight_line {		
		highlight := rl.Rectangle {
			editor.rect.x,
			editor.rect.y + f32(current_line) * 40 + scroll_y^,
			editor.rect.width,
			40
		}
		rl.DrawRectangleRec(highlight, style.highlight_color)
	}
	
	start_x := code_rect.x + scroll_x^ 
	char_x := start_x
	char_y := f32(40 * first_line) + code_rect.y + scroll_y^
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
		char_color := style.text_color
		if editor.highlight { 
			char_color = get_color_for_token(&editor.syntax, token.kind)
		}

		char_cstring := fmt.ctprint(rune(char))
		char_w := rl.MeasureTextEx(style.font, char_cstring, 40, 0)[0]
		if char == '\n' {
			char_w = rl.MeasureTextEx(style.font, " ", 40, 0)[0]
		} else if char == '\t' {
			char_w = rl.MeasureTextEx(style.font, "    ", 40, 0)[0]
		}

		// draw selection
		cursor_range := cursor_to_range(&editor.cursor)
		if cursor_range.start <= char_index && char_index < cursor_range.end {
			rl.DrawRectangleRec({ char_x, char_y, char_w, 40 }, style.select_color)
		} 

		// draw highlighted ranges
		for range in editor.highlighted_ranges {
			if range.start <= char_index && char_index < range.end {
				rl.DrawRectangleRec({ char_x, char_y, char_w, 40 }, style.select_color)
			}
		}

		// draw text
		rl.DrawTextEx(style.font, char_cstring, { char_x, char_y }, 40, 0, char_color)
		
		if char == '\n' {
			char_x = start_x
			char_y += 40
			line += 1
			continue
		}
		else {
			char_x += char_w
		}
	}
	
	// draw line numbers
	// rl.DrawRectangleRec(lines_rect, style.)
	if editor.line_numbers {		
		for i in first_line..=last_line {
			number_color := style.text_color2
			if i == line_from_pos(editor, editor.cursor.head) {
				number_color = style.text_color
			}
			pos := rl.Vector2 { lines_rect.x + 10, lines_rect.y + f32(i) * 40 + scroll_y^ }
			rl.DrawTextEx(style.font, fmt.ctprint(i + 1), pos, 40, 0, number_color)
		}

		shadow_rect := rl.Rectangle { 
			lines_rect.x + lines_rect.width, 
			editor.rect.y, 
			30, 
			editor.rect.height 
		}
		shadow_color := rl.Color { 0, 0, 0, 50 }
		rl.DrawRectangleGradientEx(shadow_rect, shadow_color, shadow_color, {}, {})
	}

	// draw cursor
	if editor.hide_cursor == false {
		line := line_from_pos(editor, editor.cursor.head)
		cursor_x := code_rect.x + scroll_x^
		cursor_y := code_rect.y + f32(line) * 40 + scroll_y^
		for i in buffer.line_ranges[line].start..<editor.cursor.head {
			char := rune(buffer.content[i])
			char_cstring := fmt.ctprint(char)
			char_w := rl.MeasureTextEx(style.font, char_cstring, 40, 0)[0]
			if char == '\t' {
				char_w = rl.MeasureTextEx(style.font, "    ", 40, 0)[0]
			}
			cursor_x += char_w
		}
		rl.DrawRectangleRec({ cursor_x, cursor_y, 2, 40 }, style.caret_color)
	}
	rl.EndScissorMode()
}

get_color_for_token :: proc(syntax: ^syntax.Syntax, kind: tokenizer.Token_Kind) -> rl.Color {
	color := syntax.default
	if kind == .Ident {
		color = syntax.symbol
	}
	else if kind == .String {
		color = syntax.sstring
	}
	else if kind == .Comment {
		color = syntax.comment
	}
	else if kind == .Float || kind == .Integer {
		color = syntax.number
	}

	return color
}

// TODO: add horizontal version of this
scroll_center_v :: proc(editor: ^Editor, pos: int) {
	line_index := line_from_pos(editor, pos)
	editor.scroll_y = -(f32(line_index) * 40 - f32(rl.GetScreenHeight()) / 2)  
	if editor.scroll_y > 0 {
		editor.scroll_y = 0
	}
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

undo :: proc(editor: ^Editor) {
	for 1 <= editor.undo_index {
		editor.undo_index -= 1
		undo := editor.undos[editor.undo_index]

		if undo.kind == .Insert {
			select(editor, undo.change_range)
			remove_raw(editor)
		}
		else if undo.kind == .Delete {
			goto(editor, undo.change_range.start)
			insert_raw(editor, undo.text)
			select(editor, undo.change_range)
		}
		
		can_be_mereged := 1 <= editor.undo_index && 
		(undo.time - editor.undos[editor.undo_index - 1].time) < 0.3

		if can_be_mereged {
			continue
		}
		else {
			break
		}
	}
}

redo :: proc(editor: ^Editor) {
	for editor.undo_index <= len(editor.undos) - 1 {
		undo := editor.undos[editor.undo_index]

		if undo.kind == .Insert {
			insert_raw(editor, undo.text)
		}
		else if undo.kind == .Delete {
			select(editor, undo.change_range)
			remove_raw(editor)
		}

		can_be_mereged := editor.undo_index + 1 <= len(editor.undos) - 1 && 
		(editor.undos[editor.undo_index + 1].time - undo.time) < 0.3

		editor.undo_index += 1

		if can_be_mereged {
			continue
		}
		else {
			break
		}
	}
}

push_undo :: proc(editor: ^Editor, kind: Undo_Kind, range: Range, text: string) {
	for i := len(editor.undos) - 1; editor.undo_index <= i; i -= 1 {
		undo := pop(&editor.undos)
		undo_deinit(&undo)
	}

	append(&editor.undos, Undo {
		kind = kind,
		change_range = range,
		text = strings.clone(text),
		time = f32(rl.GetTime()),
	})
	editor.undo_index += 1
}

undo_deinit :: proc(undo: ^Undo) {
	delete(undo.text)
}

set_style :: proc(editor: ^Editor, style: Style) {
	editor.style = style
}