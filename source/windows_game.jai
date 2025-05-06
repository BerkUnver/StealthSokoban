os_print :: (s: string) {
    stdout := GetStdHandle(STD_OUTPUT_HANDLE);
    assert(stdout != INVALID_HANDLE_VALUE);
    WriteConsoleA(stdout, s.data, cast(u32, s.count), null, null);
    FlushFileBuffers(stdout); 
    // This function is for debug output. We don't care about performance, so we flush every time we call this.
}


set_console_text_color :: (color: Console_Text_Color) {
    stdout := GetStdHandle(STD_OUTPUT_HANDLE);
    assert(stdout != INVALID_HANDLE_VALUE);
    if #complete color == {
        case .WHITE; SetConsoleTextAttribute(stdout, FOREGROUND_RED | FOREGROUND_GREEN | FOREGROUND_BLUE);
        case .RED;   SetConsoleTextAttribute(stdout, FOREGROUND_RED);
        case .GREEN; SetConsoleTextAttribute(stdout, FOREGROUND_GREEN);
    }
}


read_file :: (name: string, arena: *Memory_Arena) -> bool, string {
    using context.game_context;

    mark := get_mark(frame_arena);
    path := jai_string_to_path(name, frame_arena);
    handle := CreateFileA(path, FILE_GENERIC_READ);
    restore_mark(frame_arena, mark);

    if handle == INVALID_HANDLE_VALUE return false, .{};
    defer CloseHandle(handle);

    size_l: LARGE_INTEGER;
    assert(GetFileSizeEx(handle, *size_l) != 0);
    assert(size_l.QuadPart < 0x7fffffff);
    size := cast(u32, size_l.QuadPart);

    data := alloc(arena, size, zero_init = false);

    read_size: u32;
    ReadFile(handle, data, size, *read_size);
    assert(read_size == size);
    
    return true, .{size, data};
}


write_file :: (name: string, str: string) -> bool {
    using context.game_context;

    mark := get_mark(frame_arena);
    path := jai_string_to_path(name, frame_arena);
    handle := CreateFileA(path, FILE_GENERIC_WRITE, creation = CREATE_ALWAYS);
    restore_mark(frame_arena, mark);

    if handle == INVALID_HANDLE_VALUE return false;
    defer CloseHandle(handle);
    
    bytes_written: u32;
    WriteFile(handle, str.data, xx str.count, *bytes_written, null);
    if bytes_written < str.count return false;

    return true;
}


create_directory :: (name: string) -> bool {
    using context.game_context;

    scope_mark(frame_arena);
    path := jai_string_to_path(name, frame_arena);

    if CreateDirectoryA(path, null) == 0 return true;
    err := GetLastError();
    if err == ERROR_ALREADY_EXISTS return true;
    return false;
}


iterate_directory :: (dir: string, data: *void, func: (*void, string)) -> bool {
    using context.game_context;

    buf: [1024] u8 = ---;
    sb := make_string_builder(buf);
    print(*sb, "%/*", dir);
    str := get_string(*sb);
    
    mark := get_mark(frame_arena);
    path := jai_string_to_path(str, frame_arena);
    find_data: WIN32_FIND_DATAA;
    find_handle := FindFirstFileA(path, *find_data);
    restore_mark(frame_arena, mark);

    if find_handle == INVALID_HANDLE_VALUE return false;

    while true {
        if !jai_string_equals_c_string(".", find_data.cFileName.data)
        && !jai_string_equals_c_string("..", find_data.cFileName.data) 
        // We're not doing recursive iteration for now.
        && !(find_data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) { 
            buf: [1024] u8 = ---;
            sb := make_string_builder(buf);
            print(*sb, "%/%", dir, find_data.cFileName.data);
            str := get_string(*sb);

            func(data, str);
        }
        
        if !FindNextFileA(find_handle, *find_data) break;
    }

    error := GetLastError();
    FindClose(find_handle);

    return error == ERROR_NO_MORE_FILES;
}


get_date :: () -> Date {
    using date: SYSTEMTIME;
    GetSystemTime(*date);

    return .{
        year=wYear,
        month=wMonth,
        day=wDay,
        hour=wHour,
        minute=wMinute,
        second=wSecond,
        millisecond=wMilliseconds
    };
}


enable_cursor :: (enabled: bool) {
    if enabled {
        SetCursor(LoadCursorA(null, IDC_ARROW));
    } else {
        SetCursor(null);
    }
}


#scope_file

#load "windows_winapi.jai";

jai_string_to_path :: (str: string, arena: *Memory_Arena) -> *u8 {
    // @TODO: Maybe we can detect when name is a static string (it is zero-terminated) and skip translating it?
    path := cast(*u8, alloc(arena, str.count + 1, zero_init = false));
    memcpy(path, str.data, str.count);
    path[str.count] = 0;
    return path;
}
