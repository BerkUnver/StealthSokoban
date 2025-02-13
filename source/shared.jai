// These are the type definitions shared between the os-specific main
// and the game itself. Please keep the stuff in this file to a minimum.

BACKGROUND_R :: 12;
BACKGROUND_G :: 27;
BACKGROUND_B :: 19;

INNER_WINDOW_W :: 1920;
INNER_WINDOW_H :: 1080;

GAME_MEMORY_SIZE :: 1 << 24; // @TODO: See how much of this memory is actually used!
LEVEL_ARENA_SIZE :: 1 << 24;
FRAME_ARENA_SIZE :: 1 << 20;

Game_Init_Data :: struct {
    game_memory: *void;
    gl_extension_loader: (*u8) -> *void #c_call;
    os_print: (string);
    read_file: (string, [] u8) -> bool, int;
    level_arena_memory: *void;
    frame_arena_memory: *void;
}

Game_Init_Proc :: #type (init: *Game_Init_Data) #no_context;

Game_Update :: #type (
    game_memory: *void,
    input: *Input,
    time_elapsed: float64
) #no_context;


Input :: struct {
    EVENT_COUNT :: 64;
    events: *Fixed_Array(EVENT_COUNT, Input_Event); // This is stored by the OS

    // In the range (-1, 1) for the x and y axis of the window. Maybe this is a mistake?
    mouse_x: float;
    mouse_y: float;
}


Input_Event :: struct {
    key: Key; // Do we want to pack the "down" into these bits?
    down: bool; // Up or down?
}


Key :: enum {
    // @TODO: Fill in the rest of these.
    // A - Z: Ascii 'A' - 'Z' 
    // 0 - 9: Ascii '0' - '9'
    // Space: Ascii ' '
    MOUSE_LEFT_BUTTON :: 256;
    MOUSE_RIGHT_BUTTON;
    F_BASE :: MOUSE_RIGHT_BUTTON;
    F12 :: F_BASE + 12;
    LEFT_ARROW;
    RIGHT_ARROW;
    DOWN_ARROW;
    UP_ARROW;
    BACKSPACE;
    DELETE;
    TILDE;
}


Fixed_Array :: struct (n: s64, $T: Type) {
    count: s64;
    data: [n] T = ---;
}


append :: (using array: *Fixed_Array($N, $T), item: T) -> bool {
    if count == N return false;
    data[count] = item;
    count += 1;
    return true;
}


append :: (using array: *Fixed_Array($N, $T)) -> *T {
    if count == N return null;
    ptr := *data[count];
    count += 1;
    return ptr;
}


pop :: (using array: *Fixed_Array($N, $T)) -> T {
    count -= 1;
    return data[count];
    // If count is zero and it gets deincremented the data[count] bounds check will fail
    // So we don't need to do the manual bounds check.
}


append_many :: (using array: *Fixed_Array($N, $T), how_many: s64) -> *T {
    if count + how_many > N return null;
    ptr := *data[count];
    count += how_many;
    return ptr;
}


contains :: (using array: *Fixed_Array($N, $T), item: T) -> bool {
    for array {
        if it == item return true;
    }
    return false;
}


to_array :: (a: Fixed_Array($N, $T)) -> [] T {
    return .{N, a.data.data};
}


operator [] :: (using array: Fixed_Array($N, $T), index: s64) -> T {
    assert(0 <= index && index < array.count);
    return array.data[index];
}


for_expansion :: (array: *Fixed_Array($N, $T), body: Code, flags: For_Flags) #expand {
    remove_element :: (array: *Fixed_Array($N, $T), index: int) {
        array.count -= 1;
        if index != array.count {
            array.data[index] = array.data[array.count];
        }
    }

    #assert(!(flags & .REVERSE));
    for `it_index: 0..array.count-1 {
        #if flags & .POINTER {
            `it := *array.data[it_index];
        } else {
            `it := array.data[it_index];
        }

        #insert(remove=remove_element(array, it_index)) body;
    }
}



assert :: (condition: bool, message := "", loc := #caller_location) #no_debug #expand {
    // if !message message = "We've detected an error occuring in the game. This is almost definitely our fault. To prevent corruption, the game will crash now.";
    // @TODO: Open a user-level windows MessageBoxA that contains the message in release builds. Telemetry?

    // @Copypasta from modules/Basic
    assert_stack_trace :: (message: string, loc: Source_Code_Location) -> bool {
        if context.handling_assertion_failure  return false;  // Avoid infinite loops.
        context.handling_assertion_failure = true;

        // We provide 'loc' in case _STACK_TRACE is turned off, but assertion_failed may well
        // look at the stack trace if it is available.
        should_break := context.assertion_failed(loc, message);
        context.handling_assertion_failure = false;
        return true;
    }

    if !condition && assert_stack_trace(message, loc) debug_break();
}

format_print :: (buffer: string, s: string, args: ..Any) -> string, remaining: string {
    buffer_index := 0;
    arg_index := 0;
    
    expand_to_s64 :: (value: *void, info: *Type_Info) -> s64 {
        check :: (T: Type) #expand {
            if `info == type_info(T) `return xx cast(*T, `value).*;
        }

        check(s8);
        check(u8);
        check(s16);
        check(u16);
        check(s32);
        check(u32);
        check(s64);

        assert(false);
        return 0;
    }

    print_string :: (buffer: string, index: int, str: string) -> new_index: int {
        assert(index + str.count < buffer.count);
        memcpy(buffer.data + index, str.data, str.count);
        return index + str.count;
    }

    for 0..s.count-1 {
        if s[it] == #char "%" {
            assert(arg_index < args.count);
            arg := args[arg_index];
            
            if arg.type == type_info(string) {
                arg_str := cast(*string, arg.value_pointer).*;
                buffer_index = print_string(buffer, buffer_index, arg_str);
            } else if arg.type.type == .INTEGER {
                negative: bool;
                arg_u64: u64;

                if arg.type == type_info(u64) {
                    arg_u64 = cast(*u64, arg.value_pointer).*;
                } else {
                    arg_s64 := expand_to_s64(arg.value_pointer, arg.type);
                    if arg_s64 < 0 {
                        negative = true;
                        arg_u64 = xx -arg_s64;
                    } else {
                        arg_u64 = xx arg_s64;
                    }
                }

                if arg_u64 == 0 {
                    assert(buffer_index < buffer.count);
                    buffer[buffer_index] = #char "0";
                    buffer_index += 1;
                } else {
                    if negative {
                        assert(buffer_index < buffer.count);
                        buffer[buffer_index] = #char "-";
                        buffer_index += 1;
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
            } else if arg.type == type_info(bool) {
                arg_bool := cast(*bool, arg.value_pointer).*;
                str := ifx arg_bool "true" else "false";
                buffer_index = print_string(buffer, buffer_index, str);
            } else if arg.type.type == .ENUM {
                info := cast(*Type_Info_Enum, arg.type);
                // @TODO: Figure out how u64 enums work (info.values type is [] s64)
                arg_s64 := expand_to_s64(arg.value_pointer, info.internal_type);
                found := false;
                for info.values {
                    if it == arg_s64 {
                        str := info.names[it_index];
                        buffer_index = print_string(buffer, buffer_index, str);
                        found = true;
                        break;
                    }
                }
                assert(found); // @TODO: Print "(Type_Name) value" or something like that.
            }
            arg_index += 1;
        } else {
            assert(buffer_index < buffer.count);
            buffer[buffer_index] = s[it];
            buffer_index += 1;
        }
    }
    assert(arg_index == args.count);
    return .{buffer_index, buffer.data}, .{buffer.count - buffer_index, buffer.data + buffer_index};
}
