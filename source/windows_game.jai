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


#scope_file
// @CompileSpeed both the windows exe and the game dll have to load windows_winapi.jai
// This is why headers kill compile time in C++, and we're replicating the problem here.
#load "windows_winapi.jai";

jai_string_to_path :: (str: string) -> [MAX_PATH] u8 {
    // @TODO: Maybe we can detect when name is a static string (it is zero-terminated) and skip translating it?

    path: [MAX_PATH] u8;
    assert(str.count <= MAX_PATH - 1);
    memcpy(path.data, str.data, str.count);
    path[str.count] = 0;
    return path;
}

