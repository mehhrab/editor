package editor

import rl "vendor:raylib"
import os "core:os/os2"
import "core:strings"
import "core:fmt"
import "path"

File_Picker :: struct {
	app: ^App,
	list: List,
	visible: bool,
	dir: string,
	
	events: [dynamic]File_Picker_Event,
}

File_Picker_Event :: union {
	File_Picker_Selected,
}

File_Picker_Selected :: struct {
	path: string,
}

file_picker_init :: proc(file_picker: ^File_Picker, app: ^App, dir: string) {
	file_picker.app = app
	file_picker_set_dir(file_picker, dir)

	list_init(&file_picker.list, app)
	file_picker_update_content(
		file_picker, 
		file_picker_items_from_dir(file_picker.dir, context.temp_allocator))
}

file_picker_deinit :: proc(file_picker: ^File_Picker) {
	delete(file_picker.dir)
	list_deinit(&file_picker.list)
	delete(file_picker.events)
}

file_picker_show :: proc(file_picker: ^File_Picker) {
	file_picker.visible = true
}

file_picker_hide :: proc(file_picker: ^File_Picker) {
	file_picker.visible = false
}

// TODO: clean this whole thing
file_picker_input :: proc(file_picker: ^File_Picker) -> ([]File_Picker_Event, bool) {
	clear(&file_picker.events)

	if file_picker.visible == false {
		return file_picker.events[:], false
	}

	handled := false

	if rl.IsKeyPressed(.ENTER) {
		_, text := list_get_current_item(&file_picker.list, context.temp_allocator)

		full_path: string = ---
		if file_picker.dir != "" {
			full_path = path.join({ file_picker.dir, text }, context.temp_allocator)
		}
		else {
			// text is a disk
			full_path = strings.clone(text, context.temp_allocator)
		}
	
		if text == ".." {
			parent_path := path.parent(file_picker.dir)
			items: []string
			if strings.ends_with(file_picker.dir, ":") {
				items = file_picker_items_from_drives(context.temp_allocator)
				file_picker_set_dir(file_picker, "")
			}
			else {
				items = file_picker_items_from_dir(parent_path, context.temp_allocator)
				file_picker_set_dir(file_picker, parent_path)
			}
			file_picker_update_content(file_picker, items)
			handled = true
		}
		else if os.is_file(full_path) {
			append(&file_picker.events, File_Picker_Selected {
				path = full_path
			})
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
	else {
		handled = list_input(&file_picker.list)
	}
	return file_picker.events[:], handled
}

file_picker_draw :: proc(file_picker: ^File_Picker) {
	theme := &file_picker.app.theme

	padding := f32(20)
	expanded_rect := file_picker.list.rect
	expanded_rect.x -= padding
	expanded_rect.y -= padding
	expanded_rect.width += padding * 2
	expanded_rect.height += padding * 2

	shadow_rect := expanded_rect
	shadow_rect.x += 20
	shadow_rect.y += 20
	rl.DrawRectangleRec(shadow_rect, { 0, 0, 0, 255 })

	rl.DrawRectangleRec(expanded_rect, theme.bg)
	list_draw(&file_picker.list)
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
	list_clear(&file_picker.list)
	list_add_items(&file_picker.list, items)
	list_set_current_item(&file_picker.list, 0)
}

file_picker_set_rect :: proc(file_picker: ^File_Picker, rect: rl.Rectangle) {
	list_set_rect(&file_picker.list, rect)
}

file_picker_set_dir :: proc(file_picker: ^File_Picker, dir: string)
{
	// dir might be a slice of file_picker.dir so clone it early.
	to_be_assigned := strings.clone(dir)
	delete(file_picker.dir)
	file_picker.dir = to_be_assigned 
}