package find

import rl "vendor:raylib"
import "core:fmt"
import "core:strings"
import buf "../buffer"
import ed "../editor"
import rg "../range"

Find :: struct {
	input: ed.Editor,
	
	text: string,
	
	matches: [dynamic]rg.Range,
	match_index: int,
	
	style: Style,
	visible: bool,
}

Style :: struct {
	active_outline_color: rl.Color,
	input: ed.Style,
}

init :: proc(find: ^Find, style: ^Style) {
	find.style = style^

	buffer: buf.Buffer; buf.init(&buffer, "")
	ed.init(&find.input, &style.input, &buffer, "", "")
}

deinit :: proc(find: ^Find) {
	ed.deinit(&find.input)
	delete(find.matches)
	delete(find.text)
}

calc_matches :: proc(find: ^Find) -> []rg.Range {	
	clear(&find.matches)
	find.match_index = 0

	word := string(find.input.buffer.content[:])
	if word != "" {
		i := 0
		for i < len(find.text) {
			matched := true
			match_start := i
			for w in word {
				char := find.text[i]
				if rune(char) != w {
					matched = false
					break
				}
				i += 1
			}
			if matched {
				range := rg.Range { match_start, i }
				append(&find.matches, range)
			}
			i += 1
		}
	}

	return find.matches[:]
}

next :: proc(find: ^Find) -> (int, rg.Range) {
	index := 0
	range := rg.Range {}
	if len(find.matches) != 0 {		
		index = find.match_index
		range = find.matches[index]
		find.match_index = (find.match_index + 1) % len(find.matches)
	}
	return index, range
}

insert :: proc(find: ^Find, text: string) {
	ed.insert(&find.input, text)
	matches := calc_matches(find)
	// index, range := next(find)
}

draw :: proc(find: ^Find) {
	ed.draw(&find.input)
	rl.DrawRectangleLinesEx(find.input.rect, 1, find.style.active_outline_color)
}

show :: proc(find: ^Find, word := "") {
	find.visible = true

	if word != "" {
		ed.select(&find.input, ed.all(&find.input))
		ed.remove(&find.input)
		ed.insert(&find.input, word)
	}
	ed.select(&find.input, ed.all(&find.input))
}

hide :: proc(find: ^Find) {
	find.visible = false
}

set_text :: proc(find: ^Find, text: string) {
	delete(find.text)
	find.text = strings.clone(text)
}

set_style :: proc(find: ^Find, style: Style) {
	find.style = style
	ed.set_style(&find.input, style.input)
}