// TODO: needs some work
package path

import "core:strings"

when ODIN_OS == .Windows {
	PATH_SEP :: "\\"
}
else {
	PATH_SEP :: "/"
}

shorten :: proc(path: string) -> string {
	return strings.cut(path, strings.last_index(path, PATH_SEP) + 1)
}

join :: proc(paths: []string, aloc := context.allocator) -> string {
	return strings.join(paths, string(PATH_SEP), aloc)
}

parent :: proc(path: string) -> string {
	index := strings.last_index(path, PATH_SEP)
	return strings.cut(path, 0, index)
}