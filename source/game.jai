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
    
    player_position: Vector3i;
    collision: Collision;
}

Collision :: struct {
    position: Vector3i;
    size: Vector3i;

    level: [] bool;
    // @TODO This is stored x-major, then z, then y.
    // This makes sense from the perspective of wanting to be 
    // able to type levels directly into code for this initial
    // development period, but may make less sense later.
    // Consider coming back to this.
    // @TODO Implement a bit array for better cache coherency.
}

is_voxel_occupied :: (col: Collision, position: Vector3i) -> bool {
    local_position := position - col.position;
    if local_position.x < 0 || col.size.x <= local_position.x
    || local_position.y < 0 || col.size.y <= local_position.y
    || local_position.z < 0 || col.size.z <= local_position.z {
        return false;
    }
    
    coord := local_position.x + 
             local_position.z * col.size.x +
             local_position.y * col.size.z * col.size.x;

    return col.level[coord];
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
    
    collision = .{
        position = .{-2, -1, -2},
        size = .{4, 2, 4},
        level = bool.[
            true,  true,  true,  true,
            true,  true,  true,  true,
            true,  true,  true,  true,
            true,  true,  true,  true,
            
            true,  true,  true,  true,
            true,  true,  true,  true,
            true,  true,  false, false,
            true,  true,  false, false
        ]
    };
    
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
        new_player_position := player_position;
        if it.input == {
            case .UP;    new_player_position.z += 1;
            case .LEFT;  new_player_position.x += 1;
            case .DOWN;  new_player_position.z -= 1;
            case .RIGHT; new_player_position.x -= 1;
        }

        if !is_voxel_occupied(g.collision, new_player_position) {
            player_position = new_player_position;
        }
    }

    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    
    imm_set_shader(g, level_shader);
    imm_set_bitmap(g, level_bitmap);

    // Draw the collision information
    y_chunk := collision.size.x * collision.size.z;
    for y_index: 0..collision.size.y-1 {
        y_offset := y_index * y_chunk;

        y_begin := cast(float, collision.position.y + y_index);
        y_end := y_begin + 1;

        for z_index: 0..collision.size.z-1 {
            z_offset := z_index * collision.size.x;
            offset := y_offset + z_offset;

            z_begin := cast(float, collision.position.z + z_index);
            z_end := z_begin + 1;

            for x_index: 0..collision.size.x-1 {
                has_cube := collision.level[offset + x_index];
                if !has_cube continue;

                x_begin := cast(float, collision.position.x + x_index);
                x_end := x_begin + 1;

                imm_cuboid(g, .{x_begin, y_begin, z_begin}, .{x_end, y_end, z_end}, .{1, 143.0/255.0, 0, 1});
            }
        }
    }

    imm_flush(g);
    
    player_corner := to_vector3(player_position);
    player_begin := player_corner + Vector3.{0.2, 0.2, 0.2};
    player_end   := player_corner + Vector3.{0.8, 0.8, 0.8};

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
