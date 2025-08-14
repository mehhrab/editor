package app

import "core:fmt"
import "../path"
import buf "../buffer"
import ed "../editor"
import fi "../find"
import co "../commands"
import fp "../file_picker"
import li "../list"
import km "../keymap"

Keybinds :: struct {
	go_left: km.Keybind,
	go_right: km.Keybind,
	go_up: km.Keybind,
	go_down: km.Keybind,
	
	go_left_select: km.Keybind,
	go_right_select: km.Keybind,
	go_up_select: km.Keybind,
	go_down_select: km.Keybind,

	select_line: km.Keybind,
	
	undo: km.Keybind,
	redo: km.Keybind,
	copy: km.Keybind,
	cut: km.Keybind,
	paste: km.Keybind,

	find_show: km.Keybind,
	find_confirm: km.Keybind,
	find_next: km.Keybind,

	commands_show: km.Keybind,
	file_picker_show: km.Keybind,
	close_popup: km.Keybind,

	next_tab: km.Keybind,
	new_file: km.Keybind,
	save_file: km.Keybind,
	close_current_editor: km.Keybind,
	confirm: km.Keybind,

	add_cursor_above: km.Keybind,
	add_cursor_below: km.Keybind,
	remove_extra_cursors: km.Keybind,
}

keybinds_default :: proc() -> Keybinds {
	return {
		go_left = km.keybind_init(.LEFT),
		go_right = km.keybind_init(.RIGHT),
		go_up = km.keybind_init(.UP),
		go_down = km.keybind_init(.DOWN),

		go_left_select = km.keybind_init(.LEFT, shift = true),
		go_right_select = km.keybind_init(.RIGHT, shift = true),
		go_up_select = km.keybind_init(.UP, shift = true),
		go_down_select = km.keybind_init(.DOWN, shift = true),

		select_line = km.keybind_init(.L, control = true),

		undo = km.keybind_init(.Z, control = true),
		redo = km.keybind_init(.Z, shift = true, control = true),
		copy = km.keybind_init(.C, control = true),
		cut = km.keybind_init(.X, control = true),
		paste = km.keybind_init(.V, control = true),

		find_show = km.keybind_init(.F, control = true),
		find_confirm = km.keybind_init(.ENTER, control = true),
		find_next = km.keybind_init(.ENTER),
		
		commands_show = km.keybind_init(.P, shift = true, control = true),
		file_picker_show = km.keybind_init(.E, control = true),
		close_popup = km.keybind_init(.ESCAPE),

		next_tab = km.keybind_init(.TAB, control = true),
		new_file = km.keybind_init(.N, control = true),
		save_file = km.keybind_init(.S, control = true),
		close_current_editor = km.keybind_init(.W, control = true),
		confirm = km.keybind_init(.ENTER),

		add_cursor_above = km.keybind_init(.UP, alt = true, control = true),
		add_cursor_below = km.keybind_init(.DOWN, alt = true, control = true),
		remove_extra_cursors = km.keybind_init(.ESCAPE),
	}
}

input :: proc(app: ^App) {
	if km.check(&app.keybinds.find_show) {
		find_show(app)
	}
	else if km.check(&app.keybinds.commands_show) {
		commands_show(app)
	}
	else if km.check(&app.keybinds.file_picker_show) {
		file_picker_show(app)
	}
	else if km.check(&app.keybinds.next_tab) {
		if len(app.editors) != 0 {
			focus_editor(app, (app.editor_index + 1) % len(app.editors)) 
		}
	}
	else if km.check(&app.keybinds.new_file) {
		index := new_file(app)
		focus_editor(app, index)
	}
	else if km.check(&app.keybinds.save_file) {
		// TODO: uncomment this when theres an option for line endings
		// save_file(app, app.editor_index)
	}
	else if km.check(&app.keybinds.close_current_editor) {
		if 1 <= len(app.editors) {
			ed.deinit(&app.editors[app.editor_index])
			ordered_remove(&app.editors, app.editor_index)
			focus_editor(app, len(app.editors) - 1)
		}
	}
	else if km.check(&app.keybinds.close_popup) {
		if app.find.visible {
			find_cancel(app)
		}
		else if app.file_picker.visible {
			file_picker_hide(app)
		}
		else if app.commands.visible {
			commands_hide(app)
		}
	}
}

// NOTE: this is used for diffrent kind of editors, it shouldnt change anything outside of it
editor_input :: proc(app: ^App, editor: ^ed.Editor) -> bool {
	content_changed := false

	if km.check(&app.keybinds.go_up) {
		for &cursor in editor.cursors {
			ed.go_up(editor, &cursor, false)
		}
		ed.merge_cursors(editor)
	}
	else if km.check(&app.keybinds.go_down) {
		for &cursor in editor.cursors {
			ed.go_down(editor, &cursor, false)
		}
		ed.merge_cursors(editor)
	}
	else if km.check(&app.keybinds.go_left) {
		for &cursor in editor.cursors {
			ed.go_left(editor, &cursor, false)
		}
		ed.merge_cursors(editor)
	}
	else if km.check(&app.keybinds.go_right) {
		for &cursor in editor.cursors {
			ed.go_right(editor, &cursor, false)
		}
		ed.merge_cursors(editor)
	}
	else if km.check(&app.keybinds.go_up_select) {
		for &cursor in editor.cursors {
			ed.go_up(editor, &cursor, true)
		}
		ed.merge_cursors(editor)
	}
	else if km.check(&app.keybinds.go_down_select) {
		for &cursor in editor.cursors {
			ed.go_down(editor, &cursor, true)
		}
		ed.merge_cursors(editor)
	}
	else if km.check(&app.keybinds.go_left_select) {
		for &cursor in editor.cursors {
			ed.go_left(editor, &cursor, true)
		}
		ed.merge_cursors(editor)
	}
	else if km.check(&app.keybinds.go_right_select) {
		for &cursor in editor.cursors {
			ed.go_right(editor, &cursor, true)
		}
		ed.merge_cursors(editor)
	}
	else if key_pressed(.BACKSPACE) {
		ed.back_space(editor)
		content_changed = true
	}
	else if key_pressed(.ENTER) {
		for &cursor in editor.cursors {
			ed.insert(editor, &cursor, "\n")
		}
		content_changed = true
	}
	else if key_pressed(.TAB) {
		// TODO: add option to use spaces
		for &cursor in editor.cursors {
			ed.insert(editor, &cursor, "\t")
		}
		content_changed = true
	}
	else if km.check(&app.keybinds.select_line) {
		for &cursor in editor.cursors {
			ed.select_line(editor, &cursor)
		}
		ed.merge_cursors(editor)
	}
	else if km.check(&app.keybinds.undo) {
		ed.undo(editor)
		content_changed = true
	}
	else if km.check(&app.keybinds.redo) {
		ed.redo(editor)
		content_changed = true
	}
	else if km.check(&app.keybinds.copy) {
		ed.copy(editor)
	}
	else if km.check(&app.keybinds.cut) {
		ed.cut(editor)
	}
	else if km.check(&app.keybinds.paste) {
		ed.paste(editor)
	}
	else if km.check(&app.keybinds.add_cursor_above) {
		abovest_line := ed.line_from_pos(editor, editor.cursors[0].head)
		for &cursor in editor.cursors {
			line := ed.line_from_pos(editor, cursor.head)
			if line <= abovest_line {
				abovest_line = line
			}
		}
		abovest_line -= 1
		if 0 <= abovest_line {
			dest := editor.buffer.line_ranges[abovest_line].start
			dest += ed.col_visual_to_real(editor, abovest_line, editor.cursors[0].last_col)
			dest = ed.clamp_in_line(editor, dest, abovest_line)
			ed.add_cursor(editor, dest, dest)
		}
	}
	else if km.check(&app.keybinds.add_cursor_below) {
		belowest_line := 0
		for &cursor in editor.cursors {
			line := ed.line_from_pos(editor, cursor.head)
			if belowest_line <= line {
				belowest_line = line
			}
		}
		belowest_line += 1
		if belowest_line <= len(editor.buffer.line_ranges) - 1 {			
			dest := editor.buffer.line_ranges[belowest_line].start
			dest += ed.col_visual_to_real(editor, belowest_line, editor.cursors[0].last_col)
			dest = ed.clamp_in_line(editor, dest, belowest_line)
			ed.add_cursor(editor, dest, dest)
		}
	}
	else if km.check(&app.keybinds.remove_extra_cursors) {
		ed.remove_extra_cursors(editor)
	}
	else if len(app.chars_pressed) != 0 {
		for char in app.chars_pressed {
			for &cursor in editor.cursors {
				ed.insert(editor, &cursor, fmt.tprint(char))
			}
		}
		content_changed = true
	}

	return content_changed
}

find_input :: proc(app: ^App) {
	if km.check(&app.keybinds.find_confirm) {
		fi.hide(&app.find)
	}
	else if km.check(&app.keybinds.find_next) {
		find_next(app)
	}
	else {
		content_changed := editor_input(app, &app.find.input)
		if content_changed {
			fi.calc_matches(&app.find)
			_, match_range := fi.next(&app.find)
			ed.remove_extra_cursors(editor(app))
			ed.select(editor(app), &editor(app).cursors[0], match_range)
		}
	}
}

file_picker_input :: proc(app: ^App) {
	if km.check(&app.keybinds.go_up) {
		fp.go_up(&app.file_picker)
	}
	else if km.check(&app.keybinds.go_down) {
		fp.go_down(&app.file_picker)
	}
	else if km.check(&app.keybinds.confirm) {
		if file_path, ok := fp.select(&app.file_picker).?; ok {
			index := open_file(app, file_path)
			focus_editor(app, index)
			file_picker_hide(app)
		}
	}
}

commands_input :: proc(app: ^App) {
	if km.check(&app.keybinds.go_up) {
		co.go_up(&app.commands)
	}
	else if km.check(&app.keybinds.go_down) {
		co.go_down(&app.commands)
	}
	else if km.check(&app.keybinds.confirm) {
		commands_hide(app)
	}
	else {
		content_changed := editor_input(app, &app.commands.input)
		if content_changed {
			co.refresh(&app.commands)
		}
	}
}
