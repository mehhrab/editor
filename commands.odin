// TODO: add fuzzy search
package editor

import "core:strings"
import "core:fmt"
import rl "vendor:raylib"

Commands :: struct {
	app: ^App,
	input: Editor,
	content: Editor,
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
		text := "new file\nopen file\nshow explorer\nclose window"
		buffer: Buffer; buffer_init(&buffer)
		editor_init(&commands.content, app, &buffer, "", "")
		commands.content.hide_cursor = true
		commands.content.hightlight_line = true

		for item, i in items {
			append(&commands.items, strings.clone(item))
		}

		for item, i in commands.items {
			append(&commands.sorted_items, Command_Sorted { i, item })
		}

		for item, i in commands.sorted_items {
			editor_insert_raw(&commands.content, item.name)
			if i != len(items) - 1 {
				editor_insert_raw(&commands.content, "\n") 
			}
		}

		editor_goto(&commands.content, 0)
	}
}

commands_deinit :: proc(commands: ^Commands) {
	delete(commands.sorted_items)
	for item in commands.items {
		delete(item)
	}
	delete(commands.items)
	editor_deinit(&commands.content)
	editor_deinit(&commands.input)
	delete(commands.events)
}

commands_input :: proc(commands: ^Commands) -> ([]Commands_Event, bool) {
	clear(&commands.events)
	handled := false
	
	if commands.visible == false {
		return commands.events[:], false
	}

	if rl.IsKeyDown(.LEFT_SHIFT) == false &&
	(key_pressed_or_repeated(.DOWN) ||
	key_pressed_or_repeated(.UP)) {
		handled = editor_input(&commands.content)
	}
	else if key_pressed_or_repeated(.ENTER) {
		if 1 <= len(commands.sorted_items) {			
			index := editor_line_from_pos(&commands.content, commands.content.cursor.head)
			command := commands.sorted_items[index]
			append(&commands.events, Commands_Selected {
				index = command.index,
				name = command.name,
			})
			commands.visible = false
		}
		handled = true
	}
	else {
		handled = editor_input(&commands.input)
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
	clear(&commands.content.highlighted_ranges)

	ranges := make([dynamic]Range)
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

	editor_clear(&commands.content)
	for item, i in commands.sorted_items {
		editor_insert_raw(&commands.content, item.name)
		if i != len(commands.sorted_items) - 1 {
			editor_insert_raw(&commands.content, "\n") 
		}
	}
	editor_goto(&commands.content, 0)

	line := 0
	for range in ranges {
		if range == RANGE_NEW_LINE {
			line += 1
			continue
		}

		line_start := commands.content.buffer.line_ranges[line].start
		append(&commands.content.highlighted_ranges, Range {
			start = line_start + range.start,
			end = line_start + range.end,
		})
	}
}

commands_draw :: proc(commands: ^Commands) {
	editor_draw(&commands.input)
	editor_draw(&commands.content)
	rl.DrawRectangleLinesEx(commands.input.rect, 1, commands.app.theme.selection)
	rl.DrawRectangleLinesEx(commands.content.rect, 1, commands.app.theme.selection)
}

commands_set_rect :: proc(commands: ^Commands, rect: rl.Rectangle) {
	commands.input.rect = rect
	commands.input.rect.height = 40

	commands.content.rect = rect
	commands.content.rect.y += 40	
	commands.content.rect.height -= 40	
}

commands_show :: proc(commands: ^Commands) {
	commands.visible = true
	editor_select(&commands.input, editor_all(&commands.input))
}

commands_hide :: proc(commands: ^Commands) {
	commands.visible = false
}