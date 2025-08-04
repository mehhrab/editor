package main

import rl "vendor:raylib"
import "syntax"

Theme :: struct {
	bg: rl.Color,
	bg2: rl.Color,
	text: rl.Color,
	text2: rl.Color,
	caret: rl.Color,
	selection: rl.Color,
	accent: rl.Color,
	seperator: rl.Color,
	using syntax: syntax.Syntax,
}

THEME_DEFAULT :: Theme {
	bg = { 30, 30, 30, 255 },
	bg2 = { 20, 20, 20, 255 },
	text = rl.WHITE,
	text2 = rl.GRAY,
	selection = { 80, 80, 80, 255 },
	caret = rl.SKYBLUE,
	accent = rl.ORANGE,
	seperator = { 255, 255, 255, 20 },
	syntax = {
		default = rl.SKYBLUE,
		symbol = rl.WHITE,
		sstring = rl.GREEN,
		comment = rl.DARKGREEN,
		number = rl.PINK,
	},
}