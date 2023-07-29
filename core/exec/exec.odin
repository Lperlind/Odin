package exec

import "core:os"
import "core:mem"
import "core:strings"
import "core:intrinsics"
import "core:slice"

Process_Handle :: struct {
	handle: os.Handle,
	// NOTE: this is required by windows as we need to close this handle
	handleThread: os.Handle,
}

Process :: struct {
	pid: Process_Handle,
	stdout: os.Handle,
	stderr: os.Handle,
	stdin: os.Handle,
}

Handle_Behaviour :: enum {
	Inherit = 0, // zii behaviour
	Pipe,
	Nil,
}
Options :: struct {
	stdout: Handle_Behaviour,
	stderr: Handle_Behaviour,
	stdin: Handle_Behaviour,

	virtual_terminal: bool,
}

Error_Code :: int
Exec_Error :: struct {
	message: string,
}

Spawn_Error :: union {
	mem.Allocator_Error,
	Exec_Error,
}
spawn :: proc(process_path: string, arguments: []string, options := Options {}) -> (Process, Spawn_Error) {
	if process_path == "" {
		return {}, Exec_Error { "process_path is empty" }
	}
	return _spawn(process_path, arguments, options)
}

wait :: proc(process: Process) -> Error_Code {
	if process.pid.handle <= 0 {
		panic("Process has not been created with a valid handle")
	}
	exit_code := _wait(process)
	// delete(process)
	return exit_code
}

delete :: proc(process: Process) {
	if process.pid.handle <= 0 {
		panic("Process has not been created with a valid handle")
	}
	_delete(process)
}

Run_Error :: intrinsics.type_merge(Spawn_Error, union { Error_Code })

@(private)
_Builder_And_Handle :: struct {
	handle: os.Handle,
	sb: ^strings.Builder,
}

Run_Result :: struct {
	stdout: string,
	stderr: string,
}
run :: proc(process_path: string, arguments: []string = {}, options := Options {}) -> (Run_Result, Run_Error) {
	if options.stdin == .Pipe do panic("Cannot use .Pipe with stdin")

	process, err := spawn(process_path, arguments, options); if err != nil {
		switch e in err {
		case Exec_Error: return {}, e
		case mem.Allocator_Error: return {}, e
		}
	}
	defer delete(process)

	sb_out: strings.Builder
	sb_err: strings.Builder

	possible_handles_backing: [2]_Builder_And_Handle
	possible_handles := slice.into_dynamic(possible_handles_backing[:])
	if process.stdout != os.INVALID_HANDLE {
		_, err := append(&possible_handles, _Builder_And_Handle { handle = process.stdout, sb = &sb_out })
		assert(err == nil)
	}
	if process.stderr != os.INVALID_HANDLE {
		_, err := append(&possible_handles, _Builder_And_Handle { handle = process.stderr, sb = &sb_err })
		assert(err == nil)
	}

	_read_handles_into_builders(possible_handles[:])

	res: Run_Result = {
		stdout = strings.to_string(sb_out),
		stderr = strings.to_string(sb_err),
	}

	exit_code := wait(process)
	return res, exit_code == 0 ? nil : exit_code
}

find :: proc(executable_name: string, allocator := context.allocator) -> (string, bool) #optional_ok {
	return _find(executable_name, allocator)
}
