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

	file_picker_update_content(
		file_picker, 
		file_picker_items_from_dir(file_picker.dir, context.temp_allocator))
}

file_picker_deinit :: proc(file_picker: ^File_Picker) {
	delete(file_picker.dir)
	editor_deinit(&file_picker.content)
}

file_picker_show :: proc(file_picker: ^File_Picker) {
	file_picker.visible = true
}

file_picker_hide :: proc(file_picker: ^File_Picker) {
	file_picker.visible = false
}

// TODO: clean this whole thing
file_picker_input :: proc(file_picker: ^File_Picker, allocator := context.allocator) -> (bool, string) {
	if file_picker.visible == false {
		return false, strings.clone("", allocator)
	}

	handled := false
	selected := ""

	if rl.IsKeyPressed(.ENTER) {
		line := editor_line_from_pos(&file_picker.content, file_picker.content.cursor.head)
		line_range := file_picker.content.buffer.line_ranges[line]
		text := string(file_picker.content.buffer.content[line_range.start:line_range.end])
	
		full_path: string = ---
		if file_picker.dir != "" {
			full_path = join_paths({ file_picker.dir, text }, context.temp_allocator)
		}
		else {
			// text is a disk
			full_path = strings.clone(text, context.temp_allocator)
		}
	
		if text == ".." {
			parent_path := parent_path(file_picker.dir)
			items: []string
			if strings.ends_with(file_picker.dir, ":") {
				items = file_picker_items_from_drives()
				file_picker_set_dir(file_picker, "")
			}
			else {
				items = file_picker_items_from_dir(parent_path)
				file_picker_set_dir(file_picker, parent_path)
			}
			file_picker_update_content(file_picker, items)
			handled = true
		}
		else if os.is_file(full_path) {
			selected = full_path 
			file_picker.visible = false
			handled = true
		}
		else {
			file_picker_set_dir(file_picker, full_path)	
			file_picker_update_content(
				file_picker, 
				file_picker_items_from_dir(full_path, context.temp_allocator))
			handled = true
		}
	}
	else if (key_pressed_or_repeated(.DOWN) || key_pressed_or_repeated(.UP)) &&
	rl.IsKeyDown(.LEFT_SHIFT) == false {
		handled = editor_input(&file_picker.content)
	}
	return handled, strings.clone(selected, allocator)
}

file_picker_draw :: proc(file_picker: ^File_Picker) {
	theme := &file_picker.app.theme

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

file_picker_items_from_drives :: proc(allocator := context.allocator) -> []string {
	items := make([dynamic]string, allocator)
	// funny code to get all the drives
	// TODO: implement an actual solution
	for char in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" {
		drive := fmt.tprint(char, ":", sep = "")
		if os.is_dir(drive) {
			append(&items, drive)
		}
	}
	return items[:]
}

file_picker_items_from_dir :: proc(dir: string, allocator := context.allocator) -> []string {
	files, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	assert(err == nil)

	items := make([dynamic]string, allocator)
	append(&items, "..")
	
	for file in files {
		append(&items, file.name)
	}

	return items[:]
}

file_picker_update_content :: proc(file_picker: ^File_Picker, items: []string) {
	editor_select(&file_picker.content, editor_all(&file_picker.content))
	editor_delete(&file_picker.content)

	for item, i in items {
		editor_insert(&file_picker.content, item)
		if i != len(items) - 1 {
			editor_insert(&file_picker.content, "\n") 
		}
	}
	editor_goto(&file_picker.content, 0)
}

file_picker_set_rect :: proc(file_picker: ^File_Picker, rect: rl.Rectangle) {
	file_picker.content.rect = rect
}

file_picker_set_dir :: proc(file_picker: ^File_Picker, dir: string)
{
	// dir might be a slice of file_picker.dir so clone it early.
	to_be_assigned := strings.clone(dir)
	delete(file_picker.dir)
	file_picker.dir = to_be_assigned 
}