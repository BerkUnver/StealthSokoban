// These are the type definitions shared between the os-specific main
// and the game itself. Please keep the stuff in this file to a minimum.

BACKGROUND_R :: 12;
BACKGROUND_G :: 27;
BACKGROUND_B :: 19;

INNER_WINDOW_W :: 2560;
INNER_WINDOW_H :: 1600;

// INNER_WINDOW_W :: 1920;
// INNER_WINDOW_H :: 1080;

MAX_INPUT_EVENTS_PER_TICK :: 64;

// @TODO: See how much of this memory is actually used!
GAME_MEMORY_SIZE     :: 1 << 24; 
EDITOR_ARENA_SIZE    :: 1 << 27;
GAMEPLAY_ARENA_SIZE  :: 1 << 24;
PERMANENT_ARENA_SIZE :: 1 << 22;
FRAME_ARENA_SIZE     :: 1 << 24;

// GAMEPLAY_ARENA_SIZE < EDITOR_ARENA_SIZE because the way we make changes to allocations in the level
// is just to append new allocations to the end of the arena. Once we stop storing mesh vertices on the CPU then
// maybe this can change.


AUDIO_SAMPLES_PER_SECOND :: 48000;


Sample :: struct {
    l, r: s16;
}


Game_Init_Data :: struct {
    game_memory: *void;
    gl_extension_loader: (*u8) -> *void #c_call;
    keys_down: [] bool;
    gameplay_arena_memory: *void;
    editor_arena_memory: *void;
    frame_arena_memory: *void;
    permanent_arena_memory: *void;
}

// :ContextBase
// We need to carry over the Context_Base (@TODO the entire exe context) from the 
// exe because it has stuff in it that helps us print stack traces correctly.
// Runtime_Support is copied between both the exe and dll. If we don't copy the
// context, things get really weird with things sometimes being called from the 
// dll and sometimes the exe, and stack traces are bugged, get printed out twice,
// etc.

// @TODO: Figure out why kernel-level exception backtraces are bugged. Likely the
// Runtime_Support_Crash_Handler code for backtraces does not work in dlls.

Game_Init_Proc :: #type (
    context_base: *Context_Base, // :ContextBase
    init: *Game_Init_Data
) #no_context;


Game_Update :: #type (
    context_base: *Context_Base, // :ContextBase
    game_memory: *void,
    input: Input,
    time_elapsed: float64,
    hotloaded: bool
) #no_context;


Game_Get_Audio_Samples :: #type (
    game_memory_void_ptr: *void,
    samples_played: int, // How many samples we played since the previous update
    buffer: [] Sample
) #no_context;


Audio_Sample :: struct {
    left: u16;
    right: u16;
}


Input :: struct {
    events: [] Input_Event; // Stored by the OS layer

    // In the range (-1, 1) for the x and y axis of the window. Maybe this is a mistake?
    mouse_x: float;
    mouse_y: float;
}


Input_Event_State :: enum u8 {
    DOWN;
    UP;
    REPEAT;
}


Input_Event :: struct {
    key: Key; // Do we want to pack the "down" into these bits?
    state: Input_Event_State;
}


Key :: enum {
    // @TODO: Fill in the rest of these.
    // A - Z: Ascii 'A' - 'Z' 
    // 0 - 9: Ascii '0' - '9'
    // Space: Ascii ' '
    // '[', ']'
    // '-', '='
    MOUSE_LEFT_BUTTON :: 256;
    MOUSE_RIGHT_BUTTON;
    F_BASE :: MOUSE_RIGHT_BUTTON;
    F12 :: F_BASE + 12;
    ARROW_START;
    LEFT_ARROW :: ARROW_START;
    RIGHT_ARROW;
    DOWN_ARROW;
    UP_ARROW;
    ARROW_END :: UP_ARROW;
    BACKSPACE;
    DELETE;
    SHIFT;
    CTRL;
    TILDE;
    TAB;
    ENTER;
    HOME;
    END;
    COUNT;
}


Date :: struct {
    year, month, day, hour, minute, second, millisecond: int;
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


// @TODO: Make this use memory arenas
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


expand_to_s64 :: (value: *void, info: *Type_Info) -> s64 {
    assert(info != type_info(u64));

    check :: (T: Type) #expand {
        if info == type_info(T) `return xx cast(*T, value).*;
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

print :: (using sb: *String_Builder, s: string, args: ..Any) {
    arg_index := 0;

    for 0..s.count-1 {
        if s[it] == #char "%" {
            assert(arg_index < args.count);
            arg := args[arg_index];
            
            if arg.type.type == {
                case .STRING;
                    arg_str := cast(*string, arg.value_pointer).*;
                    print_string(sb, arg_str);
                case .INTEGER;
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
                case .FLOAT;
                    arg_float: float64;
                    if arg.type.runtime_size == 4 {
                        arg_float = xx cast(*float32, arg.value_pointer).*;
                    } else {
                        arg_float = cast(*float64, arg.value_pointer).*;
                    }

                    i := cast(*u64, *arg_float).*;

                    sign := i >> 63;
                    exponent := cast(s64, (i >> 52) & 0b11111111111) - 1023;
                    mantissa := i & 0b1111111111111111111111111111111111111111111111111111;

                    // Max value of u64 is 18_446_744_073_709_551_616.
                    DECIMAL : u64 : 10_000_000_000_000_000_000;
                    
                    print_fractional_part :: (sb: *String_Builder, fractional_part: u64) {
                        if fractional_part == 0 return;
                        print_string(sb, ".");

                        divisor := DECIMAL;
                        while divisor / 10 > fractional_part {
                            divisor /= 10;
                            print_string(sb, "0");
                        }

                        while fractional_part / 10 * 10 == fractional_part {
                            fractional_part /= 10;
                        }

                        print(sb, "%", fractional_part);
                    }
                    
                    // @Incomplete I'm sure there are edge cases where this breaks. We need to find them.
                    // Implementing your own printf sounds like the most hackerman thing EVER.
                    // I should not have done this.

                    if exponent >= 64 {
                        // @Incomplete: Handle printing giant floats correctly.
                        // @Incomplete: Handle printing infinity correctly.
                        // @Incomplete: Handle printing nan correctly.
                        print(sb, "%", cast(u64, 1 << 63));
                    } else if exponent <= -64 {
                        // @Incomplete: Handle printing tiny floats correctly
                        // @Incomplete: Handle printing denormalized numbers correctly
                        if sign print_string(sb, "-0");
                        else    print_string(sb, "0");
                    } else if exponent >= 0 {
                        int_part := cast(u64, 1 << exponent);
                        
                        mantissa_last_int_bit_index := 52 - exponent;
                        for 0..mantissa_last_int_bit_index {
                            if mantissa & cast(u64, (1 << 51) >> it) {
                                int_part += cast(u64, 1 << (exponent - 1 - it));
                            }
                        }
                        
                        if sign print_string(sb, "-");
                        print(sb, "%", int_part);
                        
                        
                        fractional_part: u64 = 0;
                        
                        // @Cleanup maybe there is a way to factor this with code for printing out
                        // floats with no integer part.
                        floating_point_length := 52 - exponent - 1;
                        for 0..floating_point_length {
                            if mantissa & cast(u64, (1 << floating_point_length) >> it) {
                                fractional_part += DECIMAL >> cast(u64, (it + 1));
                            }
                        }

                        print_fractional_part(sb, fractional_part);

                    } else {
                        if sign print_string(sb, "-0");
                        else    print_string(sb, "0");

                        fractional_part := DECIMAL >> cast(u64, -exponent);
                        
                        for 0..51 {
                            if mantissa & cast(u64, (1 << 51) >> it) {
                                fractional_part += DECIMAL >> cast(u64, -exponent + (it + 1));
                            }
                        }

                        print_fractional_part(sb, fractional_part);
                    }

                case .BOOL;
                    arg_bool := cast(*bool, arg.value_pointer).*;
                    str := ifx arg_bool "true" else "false";
                    print_string(sb, str);
                case .ENUM;
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
                case .ARRAY;
                    info := cast(*Type_Info_Array, arg.type);

                    print_array :: (sb: *String_Builder, count: s64, data: *void, type: *Type_Info) {
                        print(sb, "[ ");
                        for 0..count-1 {
                            element_ptr := data + type.runtime_size * it;
                            print(sb, "% ", dynamic_any(type, element_ptr));
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

                case .POINTER;
                    info := cast(*Type_Info_Pointer, arg.type);

                    // I want to allow us to print c strings.
                    // Maybe this is a mistake.
                    assert(info.pointer_to == type_info(u8));
                    c_string := cast(**u8, arg.value_pointer).*;
                    while c_string.* {
                        assert(index < buf.count);
                        buf[index] = c_string.*;
                        index += 1;
                        c_string += 1;
                    }
                case .VARIANT;
                    info := cast(*Type_Info_Variant, arg.type);
                    print(sb, "%", dynamic_any(info.variant_of, arg.value_pointer));
                case; assert(false);
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


clear :: inline (arena: *Memory_Arena) {
    arena.current = 0;
}


alloc :: (arena: *Memory_Arena, count: s64, zero_init := true) -> *void {
    assert(count >= 0);
    new_current := arena.current + count;
    assert(new_current <= arena.count);
    ret := arena.data + arena.current;
    arena.current = new_current;
    if zero_init memset(ret, 0, count);
    return ret;
}


print :: (s: string, args: ..Any) {
    buf: [4096] u8;
    sb := make_string_builder(buf);
    print(*sb, s, ..args);
    os_print(get_string(*sb));
}


// This is os-specific stuff that doesn't require an init.
#if OS == .WINDOWS {
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
} else {
    #assert false;
}

