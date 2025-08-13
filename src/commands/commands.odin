// TODO: add fuzzy search
package commands

import "core:strings"
import "core:fmt"
import rl "vendor:raylib"
import buf "../buffer"
import ed "../editor"
import li "../list"
import rg "../range"

Commands :: struct {
	input: ed.Editor,
	list: li.List,
	items: [dynamic]string,
	sorted_items: [dynamic]Command_Sorted,

	style: Style,
	visible: bool,
	rect: rl.Rectangle,
}

Command_Sorted :: struct {
	index: int,
	name: string,
}

Style :: struct {
	outline_color: rl.Color,
	input: ed.Style,
	list: li.Style,
}


init :: proc(commands: ^Commands, style: ^Style, items: []string) {
	commands.style = style^

	{
		buffer: buf.Buffer; buf.init(&buffer)
		ed.init(&commands.input, &style.input, &buffer, "", "")
	}
	{
		li.init(&commands.list, &style.list)

		for item, i in items {
			append(&commands.items, strings.clone(item))
		}

		for item, i in commands.items {
			append(&commands.sorted_items, Command_Sorted { i, item })
		}

		for item, i in commands.sorted_items {
			li.add_items(&commands.list, { item.name })
		}
		li.set_current_item(&commands.list, 0)
	}
}

deinit :: proc(commands: ^Commands) {
	delete(commands.sorted_items)
	for item in commands.items {
		delete(item)
	}
	delete(commands.items)
	li.deinit(&commands.list)
	ed.deinit(&commands.input)
}

get_selected :: proc(commands: ^Commands) -> (int, string) {
	index, name := li.get_current_item(&commands.list, context.temp_allocator)			
	command := commands.sorted_items[index]
	return command.index, command.name
}

go_up :: proc(commands: ^Commands) {
	li.go_up(&commands.list)
}

go_down :: proc(commands: ^Commands) {
	li.go_down(&commands.list)
}

replace :: proc(commands: ^Commands, text: string) {
	refresh(commands)
	ed.replace(&commands.input, &commands.input.cursors[0], text)	
}

refresh :: proc(commands: ^Commands) {
	clear(&commands.sorted_items)
	clear(&commands.list.content.highlighted_ranges)

	ranges := make([dynamic]rg.Range, context.temp_allocator)
	RANGE_NEW_LINE :: rg.Range { -1, -1 }

	for item, i in commands.items {
		query := strings.to_lower(string(commands.input.buffer.content[:]), context.temp_allocator)
		item_lowered := strings.to_lower(item, context.temp_allocator)
		
		match_start := strings.index(item_lowered, query)
		if match_start != -1 {
			if query != "" {
				append(&ranges, rg.Range {
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

	li.clear(&commands.list)
	for item, i in commands.sorted_items {
		li.add_items(&commands.list, { item.name })
	}
	li.set_current_item(&commands.list, 0)

	line := 0
	for range in ranges {
		if range == RANGE_NEW_LINE {
			line += 1
			continue
		}

		line_start := commands.list.content.buffer.line_ranges[line].start
		append(&commands.list.content.highlighted_ranges, rg.Range {
			start = line_start + range.start,
			end = line_start + range.end,
		})
	}
}

draw :: proc(commands: ^Commands) {
	ed.draw(&commands.input)
	li.draw(&commands.list)
	rl.DrawRectangleLinesEx(commands.rect, 1, commands.style.outline_color)
}

set_rect :: proc(commands: ^Commands, rect: rl.Rectangle) {
	commands.rect = rect
	commands.input.rect = rect
	commands.input.rect.height = 40

	list_rect := rect
	list_rect.y += 40	
	list_rect.height -= 40
	li.set_rect(&commands.list, list_rect)	
}

show :: proc(commands: ^Commands) {
	commands.visible = true
	ed.select(&commands.input, &commands.input.cursors[0], ed.all(&commands.input))
}

hide :: proc(commands: ^Commands) {
	commands.visible = false
}

set_style :: proc(commands: ^Commands, style: Style) {
	commands.style = style
	ed.set_style(&commands.input, style.input)
	li.set_style(&commands.list, style.list)
}