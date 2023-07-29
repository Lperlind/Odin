package test_core_exec_echo

import "core:fmt"

main :: proc() {
    fmt.println("hello stdout")
    fmt.eprintln("hello stderr")
}

