// These are the type definitions shared between the os-specific main
// and the game itself. Please keep the stuff in this file to a minimum.

MAX_INPUT_EVENTS_PER_TICK :: 64;

// @TODO: See how much of this memory is actually used!
MB :: 1024*1024;
EDITOR_ARENA_SIZE    :: 128 * MB;
GAMEPLAY_ARENA_SIZE  :: 16 * MB;
PERMANENT_ARENA_SIZE :: 2 * MB; // Make this kinda big to handle asset hot reloads
FRAME_ARENA_SIZE     :: 32 * MB; // Needs to be big to handle 4k screenshots

// GAMEPLAY_ARENA_SIZE < EDITOR_ARENA_SIZE because the way we make changes to allocations in the level
// is just to append new allocations to the end of the arena. Once we stop storing mesh vertices on the CPU then
// maybe this can change.


AUDIO_SAMPLES_PER_SECOND :: 48000;


Sample :: struct {
    l, r: s16;
}


Game_Init_Data :: struct {
    gl_extension_loader: (*u8) -> *void #c_call;
    keys_down: [] bool;
    gameplay_arena: *Memory_Arena;
    editor_arena: *Memory_Arena;
    frame_arena: *Memory_Arena;
    permanent_arena: *Memory_Arena;
    window_w: int;
    window_h: int;
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
) -> game_memory: *void #no_context;


Game_Update :: #type (
    context_base: *Context_Base, // :ContextBase
    game_memory: *void,
    input: Input,
    dt: float,
    hotloaded: bool,
    changed_file_names: [] string,
    new_window_w: int,
    new_window_h: int
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
    ESCAPE;
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


Print_Ascii :: struct {
    ascii: u8;
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
                
                case .STRUCT;
                    info := type_info(Print_Ascii);
                    if arg.type == info {
                        assert(index < buf.count);
                        buf[index] = cast(*Print_Ascii, arg.value_pointer).ascii;
                        index += 1;
                    } else {
                        assert(false);
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

get_mark :: (arena: *Memory_Arena) -> s64 {
    return arena.current;
}


restore_mark :: (arena: *Memory_Arena, marker: s64) {
    assert(arena.current >= marker);
    arena.current = marker;
}


scope_mark :: (arena: *Memory_Arena) #expand {
    mark := get_mark(arena);
    `defer restore_mark(arena, mark);
}


alloc :: (arena: *Memory_Arena, $T: Type, zero_init := true) -> *T {
    return alloc(arena, size_of(T), zero_init);
}


realloc :: (arena: *Memory_Arena, old: *void, old_count: s64, new_count: s64, zero_init := true) -> *void {
    assert(old_count >= 0);
    assert(new_count >= 0);

    if old == null {
        assert(old_count == 0);
        return alloc(arena, new_count, zero_init);
    }

    current := arena.data + arena.current;
    assert(arena.data <= old && old <= current);

    if new_count < old_count return old;

    if old + old_count == current {
        alloc(arena, new_count - old_count, zero_init);
        return old;
    }

    new := alloc(arena, new_count, false);
    memcpy(new, old, old_count);
    if zero_init memset(new + old_count, 0, new_count - old_count);

    return new;
}


realloc_many :: (arena: *Memory_Arena, old: *$T, old_count: s64, new_count: s64, zero_init := true) -> *T {
    return realloc(arena, old, old_count * size_of(T), new_count * size_of(T), zero_init); 
}


alloc_view :: (arena: *Memory_Arena, count: s64, $T: Type, zero_init := true) -> [] T #must {
    byte_count := size_of(T) * count; 
    ret := alloc(arena, byte_count, zero_init);
    return .{data=xx ret, count=count};
}


reserve_array :: (arena: *Memory_Arena, reserve: s64, $T: Type, zero_init := true) -> [..] T {
    mem := alloc(arena, reserve * size_of(T), zero_init);

    array: [..] T;
    array.data = mem;
    array.allocated = reserve;
    array.allocator.data = arena;

    // I don't love the implicit allocator semantics that Jai wants you to use,
    // so I am avoiding them for now. However, I will set the allocator data to the
    // arena so we can assert that we're resizing using the same arena.

    return array;
}


alloc_array :: (arena: *Memory_Arena, count: s64, $T: Type, zero_init := true) -> [..] T {
    allocated := count;
    if 0 < allocated && allocated < 8 allocated = 8;
    mem := alloc(arena, allocated * size_of(T), zero_init);

    array: [..] T;
    array.count = count;
    array.data = mem;
    array.allocated = allocated;
    array.allocator.data = arena;
    
    return array;
}


alloc_extra_array_capacity :: (arena: *Memory_Arena, array: *[..] $T, new_capacity: s64, zero_init := true) {
    if new_capacity < array.allocated return;
    mem := alloc(arena, new_capacity * size_of(T), zero_init=false);
    memcpy(mem, array.data, size_of(T) * array.count);
    if zero_init memset(mem + size_of(T) * array.count, 0, size_of(T) * (new_capacity - array.count));

    array.data = mem;
    array.allocated = new_capacity;
}


append_no_resize :: (a: *[..] $T) -> *T {
    assert(a.count < a.allocated);
    item := a.data + a.count;
    a.count += 1;
    return item;
}


append_no_resize :: (a: *[..] $T, item: T) {
    append_no_resize(a).* = item;
}


append :: (a: *[..] $T, arena: *Memory_Arena) -> *T {
    if a.allocated == 0 {
        assert(a.count == 0);
        a.allocated = 8;
        a.data = alloc_view(arena, a.allocated, T, zero_init=false).data;
    } else if a.count == a.allocated {
        a.allocated *= 2;
        a.data = realloc_many(arena, a.data, a.count, a.allocated, zero_init = false);
    }

    item := a.data + a.count;
    a.count += 1;

    return item;
}


append :: inline (a: *[..] $T, item: T, arena: *Memory_Arena) {
    append(a, arena).* = item;
}
