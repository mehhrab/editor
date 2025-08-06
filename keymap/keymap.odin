package keymap

import "core:strings"
import rl "vendor:raylib"

// Keymap :: struct {
// 	keybinds: [dynamic]Keybind,
// }

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

// keybind_deinit :: proc(keybind: ^Keybind) {
// 	delete(keybind.name)
// }

check :: proc(keybind: ^Keybind) -> bool {
	return key_pressed(keybind.key) &&
	rl.IsKeyDown(.LEFT_SHIFT) == keybind.shift &&
	rl.IsKeyDown(.LEFT_ALT) == keybind.alt &&
	rl.IsKeyDown(.LEFT_CONTROL) == keybind.control
}

key_pressed :: proc(key: rl.KeyboardKey) -> bool {
	return rl.IsKeyPressed(key) || rl.IsKeyPressedRepeat(key)
}