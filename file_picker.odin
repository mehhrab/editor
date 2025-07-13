package editor

import rl "vendor:raylib"
import os "core:os/os2"
import "core:strings"
import "core:fmt"

File_Picker :: struct {
	app: ^App,
	content: Editor,
	visible: bool,
	dir: string,
}

file_picker_init :: proc(file_picker: ^File_Picker, app: ^App, dir: string) {
	file_picker.app = app
	file_picker_set_dir(file_picker, dir)

	buffer: Buffer; buffer_init(&buffer, "")
	editor_init(&file_picker.content, file_picker.app, &buffer, "", "")
	file_picker.content.hightlight_line = true
	file_picker.content.hide_cursor = true
}

file_picker_deinit :: proc(file_picker: ^File_Picker) {
	delete(file_picker.dir)
	editor_deinit(&file_picker.content)
}

file_picker_show :: proc(file_picker: ^File_Picker) {
	file_picker.visible = true
	file_picker_update_content(file_picker)
}

file_picker_input :: proc(file_picker: ^File_Picker, allocator := context.allocator) -> string {
	selected := ""
	if rl.IsKeyPressed(.ENTER) {
		line := editor_line_from_pos(&file_picker.content, file_picker.content.cursor.head)
		line_range := file_picker.content.buffer.line_ranges[line]
		text := string(file_picker.content.buffer.content[line_range.start:line_range.end])
		path := join_paths({ file_picker.dir, text }, context.temp_allocator)
		if text == ".." {
			file_picker_set_dir(file_picker, parent_path(file_picker.dir))
			file_picker_update_content(file_picker)
		}
		else if os.is_directory(path) {
			file_picker_set_dir(file_picker, path)
			file_picker_update_content(file_picker)
		} 
		else {
			selected = path
			file_picker.visible = false
		}
	}
	else if rl.IsKeyPressed(.ESCAPE) {
		file_picker.visible = false
	}
	else if (key_pressed_or_repeated(.DOWN) || key_pressed_or_repeated(.UP)) &&
	rl.IsKeyDown(.LEFT_SHIFT) == false {
		editor_input(&file_picker.content)
	}
	return strings.clone(selected, allocator)
}

file_picker_draw :: proc(file_picker: ^File_Picker) {
	theme := &file_picker.app.theme
	screen_rect := rl.Rectangle { 0, 0, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight()) }
	rl.DrawRectangleRec(screen_rect, { 0, 0, 0, 55 })

	padding := f32(20)
	expanded_rect := file_picker.content.rect
	expanded_rect.x -= padding
	expanded_rect.y -= padding
	expanded_rect.width += padding * 2
	expanded_rect.height += padding * 2

	shadow_rect := expanded_rect
	shadow_rect.x += 20
	shadow_rect.y += 20
	rl.DrawRectangleRec(shadow_rect, { 0, 0, 0, 255 })

	rl.DrawRectangleRec(expanded_rect, theme.bg)
	editor_draw(&file_picker.content)
	rl.DrawRectangleLinesEx(expanded_rect, 1, theme.selection)
}

file_picker_update_content :: proc(file_picker: ^File_Picker) {
	files, err := os.read_all_directory_by_path(file_picker.dir, context.temp_allocator)
	assert(err == nil)

	editor_select(&file_picker.content, editor_all(&file_picker.content))
	editor_delete(&file_picker.content)

	editor_insert(&file_picker.content, "..")
	for file in files {
		editor_insert(&file_picker.content, "\n")
		editor_insert(&file_picker.content, file.name)
	}
	editor_goto(&file_picker.content, 0)
}

file_picker_set_rect :: proc(file_picker: ^File_Picker, rect: rl.Rectangle) {
	file_picker.content.rect = rect
}

file_picker_set_dir :: proc(file_picker: ^File_Picker, dir: string)
{
	delete(file_picker.dir)
	file_picker.dir = strings.clone(dir)
}