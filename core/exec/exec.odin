package exec

import "core:os"
import "core:mem"
import "core:strings"
import "core:intrinsics"

Process_Handle :: struct {
	handle: os.Handle,
	// NOTE: this is required by windows as you wait on threads rather than processes
	// when opening a process via a virtual terminal
	virtual_terminal_handle: bool,
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

Run_Result :: struct {
	stdout: string,
	stderr: string,
}
run :: proc(process_path: string, arguments: []string, options := Options {}) -> (Run_Result, Run_Error) {
	if options.stdin == .Pipe do panic("Cannot use .Pipe")

	process, err := spawn(process_path, arguments, options); if err != nil {
		switch e in err {
		case Exec_Error: return {}, e
		case mem.Allocator_Error: return {}, e
		}
	}
	defer delete(process)

	sb_out: strings.Builder
	sb_err: strings.Builder
	if process.stdout != os.INVALID_HANDLE {
		temp_buffer: [512]byte
		for {
			bytes_read, err := os.read(process.stdout, temp_buffer[:])
			if err != os.ERROR_NONE || bytes_read == 0 {
				break
			}
			strings.write_string(&sb_out, string(temp_buffer[:bytes_read]))
		}
	}
	if process.stderr != os.INVALID_HANDLE {
		panic("Cannot use.pipe with stderr right now")
	}

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
