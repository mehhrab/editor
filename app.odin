package editor

import rl "vendor:raylib"
import fmt "core:fmt"
import "core:strings"
import "core:mem"
import "core:slice"
import os "core:os/os2"

App :: struct {
	font: rl.Font,
	font_size: f32,
	editors: [dynamic]Editor,
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

	// init app
	app := App {}
	app.font_size = 40
	app.font = rl.LoadFontEx("FiraCode-Regular.ttf", i32(app.font_size * 2), nil, 0)
	defer delete(app.chars_pressed)

	append(&app.editors, Editor {})
	defer {
		for &editor in app.editors {
			editor_deinit(&editor)
		}
		delete(app.editors)
	}

	buffer: Buffer; buffer_init(&buffer, #load(#file))
	editor_init(&app.editors[0], &app, &buffer)
	app.editors[0].highlight = true
	app.editors[0].line_numbers = true

	find_init(&app.find, &app, &app.editors[0])
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
		app.editors[0].rect = { 0, 0, screen_rect.width, screen_rect.height - 40 }
		app.find.input.rect = { 0, screen_rect.height - 40, screen_rect.width, 40 }
		
		file_picker_rect := rl.Rectangle { 0, 0, 700, 400 }
		file_picker_rect.x = screen_rect.width / 2 - file_picker_rect.width / 2
		file_picker_rect.y = screen_rect.height / 2 - file_picker_rect.height / 2
		file_picker_set_rect(&app.file_picker, file_picker_rect)

		if app_input(&app) == false {
			if app.find.visible {
				find_input(&app.find)
			}
			else if app.file_picker.visible {
				selected := file_picker_input(&app.file_picker, context.temp_allocator)
				if selected != "" {
					text, err := os.read_entire_file(selected, context.temp_allocator)
					assert(err == nil)

					editor_deinit(&app.editors[0])
					app.editors[0] = {}

					buffer: Buffer; buffer_init(&buffer, string(text))
					editor_init(&app.editors[0], &app, &buffer)
					app.editors[0].highlight = true
					app.editors[0].line_numbers = true
				}
			}
			else {
				editor_input(&app.editors[0])
			}
		}
		// if rl.IsKeyPressed(.F6) {
		// 	fmt.printfln("{}", string(app.find_editor.buffer.content[:]))
		// }
		rl.BeginDrawing()
		rl.ClearBackground({ 0, 20, 40, 255 })
		
		editor_draw(&app.editors[0])
		if app.find.visible {
			find_draw(&app.find)
		}
		else {
			rect := app.find.input.rect
			rl.DrawRectangleRec(rect, rl.SKYBLUE)
			rl.DrawTextEx(app.font, "app.odin", { rect.x, rect.y }, 40, 0, rl.BLACK)
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
	editor := &app.editors[0]

	handled := false
	if rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyPressed(.F) {
		find_show(&app.find, editor_selected_text(editor))
		handled = true
	}
	else if rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyPressed(.P) {
		file_picker_show(&app.file_picker)
		handled = true
	}
	return handled
}

key_pressed_or_repeated :: proc(key: rl.KeyboardKey) -> bool {
	return rl.IsKeyPressed(key) || rl.IsKeyPressedRepeat(key) 
}