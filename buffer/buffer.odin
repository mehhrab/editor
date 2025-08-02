package buffer

import rl "vendor:raylib"
import fmt "core:fmt"
import "core:strings"
import "core:slice"
import "../range"

Range :: range.Range

Buffer :: struct {
	content: [dynamic]byte,
	line_ranges: [dynamic]Range,
}

init :: proc(buffer: ^Buffer, text := "") {
	new_text, _ := strings.replace_all(text, "\r", "", context.temp_allocator)
	append(&buffer.content, new_text) 
	calc_line_ranges(buffer)
}

deinit :: proc(buffer: ^Buffer) {
	delete(buffer.content)
	delete(buffer.line_ranges)
}

calc_line_ranges :: proc(buffer: ^Buffer) {
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

content_with_clrf :: proc(buffer: ^Buffer, allocator := context.allocator) -> []byte {
	content, _ := strings.replace_all(string(buffer.content[:]), "\n", "\r\n", context.temp_allocator)
	return transmute([]byte)strings.clone(content, allocator)
}