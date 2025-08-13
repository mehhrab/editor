package keymap

import "core:strings"
import rl "vendor:raylib"

Keybind :: struct {
	key: rl.KeyboardKey,
	alt: bool,
	shift: bool,
	control: bool,
}

keybind_init :: proc(
	key: rl.KeyboardKey, 
	alt := false, 
	shift := false, 
	control := false
) -> Keybind {
	return {
		key = key,
		alt = alt,
		shift = shift,
		control = control,
	}
}

check :: proc(keybind: ^Keybind) -> bool {
	return (rl.IsKeyPressed(keybind.key) || rl.IsKeyPressedRepeat(keybind.key)) &&
	rl.IsKeyDown(.LEFT_SHIFT) == keybind.shift &&
	rl.IsKeyDown(.LEFT_ALT) == keybind.alt &&
	rl.IsKeyDown(.LEFT_CONTROL) == keybind.control
}