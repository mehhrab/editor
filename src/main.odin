package main

import os "core:os/os2"
import "app"

main :: proc() {
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	state: app.App
	// TODO: softcode this
	config := app.Config {
		font_path = "res\\FiraCode-Regular.ttf",
		font_size = 40,
		keybinds = app.keybinds_default(),
		theme = app.THEME_DEFAULT,
		syntax = app.SYNTAX_DEFAULT,
	}

	app.init(&state, &config)
	defer app.deinit(&state)
	
	for arg in os.args[1:] {
		app.open_file(&state, arg)
	}

	app.run(&state)
}