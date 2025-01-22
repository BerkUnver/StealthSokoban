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
    debug_print: (string),
    level_arena_memory: *void
);

INPUT_EVENT_COUNT :: 64;
Game_Update :: #type (
    game_memory: *void,
    input_events: Fixed_Array(INPUT_EVENT_COUNT, Input_Event)
);

Input_Event :: struct {
    input: Input; // Do we want to pack the "down" into these bits?
    down: bool; // Up or down?
}

Input :: enum {
    // @TODO: If we add keyboard remapping, this are probably just going to be virtual keycodes that wrap the keycodes of the operating system.
    FORWARD; // Away from the viewer
    LEFT;
    BACKWARD; // Towards the viewer
    RIGHT;
    UP;
    DOWN;

    PULL;
}

Fixed_Array :: struct (n: s64, $T: Type) {
    count: s64;
    data: [n] T;
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
