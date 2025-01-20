Math :: #import "Math"; // @TODO: DELETE THIS DEPENDENCY!
tan :: Math.tan;
sin :: Math.sin;
cos :: Math.cos;
sqrt :: Math.sqrt;

#load "gl.jai";
#load "shared.jai";
#load "imm.jai";
#load "helpers.jai";
#load "math.jai";


Game :: struct {
    using gl_procs: GL_Procedures;
    using gl_extensions: GL_Extensions;
    imm_state: Imm_State;
    
    level_shader: GLuint;
    level_bitmap: GLuint;
    player_shader: GLuint;

    player_x: s32;
    player_z: s32;
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
    g := cast(*Game, game_memory);
    using g;

    for * type_info(GL_Procedures).members {
        assert((it.flags & .PROCEDURE_WITH_VOID_POINTER_TYPE_INFO) != 0);

        // Works whether or not address is null.
        address := gl_extension_loader(it.name.data);
        dest := cast(*u8, *g.gl_procs) + it.offset_in_bytes;
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

        dest := cast(*u8, *g.gl_extensions) + member.offset_in_bytes;
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
    imm_init(g);

    level_shader = register_shader(g.gl_procs, LEVEL_SHADER);
    assert(level_shader != 0);
    player_shader = register_shader(g.gl_procs, PLAYER_SHADER);
    assert(player_shader != 0);

    FOV :: PI / 3;
    NEAR :: 0.1;

    right := cast(float, NEAR * tan(FOV / 2));
    top := right * cast(float, INNER_WINDOW_H) / cast(float, INNER_WINDOW_W);

    camera_projection := frustum(-right, -top, NEAR, right, top, 1000);
    rotate_camera_down := matrix4_rotate_x(cast(float, PI/3));
    world_to_camera := matrix4_translate(0, -8, 4);

    matrix := matmul(camera_projection, matmul(rotate_camera_down, world_to_camera));
   
    // @TODO: Get actual bitmap loading to work, this is just temporary for testing.
    f := cast(u8, 255);
    bitmap_data := u8.[ 
        0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 
        0,0,0, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, 0,0,0,
        0,0,0, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, 0,0,0,
        0,0,0, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, 0,0,0,
        0,0,0, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, 0,0,0,
        0,0,0, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, 0,0,0,
        0,0,0, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, 0,0,0,
        0,0,0, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, 0,0,0,
        0,0,0, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, 0,0,0,
        0,0,0, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, 0,0,0,
        0,0,0, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, 0,0,0,
        0,0,0, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, 0,0,0,
        0,0,0, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, 0,0,0,
        0,0,0, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, 0,0,0,
        0,0,0, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, 0,0,0,
        0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0
    ];
    
    glGenTextures(1, *level_bitmap);
    assert(level_bitmap != 0);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, level_bitmap);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, 16, 16, 0, GL_RGB, GL_UNSIGNED_BYTE, *bitmap_data[0]);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    
    {
        glUseProgram(level_shader);
        projection_loc := glGetUniformLocation(level_shader, "projection");
        glUniformMatrix4fv(projection_loc, 1, GL_TRUE, *matrix.x_x);
        bitmap_loc := glGetUniformLocation(level_shader, "bitmap");
        glUniform1i(bitmap_loc, 0);
    }
    
    {
        glUseProgram(player_shader);
        projection_loc := glGetUniformLocation(player_shader, "projection");
        glUniformMatrix4fv(projection_loc, 1, GL_TRUE, *matrix.x_x);
    }

    glClearColor(0, 0, 0, 1);
    glEnable(GL_DEPTH_TEST);

    if GL_ARB_debug_output glDebugMessageCallbackARB(null, null);
}

#program_export "game_update"
game_update : Game_Update : (game_memory: *void, input_events: [] Input_Event) {
    g := cast(*Game, game_memory);
    using g;

    // :GLDebugProcHotloadingHack
    // We need the GL callback to tank being hotloaded, so we load it, then unload it, every frame.
    if GL_ARB_debug_output glDebugMessageCallbackARB(gl_debug_callback, null);
    
    for input_events {
        if !it.down continue;
        if it.input == {
            case .UP;    player_z += 1;
            case .LEFT;  player_x += 1;
            case .DOWN;  player_z -= 1;
            case .RIGHT; player_x -= 1;
        }
    }

    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    level := bool.[
        false, true, true, false,
        true, false, false, true,
        false, true, true, false,
        true, false, false, true
    ];
    
    level_offset := Vector3.{-1.5, 0, -1.5};

    imm_set_shader(g, level_shader);
    imm_set_bitmap(g, level_bitmap);
    imm_cube_map(g, level, 4, 4, level_offset, .{1, 143.0/255.0, 0, 1});
    imm_flush(g);

    player_begin := level_offset + Vector3.{xx player_x, 0, xx player_z} - Vector3.{0.3, 0.3, 0.3};
    player_end   := level_offset + Vector3.{xx player_x, 0, xx player_z} + Vector3.{0.3, 0.3, 0.3};

    imm_set_shader(g, player_shader);
    imm_cuboid(g, player_begin, player_end, .{1, 1, 1, 1});
    imm_flush(g);

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




LEVEL_SHADER :: #string END
#ifdef VERTEX_SHADER
layout(location=0) in vec3 vertex_position;
layout(location=1) in vec4 vertex_color;
layout(location=2) in vec2 vertex_uv;
#else
layout(location=0) out vec4 color;
#endif

uniform mat4 projection;
uniform sampler2D bitmap;

OUTIN vec4 fragment_color;
OUTIN vec2 fragment_uv;

#ifdef VERTEX_SHADER
void main() {
    gl_Position = projection * vec4(vertex_position, 1.0);
    fragment_color = vertex_color;
    fragment_uv = vertex_uv;
}
#else
void main() {
    color = fragment_color * texture(bitmap, fragment_uv);
}
#endif
END

PLAYER_SHADER :: #string END
#ifdef VERTEX_SHADER
layout(location=0) in vec3 vertex_position;
layout(location=1) in vec4 vertex_color;
#else
layout(location=0) out vec4 color;
#endif

uniform mat4 projection;

OUTIN vec4 fragment_color;

#ifdef VERTEX_SHADER
void main() {
    gl_Position = projection * vec4(vertex_position, 1.0);
    fragment_color = vertex_color;
}
#else
void main() {
    color = fragment_color;
}
#endif
END
