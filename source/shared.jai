// These are the type definitions shared between the os-specific main and the game itself.

// :DontShare @TODO THE OPERATING SYSTEM SHOULD NOT KNOW ABOUT THIS STUFF!

// :DontShare
#load "gl.jai";

// :DontShare
Vector2 :: struct {
    x, y: float;
} 

// :DontShare
Vector3 :: struct {
    x, y, z: float;
}

// :DontShare
Vector4 :: struct {
    x, y, z, w: float;
}



Game_Main :: #type (*Game, HDC /* :DontShare */);

// :DontShare
Game :: struct {
    using gl_procs: GL_Procedures;
    using gl_extensions: GL_Extensions;
    imm_state: Imm_State;
}

// :DontShare
Vertex :: struct {
    position: Vector3;
    color: Vector4;
}

// :DontShare
Imm_State :: struct {
    vao: GLuint;
    vbo: GLuint;
    vertices: [4096] Vertex;
    vertex_count: u32;
    submitting_vertices: bool;
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
