jai_string_equals_c_string :: (jai_string: string, c_string: *u8) -> bool {
    for 0..jai_string.count-1 {
        if c_string[it] == #char "\0" return false;
        if c_string[it] != jai_string[it] return false;
    }
    
    if c_string[jai_string.count] != #char "\0" return false;
    return true;
}

Memory_Arena :: struct {
    data: *u8;
    count: s64;
    current: s64;
}

make_arena :: (memory: *u8, count: s64) -> Memory_Arena {
    return .{
        data = memory,
        count = count,
        current = 0
    };
}


clear_arena :: inline (arena: *Memory_Arena) {
    arena.current = 0;
}


arena_alloc :: (arena: *Memory_Arena, count: s64, zero_init := true) -> *void {
    assert(count >= 0);
    ret := arena.data + arena.current;
    arena.current += count;
    if zero_init memset(ret, 0, count);
    return ret;
}

arena_alloc :: (arena: *Memory_Arena, $T: Type, zero_init := true) -> *T {
    return arena_alloc(arena, size_of(T), zero_init);
}

arena_alloc_array :: (arena: *Memory_Arena, count: s64, $T: Type, zero_init := true) -> [] T #must {
    byte_count := size_of(T) * count; 
    ret := arena_alloc(arena, byte_count, zero_init);
    return .{data=xx ret, count=count};
}


get_mark :: (arena: *Memory_Arena) -> s64 {
    return arena.current;
}


restore_mark :: (arena: *Memory_Arena, marker: s64) {
    assert(arena.current >= marker);
    arena.current = marker;
}



print :: (s: string, args: ..Any) {
    buf: [4096] u8;
    buf_str := string.{buf.count, buf.data};
    buf_str = format_print(buf_str, s, ..args);
    context.game_context.os_print(buf_str);
}
