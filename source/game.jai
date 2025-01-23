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
    flags: enum {PULLING :: 1;};

    collision: Collision;
    test_collision: Collision;

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

get_block :: (col: Collision, position: Vector3i) -> in_bounds: bool, block: *Block {
    local_position := position - col.position;
    if local_position.x < 0 || col.size.x <= local_position.x
    || local_position.y < 0 || col.size.y <= local_position.y
    || local_position.z < 0 || col.size.z <= local_position.z {
        return false, null;
    }
    
    index := convert_3d_coordinate_to_index(local_position, col.size);
    return true, col.filled[index];
}

add_block_to_collision :: (col: *Collision, block: *Block) -> bool {
    if block.position.x < col.position.x return false;
    if block.position.y < col.position.y return false;
    if block.position.z < col.position.z return false;
    if block.position.x + block.size.x > col.position.x + col.size.x return false;
    if block.position.y + block.size.y > col.position.y + col.size.y return false;
    if block.position.z + block.size.z > col.position.z + col.size.z return false;
    
    offset := block.position - col.position;

    // @Speed we could just detect when the failure happens and unwind what we've
    // already added instead of first checking, then adding.
    
    for :iterate_vector3i block.size {
        filled := block.filled[it_index];
        if !filled continue;
        collision_coord := it + offset;
        collision_index := convert_3d_coordinate_to_index(collision_coord, col.size);
        block_already_there := col.filled[collision_index];
        if block_already_there return false;
    }

    for :iterate_vector3i block.size {
        filled := block.filled[it_index];
        if !filled continue;
        collision_coord := it + offset;
        collision_index := convert_3d_coordinate_to_index(collision_coord, col.size);
        col.filled[collision_index] = block;
    }

    return true;
}

remove_block_from_collision :: (col: *Collision, block: *Block) {
    for :iterate_vector3i block.size {
        filled := block.filled[it_index];
        if !filled continue;
        absolute_coord := block.position + it;
        collision_coord := absolute_coord - col.position;

        collision_index := convert_3d_coordinate_to_index(collision_coord, col.size);
        block_already_there := col.filled[collision_index];
        assert(block_already_there == block);
        col.filled[collision_index] = null;
    }
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
            F, F, F, F, F, T,
            T, F, F, F, F, F, 
            F, F, F, F, F, F,
            T, T, T, T, T, T
        ],
        color = .{1, 143.0/255.0, 0, 1},
        moveable = false
    };

    block_2 := append(*blocks);
    block_2.* = .{
        position = .{-1, 0, -2},
        size = .{3, 1, 2},
        filled = .[
            T, T, T,
            T, F, T
        ],
        color = .{0, 0, 1, 1},
        moveable = true
    };
    
    //
    // Generate your collision information based on the blocks
    //
    

    // This generates the collision information based on the bounding box of what's in the level.
    // We may want to bring this back, or possibly have bounding box widgets in the level editor.

    /*
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
    */
    
    
    // @Temporary
    START :: Vector3i.{-10, -10, -10};
    END :: Vector3i.{10, 10, 10};
    size := END - START;
    collision_array_size := size.x * size.y * size.z;

    for blocks {
        assert(it.position.x >= START.x
            && it.position.y >= START.y
            && it.position.z >= START.z);
        assert(it.position.x + it.size.x < END.x
            && it.position.y + it.size.y < END.y
            && it.position.z + it.size.z < END.z);
    }
    success, collision_memory := arena_alloc_array(*level_arena, collision_array_size, *Block);
    assert(success);

    collision = .{
        position = START,
        size = size,
        filled = collision_memory
    };

    player_position = .{0, 0, -1};


    for * blocks {
        assert(add_block_to_collision(*collision, it));
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
        if it.input == .PULL {
            if it.down flags |= .PULLING;
            else       flags &= ~.PULLING;
        } else {
            if !it.down continue;
            push_direction: Vector3i;
            if it.input == {
                case .FORWARD;  push_direction.z += 1;
                case .LEFT;     push_direction.x -= 1;
                case .BACKWARD; push_direction.z -= 1;
                case .RIGHT;    push_direction.x += 1;
                case .UP;       push_direction.y += 1;
                case .DOWN;     push_direction.y -= 1;
            }
            
            new_player_position := player_position + push_direction;


            
            // This code took a while to put together and likely is only going to get more complex.

            // When the player moves, either the entire move needs to succeed at once or fail at once.
            // When the player pushes or pulls a block, a lot about the game state needs to change.
            // If we're trying to update the game state and we find out that the move the player is
            // trying to make is illegal, then we need to undo all the changes we made to the game
            // state while determining if that move is legal.

            // Right now, I am just removing all the blocks from the collision map, updating them,
            // re-adding them to the collision map, and undoing all of that if it turns out one of
            // the blocks is overlapping with something.
            
            // If we are not _very_ careful, this could get messy really quickly.
            // Possibly consider investigating an alternate strategy that does not touch the core
            // game state until we _know_ we can make a move, then do the update.

            //          -berk, 22 - 1 - 2025.

            moving_blocks: Fixed_Array(2, *Block);
            
            pushed_in_bounds, pushed_block := get_block(collision, new_player_position);
            if !pushed_in_bounds continue;

            if pushed_block {
                if !pushed_block.moveable continue;
                assert(append(*moving_blocks, pushed_block));
            }

            if flags & .PULLING {
                pulled_in_bounds, pulled_block := get_block(collision, player_position - push_direction);
                if pulled_in_bounds && pulled_block && pulled_block.moveable && !contains(moving_blocks, pulled_block) {
                    assert(append(*moving_blocks, pulled_block));
                }
            }
            
            for moving_blocks {
                remove_block_from_collision(*collision, it);
            }

            move_failed := false;
            for moving_blocks {
                it.position += push_direction;
                if !add_block_to_collision(*collision, it) {

                    // Undo everything we just tried to do
                    it.position -= push_direction;
                    for #v2 < 0..it_index-1 {
                        block := moving_blocks[it];
                        remove_block_from_collision(*collision, block);
                        block.position -= push_direction;
                    }

                    for moving_blocks {
                        assert(add_block_to_collision(*collision, it));
                    }

                    move_failed = true;
                    break;
                }
            }

            if !move_failed player_position = new_player_position;
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
