package editor

import rl "vendor:raylib"
import fmt "core:fmt"
import "core:strings"
import "core:mem"
import "core:slice"
import os "core:os/os2"

App :: struct {
	theme: Theme,
	font: rl.Font,
	font_size: f32,
	editors: [dynamic]Editor,
	editor_index: int,
	find: Find,
	file_picker: File_Picker,
	chars_pressed: [dynamic]rune,
}

Range :: struct {
	start, end: int,
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
	defer delete(app.chars_pressed)

	defer {
		for &editor in app.editors {
			editor_deinit(&editor)
		}
		delete(app.editors)
	}

	app_open_file(&app, join_paths({ current_dir, "app.odin" }))

	find_init(&app.find, &app, &app.editors[app.editor_index])
	defer find_deinit(&app.find)

	file_picker_init(&app.file_picker, &app, current_dir)
	defer file_picker_deinit(&app.file_picker)

	for rl.WindowShouldClose() == false {
		char := rl.GetCharPressed();
		for char != 0 {
			append(&app.chars_pressed, char)
			char = rl.GetCharPressed();
		}

		screen_rect := rl.Rectangle { 0, 0, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight()) }
		app.editors[app.editor_index].rect = { 0, 41, screen_rect.width, screen_rect.height - 40 }
		app.find.input.rect = { 0, screen_rect.height - 40, screen_rect.width, 40 }
		
		file_picker_rect := rl.Rectangle { 0, 0, 700, 400 }
		file_picker_rect.x = screen_rect.width / 2 - file_picker_rect.width / 2
		file_picker_rect.y = screen_rect.height / 2 - file_picker_rect.height / 2
		file_picker_set_rect(&app.file_picker, file_picker_rect)

		if app_input(&app) == false {
			if app.file_picker.visible {
				selected := file_picker_input(&app.file_picker, context.temp_allocator)
				if selected != "" {
					app_open_file(&app, selected)
				}
			}
			else if app.find.visible {
				find_input(&app.find)
			}
			else {
				editor_input(&app.editors[app.editor_index])
			}
		}

		rl.BeginDrawing()
		rl.ClearBackground(app.theme.bg_dim)
		
		for editor, i in app.editors {
			tab_w := screen_rect.width / f32(len(app.editors))
			tab_rect := rl.Rectangle { f32(i) * tab_w, 0, tab_w, 40 }
			rl.DrawRectangleRec(tab_rect, i == app.editor_index ? app.theme.bg : app.theme.bg_dim)
			if len(app.editors) != 0 && i == app.editor_index {
				if i != 0 {
					rl.DrawTriangle(
						{ tab_rect.x, tab_rect.y + tab_rect.height },
						{ tab_rect.x + 40, tab_rect.y },
						{ tab_rect.x, tab_rect.y }, 
						app.theme.bg_dim)
				}
				if i != len(app.editors) - 1 {					
					rl.DrawTriangle(
						{ tab_rect.x + tab_rect.width, tab_rect.y }, 
						{ tab_rect.x + tab_rect.width - 40, tab_rect.y },
						{ tab_rect.x + tab_rect.width, tab_rect.y + tab_rect.height },
						app.theme.bg_dim)
				}
			}
			rl.BeginScissorMode(i32(tab_rect.x + 40), i32(tab_rect.y), i32(tab_rect.width - 40 * 2), i32(tab_rect.height))
			name_cstring := strings.clone_to_cstring(editor.name, context.temp_allocator)			
			text_w := rl.MeasureTextEx(app.font, name_cstring, 40, 0)[0]
			text_pos := rl.Vector2 { tab_rect.x + tab_rect.width / 2 - text_w / 2, tab_rect.y }
			rl.DrawTextEx(app.font, name_cstring, text_pos, 40, 0, i == app.editor_index ? app.theme.text : app.theme.text2)
			rl.EndScissorMode()
		}
		
		editor_draw(&app.editors[app.editor_index])
		
		if app.find.visible {
			find_draw(&app.find)
		}
		
		if app.file_picker.visible {
			file_picker_draw(&app.file_picker)
		}

		rl.EndDrawing()

		clear(&app.chars_pressed)
		free_all(context.temp_allocator)
	}
}

app_input :: proc(app: ^App) -> bool {
	editor := &app.editors[app.editor_index]

	handled := false
	if rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyPressed(.F) {
		find_show(&app.find, editor_selected_text(editor))
		handled = true
	}
	else if rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyPressed(.P) {
		file_picker_show(&app.file_picker)
		handled = true
	}
	else if rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyPressed(.TAB) {
		app_focus_editor(app, (app.editor_index + 1) % len(app.editors)) 
		handled = true
	}
	else if rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyPressed(.N) {
		app_new_file(app)
		handled = true
	}
	else if rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyPressed(.W) {
		if 1 < len(app.editors) {			
			editor_deinit(&app.editors[app.editor_index])
			ordered_remove(&app.editors, app.editor_index)
			app_focus_editor(app, len(app.editors) - 1)
		}
		handled = true
	}
	return handled
}

app_new_file :: proc(app: ^App, content := "") -> int {
	append(&app.editors, Editor {})
	index := len(app.editors) - 1
	editor := &app.editors[index]

	buffer: Buffer; buffer_init(&buffer, content)
	editor_init(editor, app, &buffer, "", "*untitled*")
	editor.highlight = true
	editor.line_numbers = true

	app_focus_editor(app, index)
	
	return index
}

app_open_file :: proc(app: ^App, path: string) -> int {
	for editor, i in app.editors {
		if editor.path == path {
			return i
		}
	}

	file_name := shorten_path(path)
	text, err := os.read_entire_file(path, context.temp_allocator)
	assert(err == nil)

	append(&app.editors, Editor {})
	index := len(app.editors) - 1
	editor := &app.editors[index]

	buffer: Buffer; buffer_init(&buffer, string(text))
	editor_init(editor, app, &buffer, path, file_name)
	editor.highlight = true
	editor.line_numbers = true

	app_focus_editor(app, index)
	
	return index
}

app_focus_editor :: proc(app: ^App, index: int) {
	app.editor_index = index
	app.find.editor = &app.editors[app.editor_index]
	if app.find.visible {
		find_matches(&app.find)
	}
}

key_pressed_or_repeated :: proc(key: rl.KeyboardKey) -> bool {
	return rl.IsKeyPressed(key) || rl.IsKeyPressedRepeat(key) 
}