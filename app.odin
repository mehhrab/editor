package main

import rl "vendor:raylib"
import fmt "core:fmt"
import "core:strings"
import "core:mem"
import "core:slice"
import os "core:os/os2"
import "range"
import buf "buffer"
import "path"
import ed "editor"
import fi "find"
import co "commands"
import fp "file_picker"
import li "list"

Range :: range.Range

App :: struct {
	theme: Theme,
	style: Style,
	font: rl.Font,
	font_size: f32,
	
	editors: [dynamic]ed.Editor,
	editor_index: int,
	
	find: fi.Find,
	// might move these outta here idk
	cursor_before_search: ed.Cursor,
	scroll_x_before_search: f32,
	scroll_y_before_search: f32,
	
	file_picker: fp.File_Picker,
	commands: co.Commands, 
	
	chars_pressed: [dynamic]rune,
}

Style :: struct {
	editor: ed.Style,
	find: fi.Style,
	commands: co.Style,
	file_picker: fp.Style,
	list: li.Style,
}

app_main :: proc() {
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	rl.SetConfigFlags({.WINDOW_RESIZABLE})
	rl.InitWindow(1200, 700, "Editor")
	defer rl.CloseWindow()
	rl.SetTargetFPS(30)
	rl.SetExitKey(nil)

	current_dir, err := os.get_executable_directory(context.allocator)
	assert(err == nil)
	defer delete(current_dir)

	app := App {}
	app.theme = THEME_DEFAULT
	app.font_size = 40
	app.font = rl.LoadFontEx("FiraCode-Regular.ttf", i32(app.font_size * 2), nil, 0)
	app.style = style_from_theme(&app.theme, app.font, app.font_size)
	defer delete(app.chars_pressed)

	defer {
		for &editor in app.editors {
			ed.deinit(&editor)
		}
		delete(app.editors)
	}

	open_file(&app, path.join({ current_dir, "app.odin" }, context.temp_allocator))

	fi.init(&app.find, &app.style.find)
	defer fi.deinit(&app.find)

	fp.init(&app.file_picker, &app.style.file_picker, current_dir)
	defer fp.deinit(&app.file_picker)

	co.init(&app.commands, &app.style.commands, { 
		"New File",
		"Open File",
		"Start Search",
		"Close File",
	})
	defer co.deinit(&app.commands)

	for rl.WindowShouldClose() == false {
		char := rl.GetCharPressed();
		for char != 0 {
			append(&app.chars_pressed, char)
			char = rl.GetCharPressed();
		}

		screen_rect := rl.Rectangle { 0, 0, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight()) }
		code_editor(&app).rect = { 0, 41, screen_rect.width, screen_rect.height - 40 }
		app.find.input.rect = { 0, screen_rect.height - 40, screen_rect.width, 40 }
		
		file_picker_rect := rl.Rectangle { 0, 0, 700, 400 }
		file_picker_rect.x = screen_rect.width / 2 - file_picker_rect.width / 2
		file_picker_rect.y = screen_rect.height / 2 - file_picker_rect.height / 2
		fp.set_rect(&app.file_picker, file_picker_rect)

		co.set_rect(&app.commands, { screen_rect.width / 2 - 600 / 2, 50, 600, 300 })

		input(&app)

		if app.find.visible {
			if check_key(.ENTER, .Control) {
				fi.hide(&app.find)
			}
			else if check_key(.ENTER) {
				find_next(&app)
			}
			else {
				editor_input(&app, &app.find.input)
				if len(&app.chars_pressed) != 0 {
					fi.calc_matches(&app.find)
					_, match_range := fi.next(&app.find)
					ed.select(editor(&app), match_range)
				}
			}
		}
		else if app.file_picker.visible {
			if check_key(.UP, type = .Press_Repeat) {
				fp.go_up(&app.file_picker)
			}
			else if check_key(.DOWN, type = .Press_Repeat) {
				fp.go_down(&app.file_picker)
			}
			else if check_key(.ESCAPE) {
				commands_hide(&app)
			}
			else if check_key(.ENTER) {
				if file_path, ok := fp.select(&app.file_picker).?; ok {
					open_file(&app, file_path)
					file_picker_hide(&app)
				}
			}
		}
		else if app.commands.visible {
			if check_key(.UP, type = .Press_Repeat) {
				co.go_up(&app.commands)
			}
			else if check_key(.DOWN, type = .Press_Repeat) {
				co.go_down(&app.commands)
			}
			else if check_key(.ESCAPE) {
				commands_hide(&app)
			}
			else if check_key(.ENTER) {
				commands_hide(&app)
			}
		}
		else {
			editor_input(&app, code_editor(&app))
		}

		rl.BeginDrawing()
		rl.ClearBackground(app.theme.bg2)
		
		for editor, i in app.editors {
			tab_w := screen_rect.width / f32(len(app.editors))
			tab_rect := rl.Rectangle { f32(i) * tab_w, 0, tab_w, 40 }
			rl.DrawRectangleRec(tab_rect, i == app.editor_index ? app.theme.bg : app.theme.bg2)
			if len(app.editors) != 0 && i == app.editor_index {
				if i != 0 {
					rl.DrawTriangle(
						{ tab_rect.x, tab_rect.y + tab_rect.height },
						{ tab_rect.x + 40, tab_rect.y },
						{ tab_rect.x, tab_rect.y }, 
						app.theme.bg2)
				}
				if i != len(app.editors) - 1 {					
					rl.DrawTriangle(
						{ tab_rect.x + tab_rect.width, tab_rect.y }, 
						{ tab_rect.x + tab_rect.width - 40, tab_rect.y },
						{ tab_rect.x + tab_rect.width, tab_rect.y + tab_rect.height },
						app.theme.bg2)
				}
			}
			rl.BeginScissorMode(i32(tab_rect.x + 40), i32(tab_rect.y), i32(tab_rect.width - 40 * 2), i32(tab_rect.height))
			name_cstring := strings.clone_to_cstring(editor.name, context.temp_allocator)			
			text_w := rl.MeasureTextEx(app.font, name_cstring, 40, 0)[0]
			text_pos := rl.Vector2 { tab_rect.x + tab_rect.width / 2 - text_w / 2, tab_rect.y }
			rl.DrawTextEx(app.font, name_cstring, text_pos, 40, 0, i == app.editor_index ? app.theme.text : app.theme.text2)
			rl.EndScissorMode()
		}
		
		ed.draw(code_editor(&app))
		
		if app.commands.visible {
			co.draw(&app.commands)
		}

		if app.find.visible {
			fi.draw(&app.find)
		}
		
		if app.file_picker.visible {
			fp.draw(&app.file_picker)
		}

		rl.EndDrawing()

		clear(&app.chars_pressed)
		free_all(context.temp_allocator)
	}
}

input :: proc(app: ^App) -> bool {
	handled := false
	if check_key(.F, .Control) {
		find_show(app)
		handled = true
	}
	else if check_key(.P, .Control) {
		commands_show(app)
		handled = true
	}
	else if check_key(.E, .Control) {
		file_picker_show(app)
		handled = true
	}
	else if check_key(.TAB, .Control) {
		focus_editor(app, (app.editor_index + 1) % len(app.editors)) 
		handled = true
	}
	else if check_key(.N, .Control) {
		new_file(app)
		handled = true
	}
	else if check_key(.P, .Control) {
		save_file(app, app.editor_index)
		handled = true
	}
	else if check_key(.W, .Control) {
		if 1 < len(app.editors) {			
			ed.deinit(&app.editors[app.editor_index])
			ordered_remove(&app.editors, app.editor_index)
			focus_editor(app, len(app.editors) - 1)
		}
		handled = true
	}
	else if check_key(.ESCAPE) {
		if app.find.visible {
			find_cancel(app)
			handled = true
		}
		else if app.file_picker.visible {
			file_picker_hide(app)
			handled = true
		}
		else if app.commands.visible {
			commands_hide(app)
			handled = true
		}
	}

	return handled
}

editor_input :: proc(app: ^App, editor: ^ed.Editor) {
	if check_key(.UP, type = .Press_Repeat) {
		ed.go_up(editor, false)
	}
	else if check_key(.DOWN, type = .Press_Repeat) {
		ed.go_down(editor, false)
	}
	else if check_key(.LEFT, type = .Press_Repeat) {
		ed.go_left(editor, false)
	}
	else if check_key(.RIGHT, type = .Press_Repeat) {
		ed.go_right(editor, false)
	}
	else if check_key(.UP, .Shift, type = .Press_Repeat) {
		ed.go_up(editor, true)
	}
	else if check_key(.DOWN, .Shift, type = .Press_Repeat) {
		ed.go_down(editor, true)
	}
	else if check_key(.LEFT, .Shift, type = .Press_Repeat) {
		ed.go_left(editor, true)
	}
	else if check_key(.RIGHT, .Shift, type = .Press_Repeat) {
		ed.go_right(editor, true)
	}
	else if check_key(.BACKSPACE, type = .Press_Repeat) {
		ed.back_space(editor)
	}
	else if check_key(.ENTER, type = .Press_Repeat) {
		ed.replace(editor, "\n")
	}
	else if check_key(.TAB, type = .Press_Repeat) {
		// TODO: add option to use spaces
		ed.replace(editor, "\t")
	}
	else if check_key(.Z, .Control, type = .Press_Repeat) {
		ed.undo(editor)
	}
	else if check_key(.Y, .Control, type = .Press_Repeat) {
		ed.redo(editor)
	}
	else if len(app.chars_pressed) != 0 {
		for char in app.chars_pressed {
			ed.replace(editor, fmt.tprint(char))
		}
	}
}

new_file :: proc(app: ^App, content := "") -> int {
	append(&app.editors, ed.Editor {})
	index := len(app.editors) - 1
	editor := &app.editors[index]

	buffer: buf.Buffer; buf.init(&buffer, content)
	ed.init(editor, &app.style.editor, &buffer, "", "*untitled*")
	editor.highlight = true
	editor.line_numbers = true

	focus_editor(app, index)
	
	return index
}

open_file :: proc(app: ^App, file_path: string) -> int {
	for editor, i in app.editors {
		if editor.path == file_path {
			return i
		}
	}

	file_name := path.shorten(file_path)
	text, err := os.read_entire_file(file_path, context.temp_allocator)
	assert(err == nil)

	append(&app.editors, ed.Editor {})
	index := len(app.editors) - 1
	editor := &app.editors[index]

	buffer: buf.Buffer; buf.init(&buffer, string(text))
	ed.init(editor, &app.style.editor, &buffer, file_path, file_name)
	
	ed.set_style(editor, app.style.editor)
	editor.syntax = app.theme.syntax
	editor.highlight = true
	editor.line_numbers = true

	focus_editor(app, index)
	
	return index
}

save_file :: proc(app: ^App, index: int) {
	editor := &app.editors[index]
	// TODO: add an config option to use clrf or not
	text := buf.content_with_clrf(&editor.buffer, context.temp_allocator)
	write_err := os.write_entire_file(editor.path, text)
	assert(write_err == nil)
}

focus_editor :: proc(app: ^App, index: int) {
	app.editor_index = index
	if app.find.visible {
		find_show(app)
	}
}

find_show :: proc(app: ^App) {
	if app.commands.visible {
		commands_hide(app)
	}
	
	editor := editor(app)
	
	fi.set_text(&app.find, string(editor.buffer.content[:]))
	fi.show(&app.find, ed.selected_text(editor))
	
	clear(&editor.highlighted_ranges)
	append(&editor.highlighted_ranges, ..fi.calc_matches(&app.find))

	app.cursor_before_search = editor.cursor
	app.scroll_x_before_search = editor.scroll_x
	app.scroll_y_before_search = editor.scroll_y
}

find_hide :: proc(app: ^App) {
	clear(&editor(app).highlighted_ranges)
	fi.hide(&app.find)
}

find_cancel :: proc(app: ^App) {
	editor := editor(app)

	editor.cursor = app.cursor_before_search 
	editor.scroll_x = app.scroll_x_before_search 
	editor.scroll_y = app.scroll_y_before_search 

	find_hide(app)
}

find_next :: proc(app: ^App) {
	_, match := fi.next(&app.find)
	ed.select(editor(app), match)
	ed.scroll_center_v(editor(app), match.start)
}

file_picker_show :: proc(app: ^App) {
	if app.find.visible {
		find_cancel(app)
	}
	if app.commands.visible {
		commands_hide(app)
	}
	fp.show(&app.file_picker)
}

file_picker_hide :: proc(app: ^App) {
	fp.hide(&app.file_picker)
}

commands_show :: proc(app: ^App) {
	if app.find.visible {
		find_cancel(app)
	}
	if app.file_picker.visible {
		commands_hide(app)
	}
	co.show(&app.commands)
}

commands_hide :: proc(app: ^App) {
	co.hide(&app.commands)
}

code_editor :: proc(app: ^App) -> ^ed.Editor {
	return &app.editors[app.editor_index]
}

editor :: proc(app: ^App) -> ^ed.Editor {
	current_editor: ^ed.Editor = nil
	if app.file_picker.visible {
		current_editor = &app.file_picker.list.content
	}
	else {
		current_editor = code_editor(app)
	}
	return current_editor	
}

Mod_Key :: enum {
	Control,
	Shift,
	Alt,
}

Press_Kind :: enum {
	Press,
	Hold,
	Repeat,
	Press_Repeat
}

// TODO: rewrite this guy to be simpler
check_key :: proc(key: rl.KeyboardKey, mods: ..Mod_Key, type := Press_Kind.Press) -> bool {
	shift_down := rl.IsKeyDown(.LEFT_SHIFT)
	alt_down := rl.IsKeyDown(.LEFT_ALT)
	control_down := rl.IsKeyDown(.LEFT_CONTROL)
	
	shift_wanted := false
	alt_wanted := false
	control_wanted := false
	
	for mod in mods {
		switch mod {
			case .Alt: alt_wanted = true 
			case .Shift: shift_wanted = true 
			case .Control: control_wanted = true 
		}
	}

	key_pressed := false
	switch type {
		case .Press: key_pressed = rl.IsKeyPressed(key)
		case .Hold: key_pressed = rl.IsKeyDown(key)
		case .Repeat: key_pressed = rl.IsKeyPressedRepeat(key)
		case .Press_Repeat: key_pressed = rl.IsKeyPressed(key) || rl.IsKeyPressedRepeat(key)
	}

	return key_pressed &&
	shift_down == shift_wanted &&
	alt_down == alt_wanted &&
	control_down == control_wanted
}

style_from_theme :: proc(theme: ^Theme, font: rl.Font, font_size: f32) -> Style {
	style := Style {}
	style.editor = ed.Style {
		bg_color = theme.bg,
		caret_color = theme.caret,
		font = font,
		font_size = font_size,
		highlight_color = rl.ColorAlpha(theme.selection, 0.5),
		select_color = theme.selection,
		text_color = theme.text,
		text_color2 = theme.text2,
	}
	style.list = li.Style {
		content = style.editor
	}
	style.commands = co.Style {
		outline_color = theme.seperator,
		input = style.editor,
		list = style.list,
	}
	style.file_picker = fp.Style {
		outline_color = theme.seperator,
		list = style.list,
	}
	style.find = fi.Style {
		active_outline_color = theme.accent,
		input = style.editor,
	}
	return style
}