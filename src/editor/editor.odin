package editor

import "core:fmt"
import "core:strings"
import "core:slice"
import "core:odin/tokenizer"
import "core:math"
import rl "vendor:raylib"
import buf "../buffer"
import rg "../range"
import sy "../syntax"

Editor :: struct {
	// TODO: move these two outta here
	path: string,
	name: string,

	buffer: buf.Buffer,
	
	cursors: [dynamic]Cursor,
	hide_cursor: bool,
	scroll_x: f32,
	scroll_y: f32,

	syntax: sy.Syntax,
	lexer: tokenizer.Tokenizer,
	highlighted_ranges: [dynamic]rg.Range,
	
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
	change_range: rg.Range,
	time: f32,
	cursor: Cursor,
	cursors_before: []Cursor,
	cursors_after: []Cursor,
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
	add_cursor(editor, 0, 0)
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
	delete(editor.cursors)
}

add_cursor :: proc(editor: ^Editor, anchor, head: int) {
	cursor := Cursor {
		anchor = anchor,
		head = head,
		last_col = 0,
	}
	remember_col(editor, &cursor)
	append(&editor.cursors, cursor)
}

select :: proc(editor: ^Editor, cursor: ^Cursor, range: rg.Range) {
	goto(editor, cursor, range.start)
	goto(editor, cursor, range.end, true)
}

selected_text :: proc(editor: ^Editor, cursor: ^Cursor) -> string {
	range := cursor_to_range(cursor)
	return string(editor.buffer.content[range.start:range.end])
}

all :: proc(editor: ^Editor) -> rg.Range {
	return { 0, len(editor.buffer.content)}
}

goto :: proc(editor: ^Editor, cursor: ^Cursor, pos: int, select := false, remember_column := true) {
	pos := clamp(pos, 0, len(editor.buffer.content))
	if select == false {
		cursor.anchor = pos
	}
	cursor.head = pos	

	if remember_column {
		remember_col(editor, cursor)
	}
}

remove_extra_cursors :: proc(editor: ^Editor, loc := #caller_location) {
	for i := len(editor.cursors) - 1; i >= 1 ; i -= 1 {
		ordered_remove(&editor.cursors, i)
	}
}

cursor_to_range :: proc(cursor: ^Cursor) -> rg.Range {
	return {
		min(cursor.head, cursor.anchor),
		max(cursor.head, cursor.anchor),
	}
}

has_selection :: proc(editor: ^Editor, cursor: ^Cursor) -> bool {
	return cursor.head != cursor.anchor
}

remember_col :: proc(editor: ^Editor, cursor: ^Cursor) {
	line := line_from_pos(editor, cursor.head)
	cursor.last_col = col_real_to_visual(editor, line, cursor.head)
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

insert :: proc(editor: ^Editor, cursor: ^Cursor, text: string, goto_end := true) -> (rg.Range, rg.Range) {
	deleted_text := strings.clone(selected_text(editor, cursor), context.temp_allocator)

	cursors_before := slice.clone(editor.cursors[:], context.temp_allocator)
	deleted_range, inserted_range := insert_raw(editor, cursor, text, goto_end)
	cursors_after := slice.clone(editor.cursors[:], context.temp_allocator)

	push_undo(editor, .Delete, deleted_range, deleted_text, cursors_before, cursors_after)
	push_undo(editor, .Insert, inserted_range, text, cursors_before, cursors_after)

	return deleted_range, inserted_range
}

insert_raw :: proc(editor: ^Editor, cursor: ^Cursor, text: string, goto_end := true) -> (rg.Range, rg.Range) {
	cursor_range := cursor_to_range(cursor)

	buf.replace(&editor.buffer, cursor_range, text)
	
	// adjust cursors
	change_length := len(text) - rg.length(cursor_range)
	for &other in editor.cursors {
		if cursor.head < other.head {
			other.anchor += change_length
			other.head += change_length
		}
	}

	if goto_end {
		goto(editor, cursor, cursor_range.start + len(text))
	}

	return cursor_range, { cursor_range.start, cursor_range.start + len(text) }
}

remove :: proc(editor: ^Editor, cursor: ^Cursor, goto_start := true) -> rg.Range {
	text := strings.clone(selected_text(editor, cursor), context.temp_allocator)
	cursors_before := slice.clone(editor.cursors[:], context.temp_allocator)
	change_range := remove_raw(editor, cursor, goto_start)
	cursors_after := slice.clone(editor.cursors[:], context.temp_allocator)
	push_undo(editor, .Delete, change_range, text, cursors_before, cursors_after)
	return change_range
}

remove_raw :: proc(editor: ^Editor, cursor: ^Cursor, goto_start := true) -> rg.Range {
	change_range := cursor_to_range(cursor)
	change_length := rg.length(change_range)

	buf.remove(&editor.buffer, change_range)

	// adjust cursors
	for &other in editor.cursors {
		if cursor.head < other.head {
			other.head -= change_length
			other.anchor -= change_length
		}
	}

	if goto_start {
		goto(editor, cursor, change_range.start)
	}

	return change_range
}

remove_all :: proc(editor: ^Editor) {
	remove_extra_cursors(editor)
	select(editor, &editor.cursors[0], all(editor))
	remove(editor, &editor.cursors[0])
}

go_right :: proc(editor: ^Editor, cursor: ^Cursor, select := false) {
	dest := 0
	if has_selection(editor, cursor) && select == false {
		cursor_range := cursor_to_range(cursor)
		dest = cursor_range.end
	}
	else {
		dest = cursor.head + 1
	}
	goto(editor, cursor, dest, select)
}

go_left :: proc(editor: ^Editor, cursor: ^Cursor, select := false) {
	dest := 0
	if has_selection(editor, cursor) && select == false {
		cursor_range := cursor_to_range(cursor)
		dest = cursor_range.start
	}
	else {
		dest = cursor.head - 1
	}
	goto(editor, cursor, dest, select)	
}

go_up :: proc(editor: ^Editor, cursor: ^Cursor, select := false) {
	dest := 0
	line := line_from_pos(editor, cursor.head)
	if 0 < line {
		dest = editor.buffer.line_ranges[line - 1].start
		dest += col_visual_to_real(editor, line - 1, cursor.last_col)
		dest = clamp_in_line(editor, dest, line - 1)
	}
	goto(editor, cursor, dest, select, false)	
}

go_down :: proc(editor: ^Editor, cursor: ^Cursor, select := false) {
	dest := 0
	line := line_from_pos(editor, cursor.head)
	if len(editor.buffer.line_ranges) - 1 <= line {
		dest = len(editor.buffer.content)
	}
	else {
		dest = editor.buffer.line_ranges[line + 1].start
		dest += col_visual_to_real(editor, line + 1, cursor.last_col)
		dest = clamp_in_line(editor, dest, line + 1)
	}
	goto(editor, cursor, dest, select, false)	
}

back_space :: proc(editor: ^Editor) {
	for &cursor in editor.cursors {		
		if has_selection(editor, &cursor) == false {
			goto(editor, &cursor, cursor.head - 1, true)
		} 
	}
	for &cursor in editor.cursors {		
		remove(editor, &cursor)
	}
}

select_line :: proc(editor: ^Editor, cursor: ^Cursor) {
	line := line_from_pos(editor, cursor.head)
	line_range := editor.buffer.line_ranges[line]
	line_range.end += 1
	if has_selection(editor, cursor) == false {
		goto(editor, cursor, line_range.start)
	}
	goto(editor, cursor, line_range.end, true)
}

copy :: proc(editor: ^Editor) {
	text := ""
	for &cursor in editor.cursors {
		if has_selection(editor, &cursor) {
			range := cursor_to_range(&cursor)
			selected_text := string(editor.buffer.content[range.start:range.end])
			text = strings.join({ text, selected_text }, "", context.temp_allocator)
		}
		else {
			line := line_from_pos(editor, cursor.head)
			range := editor.buffer.line_ranges[line]
			line_text := string(editor.buffer.content[range.start:range.end])
			text = strings.join({ text, line_text }, "", context.temp_allocator)
		}
	}
	rl.SetClipboardText(strings.clone_to_cstring(text, context.temp_allocator))
}

cut :: proc(editor: ^Editor) {
	text := ""
	for &cursor in editor.cursors {
		if has_selection(editor, &cursor) {
			range := cursor_to_range(&cursor)
			selected_text := string(editor.buffer.content[range.start:range.end])
			text = strings.join({ text, selected_text }, "", context.temp_allocator)
		}
		else {
			line := line_from_pos(editor, cursor.head)
			range := editor.buffer.line_ranges[line]
			select(editor, &cursor, range)
			line_text := string(editor.buffer.content[range.start:range.end])
			text = strings.join({ text, line_text }, "", context.temp_allocator)
		}
	}
	merge_cursors(editor)
	for &cursor in editor.cursors {
		remove(editor, &cursor)
	}
	rl.SetClipboardText(strings.clone_to_cstring(text, context.temp_allocator))
}

paste :: proc(editor: ^Editor) {
	for &cursor in editor.cursors {		
		remove(editor, &cursor)
		text := strings.clone_from_cstring(rl.GetClipboardText(), context.temp_allocator)
		insert(editor, &cursor, text)
	}
}

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
	
	current_line := line_from_pos(editor, editor.cursors[0].head)
	
	look_ahead_x := f32(80)
	look_ahead_y := f32(80)

	// calculate scroll_x
	cursor_x := f32(0)
	for i in buffer.line_ranges[current_line].start..<editor.cursors[0].head {
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

		// draw selections
		for &cursor in editor.cursors {			
			cursor_range := cursor_to_range(&cursor)
			if cursor_range.start <= char_index && char_index < cursor_range.end {
				rl.DrawRectangleRec({ char_x, char_y, char_w, 40 }, style.select_color)
			} 
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
	if editor.line_numbers {
		rl.DrawRectangleRec(lines_rect, style.bg_color)
		
		for i in first_line..=last_line {
			number_color := style.text_color2
			if i == line_from_pos(editor, editor.cursors[0].head) {
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
		for &cursor in editor.cursors {			
			line := line_from_pos(editor, cursor.head)
			cursor_x := code_rect.x + scroll_x^
			cursor_y := code_rect.y + f32(line) * 40 + scroll_y^
			for i in buffer.line_ranges[line].start..<cursor.head {
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
	}
	rl.EndScissorMode()
}

get_color_for_token :: proc(syntax: ^sy.Syntax, kind: tokenizer.Token_Kind) -> rl.Color {
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

// TODO: remove this shit
col_visual_to_real :: proc(editor: ^Editor, line: int, col_vis: int) -> int {
	line_range := editor.buffer.line_ranges[line]
	col := 0
	to_move := col_vis
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

// TODO: remove this shit
col_real_to_visual :: proc(editor: ^Editor, line: int, col_real: int) -> int {
	col := 0
	for i in editor.buffer.line_ranges[line].start..<col_real {
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
		
		cursor := Cursor {}
		if undo.kind == .Insert {
			select(editor, &cursor, undo.change_range)
			remove_raw(editor, &cursor)
		}
		else if undo.kind == .Delete {
			goto(editor, &cursor, undo.change_range.start)
			insert_raw(editor, &cursor, undo.text)
		}

		clear(&editor.cursors)
		append(&editor.cursors, ..undo.cursors_before[:])
		
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

		cursor := Cursor {}

		if undo.kind == .Insert {
			goto(editor, &cursor, undo.change_range.start)
			insert_raw(editor, &cursor, undo.text, false)
		}
		else if undo.kind == .Delete {
			select(editor, &cursor, undo.change_range)
			remove_raw(editor, &cursor)
		}

		clear(&editor.cursors)
		append(&editor.cursors, ..undo.cursors_after[:])

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

push_undo :: proc(
	editor: ^Editor, 
	kind: Undo_Kind, 
	range: rg.Range, 
	text: string,
	cursors_before: []Cursor,
	cursors_after: []Cursor,
) {
	for i := len(editor.undos) - 1; editor.undo_index <= i; i -= 1 {
		undo := pop(&editor.undos)
		undo_deinit(&undo)
	}
	
	undo := Undo {
		change_range = range,
		kind = kind,
		text = strings.clone(text),
		time = f32(rl.GetTime()),
		cursors_before = slice.clone(cursors_before),
		cursors_after = slice.clone(cursors_after),
	}
	append(&editor.undos, undo)

	editor.undo_index += 1
}

undo_deinit :: proc(undo: ^Undo) {
	delete(undo.text)
	delete(undo.cursors_before)
	delete(undo.cursors_after)
}

set_style :: proc(editor: ^Editor, style: Style) {
	editor.style = style
}

// TODO: rewrite this again
merge_cursors :: proc(editor: ^Editor) {
	to_remove := make([dynamic]int, context.temp_allocator)
	for &cursor, i in editor.cursors {
		for &other, j in editor.cursors {
			if i != j {
				cursor_range := cursor_to_range(&cursor)
				other_range := cursor_to_range(&other)
				if cursor_range.start <= other.head && other.head <= cursor_range.end {
					if slice.contains(to_remove[:], j) == false && slice.contains(to_remove[:], i) == false {
						cursor.anchor = other.anchor
						append(&to_remove, j)
					}
				}
			}
		}
	}

	#reverse for i in to_remove {
		if len(editor.cursors) == 1 {
			break
		}
		ordered_remove(&editor.cursors, i)
	}
}