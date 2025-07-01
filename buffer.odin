package editor

import rl "vendor:raylib"
import fmt "core:fmt"
import "core:strings"
import "core:slice"

Buffer :: struct {
	content: [dynamic]byte,
	line_ranges: [dynamic]Range,
}

buffer_init :: proc(buffer: ^Buffer, text := "") {
	new_text, _ := strings.replace_all(text, "\r", "", context.temp_allocator)
	new_text, _ = strings.replace_all(new_text, "\t", "    ", context.temp_allocator)
	append(&buffer.content, new_text) 
	buffer_calc_line_ranges(buffer)
}

buffer_deinit :: proc(buffer: ^Buffer) {
	delete(buffer.content)
	delete(buffer.line_ranges)
}

buffer_calc_line_ranges :: proc(buffer: ^Buffer) {
	clear(&buffer.line_ranges)
	line_range := Range {}
	for c, i in buffer.content {
		if c == '\n' {
			line_range.end = i
			append(&buffer.line_ranges, line_range)
			line_range.start = i + 1
		}
	}
	line_range.end = len(buffer.content)
	append(&buffer.line_ranges, line_range)
}