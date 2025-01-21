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

arena_alloc_array :: (arena: *Memory_Arena, count: s64, $T: Type) -> bool, [] T {
    assert(count >= 0); // You would think this wouldn't happen but I had a bug here.
    byte_count := size_of(T) * count;
    if arena.count - arena.current < byte_count return false, .{};
    ret := arena.data + count;
    arena.current += byte_count;
    return true, .{data=xx ret, count=count};
}

print :: (g: Game, s: string, args: ..Any) {
    buffer: [4096] u8 = ---;
    buffer_index := 0;
    arg_index := 0;
    for 0..s.count-1 {
        if s[it] == #char "%" {
            assert(arg_index < args.count);
            arg := args[arg_index];
            
            if arg.type == type_info(string) {
                arg_str := cast(*string, arg.value_pointer).*;
                assert(buffer_index + arg_str.count < buffer.count);
                memcpy(buffer.data + buffer_index, arg_str.data, arg_str.count);
                buffer_index += arg_str.count;
            } else if arg.type == type_info(s32) {
                arg_s32 := cast(*s32, arg.value_pointer).*;
                if arg_s32 == 0 {
                    assert(buffer_index < buffer.count);
                    buffer[buffer_index] = #char "0";
                    buffer_index += 1;
                } else {
                    arg_u64: u64; // So we can handle the maximum negative value of s32
                    if arg_s32 < 0 {
                        arg_u64 = cast(u64, -cast(s64, arg_s32));
                        assert(buffer_index < buffer.count);
                        buffer[buffer_index] = #char "-";
                        buffer_index += 1;
                    } else {
                        arg_u64 = xx arg_s32;
                    }
                    
                    divisor: u64 = 1;
                    digit_count := 1;
                    while true {
                        if arg_u64 / divisor < 10 break;
                        divisor *= 10;
                        digit_count += 1;
                    }
                    
                    assert(buffer_index + digit_count <= buffer.count);

                    remainder := arg_u64;
                    while divisor {
                        buffer[buffer_index] = cast(u8, #char "0" + remainder / divisor);
                        remainder = remainder % divisor;
                        divisor /= 10;
                        buffer_index += 1;
                    }
                }
            } else assert(false);

            arg_index += 1;
        } else {
            assert(buffer_index < buffer.count);
            buffer[buffer_index] = s[it];
            buffer_index += 1;
        }
    }
    g.debug_print(.{buffer_index, buffer.data});
}
