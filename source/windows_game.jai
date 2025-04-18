// This is os stuff that the game layer can know about.

read_file :: (name: string, arena: *Memory_Arena) -> bool, string {
    path := jai_string_to_path(name);

    handle := CreateFileA(path.data, FILE_GENERIC_READ);
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
    path := jai_string_to_path(name);

    handle := CreateFileA(path.data, FILE_GENERIC_WRITE, creation = CREATE_ALWAYS);
    if handle == INVALID_HANDLE_VALUE return false;
    defer CloseHandle(handle);
    
    bytes_written: u32;
    WriteFile(handle, str.data, xx str.count, *bytes_written, null);
    if bytes_written < str.count return false;

    return true;
}


create_directory :: (name: string) -> bool {
    path := jai_string_to_path(name);

    if CreateDirectoryA(path.data, null) == 0 return true;
    err := GetLastError();
    if err == ERROR_ALREADY_EXISTS return true;
    return false;
}


iterate_directory :: (dir: string, data: *void, func: (*void, string)) -> bool {
    buf: [1024] u8 = ---;
    sb := make_string_builder(buf);
    print(*sb, "%/*", dir);
    str := get_string(*sb);

    path := jai_string_to_path(str);

    find_data: WIN32_FIND_DATAA;
    find_handle := FindFirstFileA(path.data, *find_data);

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
    if error != ERROR_NO_MORE_FILES {
        log(.ERROR, "Failed to interate through all the files in the directory \"%\"\n", dir);
        FindClose(find_handle);
        return false;
    }

    FindClose(find_handle);
    return true;
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


#scope_file

#load "windows_winapi.jai";

jai_string_to_path :: (str: string) -> [MAX_PATH] u8 {
    // @TODO: Maybe we can detect when name is a static string (it is zero-terminated) and skip translating it?

    path: [MAX_PATH] u8;
    assert(str.count <= MAX_PATH - 1);
    memcpy(path.data, str.data, str.count);
    path[str.count] = 0;
    return path;
}
