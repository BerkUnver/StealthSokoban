#load "gl.jai";
#load "shared.jai";
#load "imm.jai";
#load "helpers.jai";
#load "math.jai";


Game :: struct {
    using gl_procs: GL_Procedures;
    using gl_extensions: GL_Extensions;
    imm_state: Imm_State;
}


print: (string); // :Hotloading MAKE THIS NOT GLOBAL SO IT CAN TANK HOT RELOADS!

#program_export "game_init"
game_init : Game_Init : (
    game_memory: *void,
    game_memory_size: u64,
    gl_extension_loader: (*u8) -> *void #c_call,
    debug_print: (string)
) {
    print = debug_print;
    assert(game_memory_size >= size_of(Game));
    game := cast(*Game, game_memory);
    using game;

    for * type_info(GL_Procedures).members {
        assert((it.flags & .PROCEDURE_WITH_VOID_POINTER_TYPE_INFO) != 0);

        // Works whether or not address is null.
        address := gl_extension_loader(it.name.data);
        dest := cast(*u8, *game.gl_procs) + it.offset_in_bytes;
        cast(**void, dest).* = address;
    }

    // This comes after loading the procs because we need to use glGetIntegerv, etc.
    gl_extension_count: s32;
    glGetIntegerv(GL_NUM_EXTENSIONS, *gl_extension_count);
    for * member: type_info(GL_Extensions).members {
        assert(member.type.type == .BOOL);

        has_extension := false;
        for 0..gl_extension_count-1 {
            extension := glGetStringi(GL_EXTENSIONS, xx it);
            if (jai_string_equals_c_string(member.name, extension)) {
                has_extension = true;
                break;
            }
        }

        dest := cast(*u8, *game.gl_extensions) + member.offset_in_bytes;
        cast(*bool, dest).* = has_extension;
    }


    // We want to support Mac, so we can't support OpenGL 4.3 which is when this
    // extension became part of the standard. As such, we have to use the extension.
    if GL_ARB_debug_output {
        glEnable(GL_DEBUG_OUTPUT_SYNCHRONOUS); // @Investigate
        // Make sure we do not have to also call glEnable(GL_DEBUG_OUTPUT);
    } else {
        // print("glDebugMessageCallbackARB was not found.");
    }

    // @TODO: Enable OpenGL vsync by calling wglSwapIntervalEXT(1)
   

    // :GLDebugProcHotloadingHack
    if GL_ARB_debug_output glDebugMessageCallbackARB(gl_debug_callback, null);
    imm_init(game);
    glClearColor(0, 0, 0, 1);
    glEnable(GL_DEPTH_TEST);
    if GL_ARB_debug_output glDebugMessageCallbackARB(null, null);
}

#program_export "game_update"
game_update : Game_Update : (game_memory: *void) {
    game := cast(*Game, game_memory);
    using game;

    // :GLDebugProcHotloadingHack
    // We need the GL callback to tank being hotloaded, so we load it, then unload it, every frame.
    if GL_ARB_debug_output glDebugMessageCallbackARB(gl_debug_callback, null);

    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    imm_begin(game);
    imm_rect(game, -0.5, -0.5, 1, 1, .{1, 1, 1, 1});
    imm_end(game);

    if GL_ARB_debug_output glDebugMessageCallbackARB(null, null);
}





gl_debug_callback :: (
    source: GLenum,
    type: GLenum,
    id: GLuint,
    severity: GLenum,
    length: GLsizei,
    message: *GLchar,
    userParam: *void
) #c_call {
    // @Investigate: Maybe this will notify us when we don't want to hear from it. Keep an eye out.
    push_context #Context.{} {
        source_str: string;
        if source == {
            case GL_DEBUG_SOURCE_API;               source_str = "API";
            case GL_DEBUG_SOURCE_WINDOW_SYSTEM;     source_str = "WINDOW_SYSTEM";
            case GL_DEBUG_SOURCE_SHADER_COMPILER;   source_str = "SHADER_COMPILER";
            case GL_DEBUG_SOURCE_THIRD_PARTY;       source_str = "THIRD_PARTY";
            case GL_DEBUG_SOURCE_APPLICATION;       source_str = "APPLICATION";
            case GL_DEBUG_SOURCE_OTHER;             source_str = "OTHER";
            case; assert(false);
        }
        
        type_str: string;
        if type == {
            case GL_DEBUG_TYPE_ERROR;               type_str = "ERROR";
            case GL_DEBUG_TYPE_DEPRECATED_BEHAVIOR; type_str = "DEPRECATED_BEHAVIOR";
            case GL_DEBUG_TYPE_UNDEFINED_BEHAVIOR;  type_str = "UNDEFINED_BEHAVIOR";
            case GL_DEBUG_TYPE_PORTABILITY;         type_str = "PORTABILITY";
            case GL_DEBUG_TYPE_PERFORMANCE;         type_str = "PERFORMANCE";
            case GL_DEBUG_TYPE_MARKER;              type_str = "MARKER";
            case GL_DEBUG_TYPE_PUSH_GROUP;          type_str = "PUSH_GROUP";
            case GL_DEBUG_TYPE_POP_GROUP;           type_str = "POP_GROUP";
            case GL_DEBUG_TYPE_OTHER;               type_str = "OTHER";
            case; assert(false);
        }
        
        severity_str: string;
        if severity == {
            case GL_DEBUG_SEVERITY_HIGH;            severity_str = "HIGH";
            case GL_DEBUG_SEVERITY_MEDIUM;          severity_str = "MEDIUM";
            case GL_DEBUG_SEVERITY_LOW;             severity_str = "LOW";
            case GL_DEBUG_SEVERITY_NOTIFICATION;    severity_str = "NOTIFICATION";
            case; assert(false);
        }

        message_str := string.{data=message, count=length};


        // :FormatPrint
        print("GL Debug Callback - source: ");
        print(source_str);
        print(", type: ");
        print(type_str);
        print(", severity: ");
        print(severity_str);
        print(", message: ");
        print(message_str);
        print("\n");
    }
}


