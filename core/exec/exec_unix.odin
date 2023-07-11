//+build linux, darwin, freebsd, openbsd
//+private
package exec

import "core:c"
import "core:os"
import "core:fmt"
import "core:mem"
import "core:strings"
import "core:path/filepath"

@(private="file")
pid_t :: distinct c.int
#assert(size_of(pid_t) <= size_of(uintptr))
#assert(size_of(c.int) <= size_of(os.Handle))

@(private="file")
NCCS :: 20
@(private="file")
tcflag_t :: distinct c.ulong
@(private="file")
cc_t :: distinct c.uchar
@(private="file")
speed_t :: distinct c.ulong

@(private="file")
termios :: struct {
	c_iflag: tcflag_t,
	c_oflag: tcflag_t,
	c_cflag: tcflag_t,
	c_lflag: tcflag_t,
	c_cc: [NCCS]cc_t,
	c_ispeed: speed_t,
	c_ospeed: speed_t,
}

@(private="file")
winsize :: struct {
	ws_row: c.ushort,
	ws_col: c.ushort,
	ws_xpixel: c.ushort,
	ws_ypixel: c.ushort,
}

when ODIN_OS == .Darwin {
	foreign import libc "System.framework"
	foreign libc {
		@(link_name="fork") _fork :: proc() -> pid_t ---
		@(link_name="close") _close :: proc(filedes: c.int) -> c.int ---
		@(link_name="pipe") _pipe :: proc(filedes: [^]c.int) -> c.int ---
		@(link_name="execv") _execv :: proc(file: cstring, argv: [^]cstring) -> c.int ---
		@(link_name="waitpid") _waitpid :: proc(pid: pid_t, stat_loc: ^c.int, options: c.int) -> pid_t ---
		@(link_name="dup2") _dup2 :: proc(filedes: c.int, filedes2: c.int) -> c.int ---
		@(link_name="forkpty") _forkpty :: proc(amaster: ^c.int, name: cstring, termios: ^termios, winsize: ^winsize) -> pid_t ---
	}
} else {
	#assert(false, "Platform is not supported")
}

_spawn :: proc(process_path: string, arguments: []string, options := Options {}) -> (_p: Process, _err: Spawn_Error) {
	process: Process
	pid: pid_t

	READ :: 0
	WRITE :: 1
	pipe_stdout: [2]c.int = { -1, -1 }
	pipe_stderr: [2]c.int = { -1, -1 }
	pipe_stdin: [2]c.int = { -1, -1 }

	c_args := make([]cstring, len(arguments) + 2, context.temp_allocator) or_return
	c_args[0] = strings.clone_to_cstring(process_path, context.temp_allocator) or_return
	for arg, idx in arguments {
		c_args[idx + 1] = strings.clone_to_cstring(arg, context.temp_allocator) or_return
	}

	if options.virtual_terminal {
		// TODO: add user options for the virtual terminal
		pid = _forkpty(auto_cast &pipe_stdout, nil, nil, nil)
	} else {
		if options.stdout == .Pipe do _pipe(raw_data(&pipe_stdout))
		if options.stderr == .Pipe do _pipe(raw_data(&pipe_stderr))
		if options.stdin == .Pipe do _pipe(raw_data(&pipe_stdin))
		pid = _fork()
	}

	_null_fd :: proc() -> c.int {
		@(static) got_fd: bool
		@(static) fd: c.int
		if ! got_fd {
			got_fd = true
			handle, err := os.open("/dev/null", os.O_WRONLY); if err != os.ERROR_NONE {
				fmt.eprintf("Could not open /dev/null. %v", os.get_last_error_string())
			}
			fd = auto_cast(handle)
		}
		return fd
	}

	_safe_dup_pipe :: proc(pipe_fd: c.int, pipe_fd2: c.int) {
		assert(pipe_fd2 >= 0)
		if pipe_fd >= 0 {
			_dup2(pipe_fd, pipe_fd2)
		}
	}

	switch pid {
	case -1: // failure
		_close(pipe_stdout[WRITE])
		_close(pipe_stderr[WRITE])
		_close(pipe_stdin[WRITE])
		_close(pipe_stdout[READ])
		_close(pipe_stderr[READ])
		_close(pipe_stdin[READ])

		return {}, Exec_Error{ "Failed to fork" }
	case 0: // child
		// NOTE: we perform the silent as a child since the parent then doesn't need to close anything
		if options.stdout == .Nil do pipe_stdout[WRITE] = _null_fd()
		if options.stderr == .Nil do pipe_stderr[WRITE] = _null_fd()
		if options.stdin == .Nil do pipe_stdin[READ] = _null_fd()

		_close(pipe_stdout[READ])
		_close(pipe_stderr[READ])
		_close(pipe_stdin[WRITE])

		_safe_dup_pipe(pipe_stdout[WRITE], auto_cast os.stdout)
		_safe_dup_pipe(pipe_stderr[WRITE], auto_cast os.stderr)
		_safe_dup_pipe(pipe_stdin[READ], auto_cast os.stdin)

		_execv(c_args[0], raw_data(c_args))
		error_code := os.get_last_error()
		fmt.eprintf("Failed to exec %v. %v\n", c_args[0], os.get_last_error_string())
		// NOTE: if we reach here then exec failed exit with our error code, os will cleanup handles
		os.exit(error_code)
	case: // parent
		assert(pid > 0)
		_close(pipe_stdout[WRITE])
		_close(pipe_stderr[WRITE])
		_close(pipe_stdin[READ])

		process.stdout = auto_cast pipe_stdout[READ]
		process.stderr = auto_cast pipe_stderr[READ]
		process.stdin = auto_cast pipe_stdin[WRITE]
		process.pid = { handle = auto_cast pid, virtual_terminal_handle = options.virtual_terminal }
	}
	assert(pid != 0)
	return process, {}
}

_wait :: proc(process: Process) -> int {
	if process.pid.handle <= 0 {
		return 255
	}
	_get_exit_code :: proc(code: c.int) -> int {
		return code & 0o177 == 0 ? int(code >> 8) & 0xFF : int(code)
	}

	status: c.int
	_waitpid(auto_cast process.pid.handle, &status, 0)
	return _get_exit_code(status)
}

_delete :: proc(process: Process) {
	assert(process.pid.handle > 0)
	_close(auto_cast process.stdout)
	_close(auto_cast process.stderr)
	_close(auto_cast process.stdin)
}

_nil_pipe :: proc() -> os.Handle {
	return -1
}

_find :: proc(executable_name: string, allocator: mem.Allocator) -> (string, bool) {
    path := os.get_env("PATH", context.temp_allocator)
    found_path: string
    _check_if_exists :: proc(folder: string, file: string, allocator: mem.Allocator) -> string {
		if folder == "" {
			return ""
		}
        look_for_path_to_search := filepath.join({ folder, file }, context.temp_allocator)
		stat, err := os.stat(look_for_path_to_search); if err != os.ERROR_NONE {
			return {}
		}
		if stat.is_dir {
			return {}
		}
		if stat.mode & os.S_IXUSR == 0 {
			return {}
		}
        return strings.clone(look_for_path_to_search, allocator)
    }

    if strings.has_prefix(executable_name, "./") {
        found_path = _check_if_exists(os.get_current_directory(), executable_name, allocator)
    }

	if found_path == "" {
		for folder in strings.split_by_byte_iterator(&path, ':') {
			found_path = _check_if_exists(folder, executable_name, allocator)
			if found_path != "" {
				break
			}
		}
	}

    return found_path, found_path != ""
}
