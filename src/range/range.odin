package range

Range :: struct {
	start, end: int,
}

point :: proc(pos: int) -> Range {
	return { pos, pos }
}

length :: proc(range: Range) -> int {
	return range.end - range.start
}