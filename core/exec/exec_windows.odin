//+build windows
//+private
package exec

import "core:os"
import "core:mem"
import "core:strings"
import "core:path/filepath"
import "core:sys/windows"

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

_spawn :: proc(process_path: string, arguments: []string, options := Options {}) -> (_p: Process, _err: Spawn_Error) {
	process: Process
    sb := strings.builder_make(0, 1024, context.temp_allocator)
    strings.write_string(&sb, "\"")
    strings.write_string(&sb, process_path)
    strings.write_string(&sb, "\"")
    for arg in arguments {
        strings.write_string(&sb, " ")
        strings.write_string(&sb, arg)
    }
    sa := windows.SECURITY_ATTRIBUTES {
        nLength = size_of(windows.SECURITY_ATTRIBUTES),
        bInheritHandle = true,
    }
    startup_info: windows.STARTUPINFOW = {
        cb = size_of(windows.STARTUPINFOW),
        hStdInput = windows.GetStdHandle(windows.STD_INPUT_HANDLE),
        hStdOutput = windows.GetStdHandle(windows.STD_OUTPUT_HANDLE),
        hStdError = windows.GetStdHandle(windows.STD_ERROR_HANDLE),
        dwFlags = windows.STARTF_USESTDHANDLES,
    }
    process_info: windows.PROCESS_INFORMATION

    has_process := bool(windows.CreateProcessW(
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
    if ! has_process {
        return {}, Exec_Error{ "Failed to create process" }
    }
    process.pid = {
        handle = os.Handle(process_info.hProcess),
        handleThread = os.Handle(process_info.hThread)
    }

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
}

_read_handles_into_builders :: proc(handles: []_Builder_And_Handle) {
}
