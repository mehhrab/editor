package file_picker

import "core:strings"
import "core:fmt"
import os "core:os/os2"
import rl "vendor:raylib"
import "../path"
import li "../list"

File_Picker :: struct {
	list: li.List,
	dir: string,

	font: rl.Font,
	font_size: f32,
	style: Style,
	visible: bool,
}

Style :: struct {
	outline_color: rl.Color,
	list: li.Style,
}

init :: proc(file_picker: ^File_Picker, style: ^Style, dir: string) {
	file_picker.style = style^

	set_dir(file_picker, dir)

	li.init(&file_picker.list, &style.list)
	items := items_from_dir(file_picker.dir, context.temp_allocator)
	update_content(file_picker, items)
}

deinit :: proc(file_picker: ^File_Picker) {
	delete(file_picker.dir)
	li.deinit(&file_picker.list)
}

show :: proc(file_picker: ^File_Picker) {
	file_picker.visible = true
}

hide :: proc(file_picker: ^File_Picker) {
	file_picker.visible = false
}

select :: proc(file_picker: ^File_Picker) -> Maybe(string) {
	selected: Maybe(string)
	_, text := li.get_current_item(&file_picker.list, context.temp_allocator)

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
			items = items_from_drives(context.temp_allocator)
			set_dir(file_picker, "")
		}
		else {
			items = items_from_dir(parent_path, context.temp_allocator)
			set_dir(file_picker, parent_path)
		}
		update_content(file_picker, items)
	}
	else if os.is_file(full_path) {
		selected = full_path
	}
	else {
		set_dir(file_picker, full_path)	
		update_content(
			file_picker, 
			items_from_dir(full_path, context.temp_allocator))
	}

	return selected
}

go_up :: proc(file_picker: ^File_Picker) {
	li.go_up(&file_picker.list)
}

go_down :: proc(file_picker: ^File_Picker) {
	li.go_down(&file_picker.list)
}

draw :: proc(file_picker: ^File_Picker) {
	padding := file_picker.font_size / 2
	expanded_rect := file_picker.list.rect
	expanded_rect.x -= padding
	expanded_rect.y -= padding
	expanded_rect.width += padding * 2
	expanded_rect.height += padding * 2

	shadow_rect := expanded_rect
	shadow_rect.x += padding
	shadow_rect.y += padding
	rl.DrawRectangleRec(shadow_rect, { 0, 0, 0, 255 })

	bg_color := file_picker.style.list.content.bg_color
	rl.DrawRectangleRec(expanded_rect, bg_color)
	li.draw(&file_picker.list)
	rl.DrawRectangleLinesEx(expanded_rect, 1, file_picker.style.outline_color)
}

items_from_drives :: proc(allocator := context.allocator) -> []string {
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

items_from_dir :: proc(dir: string, allocator := context.allocator) -> []string {
	files, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	assert(err == nil)

	items := make([dynamic]string, allocator)
	append(&items, "..")
	
	for file in files {
		append(&items, file.name)
	}

	return items[:]
}

update_content :: proc(file_picker: ^File_Picker, items: []string) {
	li.clear(&file_picker.list)
	li.add_items(&file_picker.list, items)
	li.set_current_item(&file_picker.list, 0)
}

set_rect :: proc(file_picker: ^File_Picker, rect: rl.Rectangle) {
	li.set_rect(&file_picker.list, rect)
}

set_dir :: proc(file_picker: ^File_Picker, dir: string) {
	// dir might be a slice of file_picker.dir so clone it early.
	to_be_assigned := strings.clone(dir)
	delete(file_picker.dir)
	file_picker.dir = to_be_assigned 
}

set_style :: proc(file_picker: ^File_Picker, style: Style) {
	file_picker.style = style
	li.set_style(&file_picker.list, style.list)
}

set_font :: proc(file_picker: ^File_Picker, font: rl.Font, font_size: f32) {
	file_picker.font = font
	file_picker.font_size = font_size
	li.set_font(&file_picker.list, font, font_size)
}