package editor

import rl "vendor:raylib"

Theme :: struct {
	bg: rl.Color,
	bg_dim: rl.Color,
	text: rl.Color,
	text2: rl.Color,
	caret: rl.Color,
	selection: rl.Color,
	highlight: rl.Color,
	using syntax: Syntax,
}

Syntax :: struct {
	symbol: rl.Color,
	number: rl.Color,
	sstring: rl.Color,
	comment: rl.Color,	
	default: rl.Color,
}

THEME_DEFAULT :: Theme {
	bg = { 50, 50, 50, 255 },
	bg_dim = { 20, 20, 20, 255 },
	text = rl.WHITE,
	text2 = rl.GRAY,
	selection = { 80, 80, 80, 255 },
	caret = rl.SKYBLUE,
	highlight = { 255, 255, 255, 15 },
	syntax = {
		default = rl.SKYBLUE,
		symbol = rl.WHITE,
		sstring = rl.GREEN,
		comment = rl.DARKGREEN,
		number = rl.PINK,
	},
}