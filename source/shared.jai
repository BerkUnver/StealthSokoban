// These are the type definitions shared between the os-specific main
// and the game itself. Please keep the stuff in this file to a minimum.

BACKGROUND_R :: 12;
BACKGROUND_G :: 27;
BACKGROUND_B :: 19;

INNER_WINDOW_W :: 1920;
INNER_WINDOW_H :: 1080;

LEVEL_ARENA_SIZE :: 1 << 24;

Game_Init :: #type (
    game_memory: *void,
    game_memory_size: u64,
    gl_extension_loader: (*u8) -> *void #c_call,
    os_print: (string),
    level_arena_memory: *void
) #no_context;

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

operator [] :: (using array: Fixed_Array($N, $T), index: s64) -> T {
    assert(0 <= index && index < array.count);
    return array.data[index];
}

for_expansion :: (array: *Fixed_Array($N, $T), body: Code, flags: For_Flags) #expand {
    #assert(!(flags & .REVERSE));
    for `it_index: 0..array.count-1 {
        #if flags & .POINTER {
            `it := *array.data[it_index];
        } else {
            `it := array.data[it_index];
        }

        #insert body;
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
    for 0..s.count-1 {
        if s[it] == #char "%" {
            assert(arg_index < args.count);
            arg := args[arg_index];
            
            if arg.type == type_info(string) {
                arg_str := cast(*string, arg.value_pointer).*;
                assert(buffer_index + arg_str.count < buffer.count);
                memcpy(buffer.data + buffer_index, arg_str.data, arg_str.count);
                buffer_index += arg_str.count;
            } else if arg.type.type == .INTEGER {
                negative: bool;
                arg_u64: u64;

                if arg.type == type_info(u32) {
                    arg_u64 = xx cast(*u32, arg.value_pointer).*;
                } else if arg.type == type_info(u64) {
                    arg_u64 = cast(*u64, arg.value_pointer).*;
                } else if arg.type == type_info(s32) {
                    arg_s32 := xx cast(*s32, arg.value_pointer).*;
                    if arg_s32 < 0 {
                        arg_u64 = xx -arg_s32;
                        negative = true;
                    } else {
                        arg_u64 = xx arg_s32;
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
            } else assert(false);

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
