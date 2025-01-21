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
    debug_print: (string);

    imm_state: Imm_State;
    
    level_shader: GLuint;
    level_bitmap: GLuint;
    player_shader: GLuint;
    
    blocks: Fixed_Array(32, Block);

    player_position: Vector3i;

    collision: Collision;

    level_arena: Memory_Arena;
}

Collision :: struct {
    position: Vector3i;
    size: Vector3i;

    filled: [] *Block;
    // @TODO This is stored x-major, then z, then y.
    // This makes sense from the perspective of wanting to be 
    // able to type levels directly into code for this initial
    // development period, but may make less sense later.
    // Consider coming back to this.
    // @TODO Implement a bit array for better cache coherency.
}


Block :: struct {
    position: Vector3i;
    size: Vector3i;
    filled: [] bool;
    color: Vector4;
    moveable: bool;
    // @TODO Pregenerate the mesh for the block and upload it to the GPU
    // @TODO Make a bit array data structure for better cache coherency
}

get_block_cell :: (col: Collision, position: Vector3i) -> **Block {
    local_position := position - col.position;
    if local_position.x < 0 || col.size.x <= local_position.x
    || local_position.y < 0 || col.size.y <= local_position.y
    || local_position.z < 0 || col.size.z <= local_position.z {
        return null;
    }
    
    index := convert_3d_coordinate_to_index(local_position, col.size);
    return *col.filled[index];
}


#program_export "game_init"
game_init : Game_Init : (
    game_memory: *void,
    game_memory_size: u64,
    gl_extension_loader: (*u8) -> *void #c_call,
    debug_print_: (string),
    level_arena_memory: *void
) {
    assert(game_memory_size >= size_of(Game));
    g := cast(*Game, game_memory);
    using g;
    
    debug_print = debug_print_;
    level_arena = make_arena(level_arena_memory, LEVEL_ARENA_SIZE);

    for * type_info(GL_Procedures).members {
        if it.flags & .CONSTANT continue; // OpenGL procs from versions 1.0 and 1.1 are constant because that's when they were introduced to windows.
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
    if GL_ARB_debug_output glDebugMessageCallbackARB(gl_debug_callback, g);
    imm_init(g);

    level_shader = register_shader(g, LEVEL_SHADER);
    assert(level_shader != 0);
    player_shader = register_shader(g, PLAYER_SHADER);
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
    
    T :: true;
    F :: false;
    
    block_0 := append(*blocks);
    block_0.* = .{
        position = .{-3, -1, -2},
        size = .{6, 1, 4},
        filled = .[
            T, T, T, T, T, T,
            T, T, T, T, T, T,
            T, T, T, T, T, T,
            T, T, T, T, T, T
        ],
        color = .{1, 0, 0, 1},
        moveable = false
    };
    
    block_1 := append(*blocks);
    block_1.* = .{
        position = .{-3, 0, -2},
        size = .{6, 1, 4},
        filled = .[
            F, F, F, F, F, F,
            F, F, F, F, F, F, 
            F, F, F, F, F, F,
            T, T, T, T, T, T
        ],
        color = .{1, 143.0/255.0, 0, 1},
        moveable = false
    };

    block_2 := append(*blocks);
    block_2.* = .{
        position = .{0, 0, -2},
        size = .{1, 1, 1},
        filled = .[T],
        color = .{0, 0, 1, 1},
        moveable = true
    };
    
    //
    // Generate your collision information based on the blocks
    //

    start: Vector3i;
    end: Vector3i;
    for blocks {
        if it_index == 0 {
            start = it.position;
            end = it.position + it.size;
        } else {
            if it.position.x < start.x start.x = it.position.x;
            if it.position.y < start.y start.y = it.position.y;
            if it.position.z < start.z start.z = it.position.z;
            
            it_end := it.position + it.size;
            if it_end.x > end.x end.x = it_end.x;
            if it_end.y > end.y end.y = it_end.y;
            if it_end.z > end.z end.z = it_end.z;
        }
    }

    size := end - start;
    collision_array_size := size.x * size.y * size.z;
    success, collision_memory := arena_alloc_array(*level_arena, collision_array_size, *Block);
    assert(success);

    collision = .{
        position = start,
        size = size,
        filled = collision_memory
    };
    
    player_position = .{0, 0, -1};

    // @Speed we could exploit the layouts of the 3D arrays to avoid
    // recalculating offsets.
    
    // @Temporary All of this collision stuff is mega-temporary, and will soon be replaced by something more robust.
    for * blocks {
        for :iterate_vector3i coord: it.size {
            absolute_coord := it.position + coord;
            collision_coord := absolute_coord - collision.position;

            filled := it.filled[it_index];
            if !filled continue;
            
            collision_index := convert_3d_coordinate_to_index(collision_coord, collision.size);
            block_already_there := collision.filled[collision_index];
            assert(!block_already_there);

            collision.filled[collision_index] = it;
        }
    }
    
    if GL_ARB_debug_output glDebugMessageCallbackARB(null, null);
}

#program_export "game_update"
game_update : Game_Update : (
    game_memory: *void, 
    input_events: Fixed_Array(INPUT_EVENT_COUNT, Input_Event)
) {
    g := cast(*Game, game_memory);
    using g;

    // :GLDebugProcHotloadingHack
    // We need the GL callback to tank being hotloaded, so we load it, then unload it, every frame.
    if GL_ARB_debug_output glDebugMessageCallbackARB(gl_debug_callback, g);
    
    for input_events {
        if !it.down continue;
        push_direction: Vector3i;
        if it.input == {
            case .UP;    push_direction.z += 1;
            case .LEFT;  push_direction.x += 1;
            case .DOWN;  push_direction.z -= 1;
            case .RIGHT; push_direction.x -= 1;
        }
        
        new_player_position := player_position + push_direction;
        block_cell := get_block_cell(collision, new_player_position);

        if !block_cell {
            player_position = new_player_position;
            continue;
        }

        block := block_cell.*;
        if !block {
            player_position = new_player_position;
            continue;
        }
        
        if block.moveable {
            new_block_position := block.position + push_direction;
            second_block_cell := get_block_cell(collision, new_block_position);
            if second_block_cell {
                second_block := second_block_cell.*;
                if !second_block {
                    second_block_cell.* = block;
                    block_cell.* = null;
                    block.position = new_block_position;
                    player_position = new_player_position;
                }
            }
        }
    }

    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    
    imm_set_shader(g, level_shader);
    imm_set_bitmap(g, level_bitmap);
    
    // Draw the blocks

    for blocks {
        for :iterate_vector3i coord: it.size {
            filled := it.filled[it_index];
            if !filled continue;
            begin := to_vector3(it.position + coord);
            end := begin + Vector3.{1,1,1};
            imm_cuboid(g, begin, end, it.color);
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

    g := cast(*Game, userParam);

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

        print(
            g,
            "GL Debug Call - source: %, type: %, severity: %, message: %\n",
            source_str,
            type_str,
            severity_str,
            message_str
        );
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
