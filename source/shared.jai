// These are the type definitions shared between the os-specific main
// and the game itself. Please keep the stuff in this file to a minimum.

BACKGROUND_R :: 12;
BACKGROUND_G :: 27;
BACKGROUND_B :: 19;

INNER_WINDOW_W :: 1920;
INNER_WINDOW_H :: 1080;

// @TODO: See how much of this memory is actually used!
GAME_MEMORY_SIZE     :: 1 << 24; 
LEVEL_ARENA_SIZE     :: 1 << 24;
PERMANENT_ARENA_SIZE :: 1 << 22;
FRAME_ARENA_SIZE     :: 1 << 20;

OS_Procedures :: struct {
    os_print: (string);
    read_file: (string, [] u8) -> bool, int;
    write_file: (string, string) -> bool;
    set_console_text_color: (Console_Text_Color);
}

Game_Init_Data :: struct {
    game_memory: *void;
    gl_extension_loader: (*u8) -> *void #c_call;
    os_procs: OS_Procedures;
    level_arena_memory: *void;
    frame_arena_memory: *void;
    permanent_arena_memory: *void;
}

Game_Init_Proc :: #type (init: *Game_Init_Data) #no_context;

Game_Update :: #type (
    game_memory: *void,
    input: *Input,
    time_elapsed: float64
) #no_context;


Input :: struct {
    events: [] Input_Event; // Stored by the OS layer

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
    OPENING_CURLY_BRACE;
    CLOSING_CURLY_BRACE;
    TILDE;
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


make_string_builder :: (backing_store: [] u8) -> String_Builder {
    return .{backing_store, 0};
}


String_Builder :: struct {
    buf: [] u8;
    index: int;
}


Console_Text_Color :: enum {
    WHITE;
    RED;
    GREEN;
}


print_string :: (using sb: *String_Builder, str: string) {
    assert(index + str.count < buf.count);
    memcpy(buf.data + index, str.data, str.count);
    index += str.count;
}


print :: (using sb: *String_Builder, s: string, args: ..Any) {
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

    for 0..s.count-1 {
        if s[it] == #char "%" {
            assert(arg_index < args.count);
            arg := args[arg_index];
            
            if arg.type == type_info(string) {
                arg_str := cast(*string, arg.value_pointer).*;
                print_string(sb, arg_str);
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
                    assert(index < buf.count);
                    buf[index] = #char "0";
                    index += 1;
                } else {
                    if negative {
                        assert(index < buf.count);
                        buf[index] = #char "-";
                        index += 1;
                    }
                    
                    divisor: u64 = 1;
                    digit_count := 1;
                    while true {
                        if arg_u64 / divisor < 10 break;
                        divisor *= 10;
                        digit_count += 1;
                    }
                    
                    assert(index + digit_count <= buf.count);

                    remainder := arg_u64;
                    while divisor {
                        buf[index] = cast(u8, #char "0" + remainder / divisor);
                        remainder = remainder % divisor;
                        divisor /= 10;
                        index += 1;
                    }
                }
            } else if arg.type == type_info(bool) {
                arg_bool := cast(*bool, arg.value_pointer).*;
                str := ifx arg_bool "true" else "false";
                print_string(sb, str);
            } else if arg.type.type == .ENUM {
                info := cast(*Type_Info_Enum, arg.type);
                // @TODO: Figure out how u64 enums work (info.values type is [] s64)
                arg_s64 := expand_to_s64(arg.value_pointer, info.internal_type);
                found := false;
                for info.values {
                    if it == arg_s64 {
                        str := info.names[it_index];
                        print_string(sb, str);
                        found = true;
                        break;
                    }
                }
                assert(found); // @TODO: Print "(Type_Name) value" or something like that.
            } else if arg.type.type == .ARRAY {
                info := cast(*Type_Info_Array, arg.type);

                print_array :: (sb: *String_Builder, count: s64, data: *void, type: *Type_Info) {
                    print(sb, "[ ");
                    for 0..count-1 {
                        element_ptr := data + type.runtime_size * it;
                        member_args := Any.[ dynamic_any(type, element_ptr) ];
                        print(sb, "% ", ..member_args);
                    }
                    print(sb, "]");
                }

                if info.array_type == {
                    case .FIXED; assert(false); // @TODO
                    case .VIEW;
                        view := cast(*Array_View_64, arg.value_pointer);
                        print_array(sb, view.count, view.data, info.element_type);

                    case .RESIZABLE;
                        array := cast(*Resizable_Array, arg.value_pointer);
                        print_array(sb, array.count, array.data, info.element_type);
                }
            }
            arg_index += 1;
        } else {
            assert(index < buf.count);
            buf[index] = s[it];
            index += 1;
        }
    }
    assert(arg_index == args.count);
}

get_string :: (using sb: *String_Builder) -> string {
    return .{index, buf.data};
}


dynamic_any :: inline (type: *Type_Info, value_pointer: *void) -> Any {
    any := Any_Struct.{type = type, value_pointer = value_pointer};
    return cast(*Any, *any).*;
}
