package test_core_exec

import "core:exec"
import "core:testing"

when ODIN_TEST {
	expect  :: testing.expect
	log     :: testing.log
} else {
	expect  :: proc(t: ^testing.T, condition: bool, message: string, loc := #caller_location) {
		TEST_count += 1
		if !condition {
			TEST_fail += 1
			fmt.printf("[%v] %v\n", loc, message)
			return
		}
	}
	log     :: proc(t: ^testing.T, v: any, loc := #caller_location) {
		fmt.printf("[%v] ", loc)
		fmt.printf("log: %v\n", v)
	}
}

main :: proc() {
	t := testing.T{}
	test_build_echo(&t)
}

@test
test_build_echo :: proc(t: ^testing.T) {
    exec.run(exec.find("odin"), { "build", "echo" })
    exec.run(exec.find("./echo"), options = { stderr = .Nil })
}



