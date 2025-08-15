package app

import "core:fmt"
import "core:strings"
import "core:mem"
import "core:slice"
import os "core:os/os2"
import rl "vendor:raylib"
import rg "../range"
import buf "../buffer"
import "../path"
import ed "../editor"
import fi "../find"
import co "../commands"
import fp "../file_picker"
import li "../list"
import km "../keymap"
import sy "../syntax"
import rec "../rectangle"

App :: struct {
	current_dir: string,

	style: Style,
	syntax: sy.Syntax,
	font: rl.Font,
	font_path: string,
	font_size: f32,
	keybinds: Keybinds,
	
	editors: [dynamic]ed.Editor,
	editor_index: int,
	
	find: fi.Find,
	// might move these outta here idk
	cursors_before_search: []ed.Cursor,
	scroll_x_before_search: f32,
	scroll_y_before_search: f32,
	
	file_picker: fp.File_Picker,
	commands: co.Commands, 
	
	tabs_rect: rl.Rectangle,
	chars_pressed: [dynamic]rune,
}

Config :: struct {
	syntax: sy.Syntax,
	theme: Theme,
	keybinds: Keybinds,
	// TODO: use font name instead
	font_path: string,
	font_size: f32,
}

Style :: struct {
	bg_color: rl.Color,
	text_color: rl.Color,
	text_color2: rl.Color,
	tab_color: rl.Color,

	editor: ed.Style,
	find: fi.Style,
	commands: co.Style,
	file_picker: fp.Style,
	list: li.Style,
}

init :: proc(app: ^App, config: ^Config) {
	rl.SetConfigFlags({.WINDOW_RESIZABLE})
	rl.InitWindow(1200, 700, "Editor")
	rl.SetTargetFPS(30)
	rl.SetExitKey(nil)

	current_dir, err := os.get_executable_directory(context.allocator)
	assert(err == nil)
	app.current_dir = current_dir

	load_config(app, config)

	fi.init(&app.find, &app.style.find)
	fp.init(&app.file_picker, &app.style.file_picker, app.current_dir)
	co.init(&app.commands, &app.style.commands, { 
		"New File",
		"Open File",
		"Start Search",
		"Close File",
	})
}

deinit :: proc(app: ^App) {
	co.deinit(&app.commands)
	fp.deinit(&app.file_picker)
	fi.deinit(&app.find)

	for &editor in app.editors {
		ed.deinit(&editor)
	}
	delete(app.editors)

	delete(app.chars_pressed)
	delete(app.cursors_before_search)
	delete(app.current_dir)
	delete(app.font_path)
	rl.UnloadFont(app.font)
	rl.CloseWindow()
}

run :: proc(app: ^App) {
	for rl.WindowShouldClose() == false {
		char := rl.GetCharPressed();
		for char != 0 {
			append(&app.chars_pressed, char)
			char = rl.GetCharPressed();
		}

		layout(app)
		input(app)

		if app.find.visible {
			find_input(app)
		}
		else if app.file_picker.visible {
			file_picker_input(app)
		}
		else if app.commands.visible {
			commands_input(app)
		}
		else if len(app.editors) != 0 {
			editor_input(app, code_editor(app))
		}

		rl.BeginDrawing()
		rl.ClearBackground(app.style.bg_color)
		
		if len(app.editors) != 0 {
			draw_tabs(app, app.tabs_rect)
			ed.draw(code_editor(app))
		}
		else {
			rl.DrawTextEx(
				app.font, 
				"no buffer is open\nuse CTRL + E to open file picker", 
				{ 10, 10 }, 
				app.font_size, 
				0, 
				app.style.text_color2)
		}
		
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

new_file :: proc(app: ^App, content := "") -> int {
	append(&app.editors, ed.Editor {})
	index := len(app.editors) - 1
	editor := &app.editors[index]

	buffer: buf.Buffer; buf.init(&buffer, content)
	ed.init(editor, &app.style.editor, &buffer, "", "*untitled*")
	ed.set_font(editor, app.font, app.font_size)
	editor.highlight = true
	editor.line_numbers = true
	
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
	
	ed.set_font(editor, app.font, app.font_size)
	editor.syntax = app.syntax
	editor.highlight = true
	editor.line_numbers = true

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
	
	if any_editor_open(app) {
		editor := editor(app)
		
		app.cursors_before_search = slice.clone(editor.cursors[:])
		app.scroll_x_before_search = editor.scroll_x
		app.scroll_y_before_search = editor.scroll_y

		fi.set_text(&app.find, string(editor.buffer.content[:]))
		fi.show(&app.find, ed.selected_text(editor, &editor.cursors[0]))
		
		clear(&editor.highlighted_ranges)
		append(&editor.highlighted_ranges, ..fi.calc_matches(&app.find))
	}
}

find_hide :: proc(app: ^App) {
	clear(&editor(app).highlighted_ranges)
	fi.hide(&app.find)
}

find_cancel :: proc(app: ^App) {
	editor := editor(app)

	clear(&editor.cursors)
	append(&editor.cursors, ..app.cursors_before_search) 
	editor.scroll_x = app.scroll_x_before_search 
	editor.scroll_y = app.scroll_y_before_search 

	find_hide(app)
}

find_next :: proc(app: ^App) {
	editor := editor(app)
	ed.remove_extra_cursors(editor)
	_, match := fi.next(&app.find)
	ed.select(editor, &editor.cursors[0], match)
	ed.scroll_center_v(editor, match.start)
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

load_config :: proc(app: ^App, config: ^Config) {
	app.font_path = strings.clone(config.font_path)
	app.font_size = config.font_size
	app.font = load_font(app.font_path, app.font_size)	
	set_font(app, app.font, app.font_size)

	app.syntax = config.syntax
	app.style = style_from_theme(&config.theme)
	app.keybinds = config.keybinds
}

style_from_theme :: proc(theme: ^Theme) -> Style {
	style := Style {
		bg_color = theme.bg2,
		tab_color = theme.bg,
		text_color = theme.text,
		text_color2 = theme.text2,
	}
	style.editor = ed.Style {
		bg_color = theme.bg,
		caret_color = theme.caret,
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

key_pressed :: proc(key: rl.KeyboardKey) -> bool {
	return (rl.IsKeyPressed(key) || rl.IsKeyPressedRepeat(key)) &&
	rl.IsKeyDown(.LEFT_SHIFT) == false &&
	rl.IsKeyDown(.LEFT_ALT) == false &&
	rl.IsKeyDown(.LEFT_CONTROL) == false
}

draw_tabs :: proc(app: ^App, rect: rl.Rectangle) {
	for editor, i in app.editors {
		tab_w := rect.width / f32(len(app.editors))
		tab_rect := rl.Rectangle { rect.x + f32(i) * tab_w, rect.y, tab_w, rect.height }
		tab_color := i == app.editor_index ? app.style.tab_color : app.style.bg_color
		rl.DrawRectangleRec(tab_rect, tab_color)
		if len(app.editors) != 0 && i == app.editor_index {
			if i != 0 {
				rl.DrawTriangle(
					{ tab_rect.x, tab_rect.y + tab_rect.height },
					{ tab_rect.x + app.font_size, tab_rect.y },
					{ tab_rect.x, tab_rect.y }, 
					app.style.bg_color)
			}
			if i != len(app.editors) - 1 {
				rl.DrawTriangle(
					{ tab_rect.x + tab_rect.width, tab_rect.y }, 
					{ tab_rect.x + tab_rect.width - app.font_size, tab_rect.y },
					{ tab_rect.x + tab_rect.width, tab_rect.y + tab_rect.height },
					app.style.bg_color)
			}
		}
		rl.BeginScissorMode(i32(tab_rect.x + app.font_size), i32(tab_rect.y), i32(tab_rect.width - app.font_size * 2), i32(tab_rect.height))
		name_cstring := strings.clone_to_cstring(editor.name, context.temp_allocator)
		text_size := rl.MeasureTextEx(app.font, name_cstring, app.font_size, 0)
		text_pos := rl.Vector2 { 
			tab_rect.x + tab_rect.width / 2 - text_size[0] / 2, 
			tab_rect.y + tab_rect.height / 2 - text_size[1] / 2
		}
		text_color := i == app.editor_index ? app.style.text_color : app.style.text_color2
		rl.DrawTextEx(app.font, name_cstring, text_pos, app.font_size, 0, text_color)
		rl.EndScissorMode()
	}
}

any_editor_open :: proc(app: ^App) -> bool {
	return len(app.editors) != 0 || app.file_picker.visible 
}

set_font :: proc(app: ^App, font: rl.Font, font_size: f32) {
	fi.set_font(&app.find, font, font_size)
	fp.set_font(&app.file_picker, font, font_size)
	co.set_font(&app.commands, font, font_size)

	for &editor in app.editors {
		ed.set_font(&editor, font, font_size)
	}
}

load_font :: proc(path: string, font_size: f32) -> rl.Font {
	font_path := strings.clone_to_cstring(path, context.temp_allocator)
	return rl.LoadFontEx(font_path, i32(font_size * 2), nil, 0)
}

layout :: proc(app: ^App) {
	screen_rect := rl.Rectangle { 0, 0, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight()) }

	tabs_rect, editor_rect := rec.cut_top(screen_rect, app.font_size)
	app.tabs_rect = tabs_rect
	if len(app.editors) != 0 {
		code_editor(app).rect = editor_rect
	}

	app.find.input.rect, _ = rec.cut_bottom(screen_rect, app.font_size)
	fp.set_rect(&app.file_picker, rec.center_in_area({ 0, 0, 700, 400 }, screen_rect))
	co.set_rect(&app.commands, rec.center_in_area({ 0, 0, 700, 300 }, screen_rect))
}