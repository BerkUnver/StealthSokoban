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
    previous_current: s64;
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


arena_alloc_array :: (arena: *Memory_Arena, count: s64, $T: Type, $zero_init := true) -> [] T #must {
    assert(count >= 0); // You would think this wouldn't happen but I had a bug here.
    byte_count := ifx count > 0 then size_of(T) * count else 1; 
    // We give it one byte so if we want to extend this allocation and another allocation was made afterwards, it does not overwrite that allocation.
    assert(arena.count - arena.current >= byte_count);
    ret := arena.data + arena.current;
    arena.previous_current = arena.current;
    arena.current += byte_count;
    #if zero_init memset(ret, 0, byte_count);
    return .{data=xx ret, count=count};
}


arena_extend_most_recent_allocation :: (arena: *Memory_Arena, allocation: *u8, new_count: s64, $zero_init := true) {
    assert(cast(s64, allocation - arena.data) == arena.previous_current);
    new_current := arena.previous_current + new_count;
    assert(new_current <= arena.count);
    #if zero_init memset(arena.data + arena.current, 0, new_count - arena.current);
    arena.current = new_current;
}


arena_grow_most_recent_array :: (arena: *Memory_Arena, array: *[] $T, new_count: s64, $zero_init := true) {
    arena_extend_most_recent_allocation(arena, xx array.data, new_count * size_of(T), zero_init);
    array.count = new_count;
}


print :: (s: string, args: ..Any) {
    buf: [4096] u8;
    buf_str := string.{buf.count, buf.data};
    buf_str = format_print(buf_str, s, ..args);
    context.game_context.os_print(buf_str);
}
