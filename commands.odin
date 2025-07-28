// TODO: add fuzzy search
package editor

import "core:strings"
import "core:fmt"
import rl "vendor:raylib"

Commands :: struct {
	app: ^App,
	input: Editor,
	list: List,
	items: [dynamic]string,
	sorted_items: [dynamic]Command_Sorted,
	events: [dynamic]Commands_Event,
	visible: bool,
	rect: rl.Rectangle,
}

Command_Sorted :: struct {
	index: int,
	name: string,
}

Commands_Event :: union {
	Commands_Selected,
}

Commands_Selected :: struct {
	index: int,
	name: string,
}

commands_init :: proc(commands: ^Commands, app: ^App, items: []string) {
	commands.app = app
	{		
		buffer: Buffer; buffer_init(&buffer)
		editor_init(&commands.input, app, &buffer, "", "")
	}
	{
		list_init(&commands.list, app)

		for item, i in items {
			append(&commands.items, strings.clone(item))
		}

		for item, i in commands.items {
			append(&commands.sorted_items, Command_Sorted { i, item })
		}

		for item, i in commands.sorted_items {
			list_add_items(&commands.list, { item.name })
		}
		list_set_current_item(&commands.list, 0)
	}
}

commands_deinit :: proc(commands: ^Commands) {
	delete(commands.sorted_items)
	for item in commands.items {
		delete(item)
	}
	delete(commands.items)
	list_deinit(&commands.list)
	editor_deinit(&commands.input)
	delete(commands.events)
}

commands_input :: proc(commands: ^Commands) -> ([]Commands_Event, bool) {
	clear(&commands.events)
	handled := false
	
	if commands.visible == false {
		return commands.events[:], false
	}

	if key_pressed_or_repeated(.ENTER) {
		if 1 <= len(commands.sorted_items) {
			index, name := list_get_current_item(&commands.list, context.temp_allocator)			
			command := commands.sorted_items[index]
			append(&commands.events, Commands_Selected {
				index = command.index,
				name = name,
			})
		}
		handled = true
	}
	else {
		handled = list_input(&commands.list) 
		if handled == false { 
			handled = editor_input(&commands.input)
		}

		if len(commands.app.chars_pressed) != 0 {
			commands_refresh(commands)
			handled = true 
		}
		if key_pressed_or_repeated(.BACKSPACE) {
			commands_refresh(commands)
			handled = true
		}
	}
	return commands.events[:], handled
}

commands_refresh :: proc(commands: ^Commands) {
	clear(&commands.sorted_items)
	clear(&commands.list.content.highlighted_ranges)

	ranges := make([dynamic]Range, context.temp_allocator)
	RANGE_NEW_LINE :: Range { -1, -1 }

	for item, i in commands.items {
		query := strings.to_lower(string(commands.input.buffer.content[:]), context.temp_allocator)
		item_lowered := strings.to_lower(item, context.temp_allocator)
		
		match_start := strings.index(item_lowered, query)
		if match_start != -1 {
			if query != "" {
				append(&ranges, Range {
					start = match_start,
					end = match_start + len(query)
				}) 
			}
			append(&commands.sorted_items, Command_Sorted { 
				index = i, 
				name = item 
			})
			append(&ranges, RANGE_NEW_LINE)
		}
	}

	list_clear(&commands.list)
	for item, i in commands.sorted_items {
		list_add_items(&commands.list, { item.name })
	}
	list_set_current_item(&commands.list, 0)

	line := 0
	for range in ranges {
		if range == RANGE_NEW_LINE {
			line += 1
			continue
		}

		line_start := commands.list.content.buffer.line_ranges[line].start
		append(&commands.list.content.highlighted_ranges, Range {
			start = line_start + range.start,
			end = line_start + range.end,
		})
	}
}

commands_draw :: proc(commands: ^Commands) {
	editor_draw(&commands.input)
	rl.DrawRectangleLinesEx(commands.input.rect, 1, commands.app.theme.selection)
	list_draw(&commands.list)
}

commands_set_rect :: proc(commands: ^Commands, rect: rl.Rectangle) {
	commands.input.rect = rect
	commands.input.rect.height = 40

	list_rect := rect
	list_rect.y += 40	
	list_rect.height -= 40
	list_set_rect(&commands.list, list_rect)	
}

commands_show :: proc(commands: ^Commands) {
	commands.visible = true
	editor_select(&commands.input, editor_all(&commands.input))
}

commands_hide :: proc(commands: ^Commands) {
	commands.visible = false
}