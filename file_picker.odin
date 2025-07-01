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
	file_picker.dir = dir
}

file_picker_show :: proc(file_picker: ^File_Picker) {
	file_picker.visible = true
	file_picker_update_content(file_picker)
}

file_picker_input :: proc(file_picker: ^File_Picker) -> string {
	selected := ""
	if rl.IsKeyPressed(.ENTER) {
		line := editor_get_cursor_line(&file_picker.content)
		line_range := file_picker.content.buffer.line_ranges[line]
		text := string(file_picker.content.buffer.content[line_range.start:line_range.end])
		path := strings.join({ file_picker.dir, text }, "\\")
		if text == ".." {
			index := strings.last_index(file_picker.dir, "\\")
			file_picker.dir = strings.cut(file_picker.dir, 0, index)
			file_picker_update_content(file_picker)
		}
		else if os.is_directory(path) {
			file_picker.dir = path
			file_picker_update_content(file_picker)
		} 
		else {
			selected = path
			file_picker.visible = false
		}
	}
	else if rl.IsKeyPressed(.BACKSPACE) {}
	else if len(file_picker.app.chars_pressed) != 0 {}
	else {
		editor_input(&file_picker.content)
	}
	return selected
}

file_picker_draw :: proc(file_picker: ^File_Picker) {
	rl.DrawRectangleRec(file_picker.content.rect, { 0, 20, 40, 255 })
	editor_draw(&file_picker.content)
	rl.DrawRectangleLinesEx(file_picker.content.rect, 1, rl.SKYBLUE)
}

file_picker_update_content :: proc(file_picker: ^File_Picker) {
	files, err := os.read_all_directory_by_path(file_picker.dir, context.allocator)
	assert(err == nil)
	buffer: Buffer; buffer_init(&buffer, "")
	editor_init(&file_picker.content, file_picker.app, &buffer)
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