package buffer

import "core:fmt"
import "core:strings"
import "core:slice"
import rl "vendor:raylib"
import rg "../range"

Buffer :: struct {
	content: [dynamic]byte,
	line_ranges: [dynamic]rg.Range,
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
	line_range := rg.Range {}
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

insert :: proc(buffer: ^Buffer, pos: int, text: string)  {
	replace(buffer, rg.point(pos), text)
}

remove :: proc(buffer: ^Buffer, range: rg.Range) {
	replace(buffer, range, "")
}

replace :: proc(buffer: ^Buffer, range: rg.Range, text: string) {
	if 1 <= rg.length(range) {
		remove_range(&buffer.content, range.start, range.end)
	}
	if text != "" {
		inject_at_elems(&buffer.content, range.start, ..transmute([]byte)text)
	}
	calc_line_ranges(buffer)
}

content_with_clrf :: proc(buffer: ^Buffer, allocator := context.allocator) -> []byte {
	content, _ := strings.replace_all(string(buffer.content[:]), "\n", "\r\n", context.temp_allocator)
	return transmute([]byte)strings.clone(content, allocator)
}