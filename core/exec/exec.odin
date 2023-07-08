package exec

import "core:os"
import "core:mem"
import "core:strings"

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

Process_Error :: enum {
	Fork_Failed,
}

Error_Code :: int
Run_Process_Error :: union {
	mem.Allocator_Error,
	Process_Error,
	Error_Code,
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
run :: proc(process_path: string, arguments: []string, options := Options {}) -> (Process, Run_Process_Error) {
	return _run(process_path, arguments, options)
}

wait :: proc(process: Process) -> int {
	if process.pid.handle <= 0 {
		panic("Process has not been created with a valid handle")
	}
	exit_code := _wait(process)
	return exit_code
}

delete :: proc(process: ^Process) {
	assert(process != nil)
	if process.pid.handle <= 0 {
		panic("Process has not been created with a valid handle")
	}
	_delete(process^)
	process.pid = {}
	process.stdout = os.INVALID_HANDLE
	process.stderr = os.INVALID_HANDLE
	process.stdin = os.INVALID_HANDLE
}

run_and_get_stdout :: proc(process_path: string, arguments: []string, options := Options {}) -> (output: string, err: Run_Process_Error) {
	options := options
	options.stdout = .Pipe
	process := run(process_path, arguments, options) or_return
	defer delete(&process)

	sb: strings.Builder
	temp_buffer: [512]byte
	for {
		bytes_read, err := os.read(process.stdout, temp_buffer[:])
		if err != os.ERROR_NONE || bytes_read == 0 {
			break
		}
		strings.write_string(&sb, string(temp_buffer[:bytes_read]))
	}

	exit_code := wait(process)
	return strings.to_string(sb), exit_code == 0 ? nil : exit_code
}

run_and_wait :: proc(process_path: string, arguments: []string, options := Options {}) -> Run_Process_Error {
	if options.stdout == .Pipe do panic("Cannot use .Pipe")
	if options.stderr == .Pipe do panic("Cannot use .Pipe")
	if options.stdin == .Pipe do panic("Cannot use .Pipe")

	process := run(process_path, arguments, options) or_return
	defer delete(&process)
	exit_code := wait(process)
	return exit_code == 0 ? nil : exit_code
}
