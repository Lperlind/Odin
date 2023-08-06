//+build windows
//+private
package exec

import "core:os"
import "core:fmt"
import "core:mem"
import "core:strings"
import "core:path/filepath"
import "core:sys/windows"
import "core:time"

_find :: proc(executable_name: string, allocator: mem.Allocator) -> (string, bool) {
    executable_name := executable_name
    if filepath.ext(executable_name) != ".exe" {
        executable_name = strings.concatenate({ executable_name, ".exe" }, context.temp_allocator)
    }
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
        return strings.clone(look_for_path_to_search, allocator)
    }

    if strings.has_prefix(executable_name, "./") {
        found_path = _check_if_exists(os.get_current_directory(), executable_name, allocator)
    } else {
		for folder in strings.split_by_byte_iterator(&path, ';') {
			found_path = _check_if_exists(folder, executable_name, allocator)
			if found_path != "" {
				break
			}
		}
	}

    return found_path, found_path != ""
}

_close_pipe :: proc(pipe: windows.HANDLE) {
    if pipe != windows.INVALID_HANDLE_VALUE {
        windows.CloseHandle(pipe)
    }
}

_spawn :: proc(process_path: string, arguments: []string, options := Options {}) -> (_p: Process, _err: Spawn_Error) {
	process: Process
    sb := strings.builder_make(0, 1024, context.temp_allocator) or_return
    _write_into_builder :: proc(sb: ^strings.Builder, s: string) -> mem.Allocator_Error {
        n := strings.write_string(sb, s)
        return n == len(s) ? {} : .Out_Of_Memory
    }
    _write_into_builder(&sb, "\"") or_return
    _write_into_builder(&sb, process_path) or_return
    _write_into_builder(&sb, "\"") or_return
    for arg in arguments {
        _write_into_builder(&sb, " ") or_return
        _write_into_builder(&sb, arg) or_return
    }
	READ :: 0
	WRITE :: 1
    _get_handle_for_type :: proc(behaviour: Handle_Behaviour, pipe_size: int, inherit_pipe: windows.HANDLE, inherit_index: int) -> ([2]windows.HANDLE, Spawn_Error) {
        pipes: [2]windows.HANDLE = { windows.INVALID_HANDLE_VALUE, windows.INVALID_HANDLE_VALUE }
        switch behaviour {
        case .Inherit: pipes[inherit_index] = inherit_pipe
        case .Pipe:
            sa := windows.SECURITY_ATTRIBUTES {
                nLength = size_of(windows.SECURITY_ATTRIBUTES),
                bInheritHandle = true,
            }
            if ! windows.CreatePipe(&pipes[READ], &pipes[WRITE], &sa, u32(pipe_size)) {
                return {}, Exec_Error { "Failed to pipe" }
            }
        case .Nil: // do nothing
        }
        return pipes, {}
    }
    stdin := _get_handle_for_type(options.stdin, options.pipe_size, auto_cast os.stdin, READ) or_return
    stdout := _get_handle_for_type(options.stdout, options.pipe_size, auto_cast os.stdout, WRITE) or_return
    stderr := _get_handle_for_type(options.stderr, options.pipe_size, auto_cast os.stderr, WRITE) or_return
    // Prevent our handles from being written/read
    if stdin[WRITE] != windows.INVALID_HANDLE_VALUE {
        windows.SetHandleInformation(stdin[WRITE], windows.HANDLE_FLAG_INHERIT, 0)
    }
    if stdout[READ] != windows.INVALID_HANDLE_VALUE {
        windows.SetHandleInformation(stdout[READ], windows.HANDLE_FLAG_INHERIT, 0)
    }
    if stderr[READ] != windows.INVALID_HANDLE_VALUE {
        windows.SetHandleInformation(stderr[READ], windows.HANDLE_FLAG_INHERIT, 0)
    }
    did_spawn: bool
    defer {
        if options.stdin != .Inherit {
            _close_pipe(stdin[READ])
        }
        if options.stdout != .Inherit {
            _close_pipe(stdout[WRITE])
        }
        if options.stderr != .Inherit {
            _close_pipe(stderr[WRITE])
        }
        if ! did_spawn {
            _close_pipe(stdin[WRITE])
            _close_pipe(stdout[READ])
            _close_pipe(stderr[READ])
        }
    }

    startup_info := windows.STARTUPINFOW {
        cb = size_of(windows.STARTUPINFOW),
        hStdInput = stdin[READ],
        hStdOutput = stdout[WRITE],
        hStdError = stderr[WRITE],
        dwFlags = windows.STARTF_USESTDHANDLES,
    }
    process_info: windows.PROCESS_INFORMATION
    did_spawn = bool(windows.CreateProcessW(
        lpApplicationName = nil,
        lpCommandLine = windows.utf8_to_wstring(strings.to_string(sb), context.temp_allocator),
        lpProcessAttributes = nil,
        lpThreadAttributes = nil,
        bInheritHandles = true,
        dwCreationFlags = 0,
        lpEnvironment = nil,
        lpCurrentDirectory = nil,
        lpStartupInfo = &startup_info,
        lpProcessInformation = &process_info,
    ))
    if ! did_spawn {
        return {}, Exec_Error{ "Failed to create process" }
    }
    process.pid = {
        handle = os.Handle(process_info.hProcess),
        handleThread = os.Handle(process_info.hThread)
    }

    process.stdin = auto_cast stdin[WRITE]
    process.stdout = auto_cast stdout[READ]
    process.stderr = auto_cast stderr[READ]

    return process, {}
}

_wait :: proc(process: Process) -> int {
	windows.WaitForSingleObject(auto_cast process.pid.handle, windows.INFINITE)
	exit_code: windows.DWORD
	if ! windows.GetExitCodeProcess(auto_cast process.pid.handle, &exit_code) {
		exit_code = 1
	}
	return int(exit_code)
}

_delete :: proc(process: Process) {
    windows.CloseHandle(auto_cast process.pid.handle)
    windows.CloseHandle(auto_cast process.pid.handleThread)
    _close_pipe(auto_cast process.stdin)
    _close_pipe(auto_cast process.stderr)
    _close_pipe(auto_cast process.stdout)
}

_read_handles_into_builders :: proc(handles: []_Builder_And_Handle) {
    handles := handles
    if len(handles) == 0 {
        return
    }

    for _, i in handles {
        no_wait := windows.PIPE_NOWAIT
        if ! windows.SetNamedPipeHandleState(auto_cast handles[i].handle, &no_wait, nil, nil) {
            fmt.panicf("Failed to set windows pipe: %v", windows.GetLastError())
        }

    }

    read_buffer: [512]byte
    for len(handles) > 0 {
        // Asynchronous (overlapped) read and write operations are not supported by anonymous pipes.
        // very lame windows, just sleep and read I guess? Or we could spawn threads
        bytes_read: windows.DWORD
        for i := 0; i < len(handles); {
            for {
                ok := windows.ReadFile(
                    auto_cast handles[i].handle,
                    raw_data(&read_buffer),
                    len(read_buffer),
                    &bytes_read,
                    nil,
                )
                if ok {
                    strings.write_string(handles[i].sb, string(read_buffer[:bytes_read]))
                } else {
                    if windows.GetLastError() != windows.ERROR_NO_DATA {
                        len_minus_one := len(handles) - 1
                        handles[i] = handles[len_minus_one]
                        handles = handles[:len_minus_one]
                    }
                    else {
                        i += 1
                    }
                    break
                }
            }
        }
        time.sleep(time.Millisecond)
    }
}
