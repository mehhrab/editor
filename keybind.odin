package main

import "core:fmt"
import "range"
import buf "buffer"
import "path"
import ed "editor"
import fi "find"
import co "commands"
import fp "file_picker"
import li "list"
import km "keymap"

Bindings :: struct {
	go_left: km.Keybind,
	go_right: km.Keybind,
	go_up: km.Keybind,
	go_down: km.Keybind,
	
	go_left_select: km.Keybind,
	go_right_select: km.Keybind,
	go_up_select: km.Keybind,
	go_down_select: km.Keybind,
	
	undo: km.Keybind,
	redo: km.Keybind,

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

	// select_line: km.Keybind,
}

bindings_default :: proc() -> Bindings {
	return {
		go_left = km.keybind_init(.LEFT),
		go_right = km.keybind_init(.RIGHT),
		go_up = km.keybind_init(.UP),
		go_down = km.keybind_init(.DOWN),

		go_left_select = km.keybind_init(.LEFT, shift = true),
		go_right_select = km.keybind_init(.RIGHT, shift = true),
		go_up_select = km.keybind_init(.UP, shift = true),
		go_down_select = km.keybind_init(.DOWN, shift = true),

		undo = km.keybind_init(.Z, control = true),
		redo = km.keybind_init(.Z, shift = true, control = true),

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
	}
}

input :: proc(app: ^App) {
	if km.check(&app.bindings.find_show) {
		find_show(app)
	}
	else if km.check(&app.bindings.commands_show) {
		commands_show(app)
	}
	else if km.check(&app.bindings.file_picker_show) {
		file_picker_show(app)
	}
	else if km.check(&app.bindings.next_tab) {
		focus_editor(app, (app.editor_index + 1) % len(app.editors)) 
	}
	else if km.check(&app.bindings.new_file) {
		new_file(app)
	}
	else if km.check(&app.bindings.save_file) {
		// TODO: uncomment this when theres an option for line endings
		// save_file(app, app.editor_index)
	}
	else if km.check(&app.bindings.close_current_editor) {
		if 1 < len(app.editors) {			
			ed.deinit(&app.editors[app.editor_index])
			ordered_remove(&app.editors, app.editor_index)
			focus_editor(app, len(app.editors) - 1)
		}
	}
	else if km.check(&app.bindings.close_popup) {
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
editor_input :: proc(app: ^App, editor: ^ed.Editor) {
	if km.check(&app.bindings.go_up) {
		ed.go_up(editor, false)
	}
	else if km.check(&app.bindings.go_down) {
		ed.go_down(editor, false)
	}
	else if km.check(&app.bindings.go_left) {
		ed.go_left(editor, false)
	}
	else if km.check(&app.bindings.go_right) {
		ed.go_right(editor, false)
	}
	else if km.check(&app.bindings.go_up_select) {
		ed.go_up(editor, true)
	}
	else if km.check(&app.bindings.go_down_select) {
		ed.go_down(editor, true)
	}
	else if km.check(&app.bindings.go_left_select) {
		ed.go_left(editor, true)
	}
	else if km.check(&app.bindings.go_right_select) {
		ed.go_right(editor, true)
	}
	else if km.key_pressed(.BACKSPACE) {
		ed.back_space(editor)
	}
	else if km.key_pressed(.ENTER) {
		ed.replace(editor, "\n")
	}
	else if km.key_pressed(.TAB) {
		// TODO: add option to use spaces
		ed.replace(editor, "\t")
	}
	else if km.check(&app.bindings.undo) {
		ed.undo(editor)
	}
	else if km.check(&app.bindings.redo) {
		ed.redo(editor)
	}
	else if len(app.chars_pressed) != 0 {
		for char in app.chars_pressed {
			ed.replace(editor, fmt.tprint(char))
		}
	}
}

find_input :: proc(app: ^App) {
	if km.check(&app.bindings.find_confirm) {
		fi.hide(&app.find)
	}
	else if km.check(&app.bindings.find_next) {
		find_next(app)
	}
	else {
		editor_input(app, &app.find.input)
		if len(&app.chars_pressed) != 0 {
			fi.calc_matches(&app.find)
			_, match_range := fi.next(&app.find)
			ed.select(editor(app), match_range)
		}
	}
}

file_picker_input :: proc(app: ^App) {
	if km.check(&app.bindings.go_up) {
		fp.go_up(&app.file_picker)
	}
	else if km.check(&app.bindings.go_down) {
		fp.go_down(&app.file_picker)
	}
	else if km.check(&app.bindings.confirm) {
		if file_path, ok := fp.select(&app.file_picker).?; ok {
			index := open_file(app, file_path)
			focus_editor(app, index)
			file_picker_hide(app)
		}
	}
}

commands_input :: proc(app: ^App) {
	if km.check(&app.bindings.go_up) {
		co.go_up(&app.commands)
	}
	else if km.check(&app.bindings.go_down) {
		co.go_down(&app.commands)
	}
	else if km.check(&app.bindings.confirm) {
		commands_hide(app)
	}
	else {
		// TODO: broken
		editor_input(app, &app.commands.input)
		if len(&app.chars_pressed) != 0 {
			co.refresh(&app.commands)
		}
	}
}
