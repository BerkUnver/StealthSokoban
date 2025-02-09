#import "Math"; // @TODO: DELETE THIS DEPENDENCY!

#load "gl.jai";
#load "shared.jai";
#load "imm.jai";
#load "draw.jai";
#load "helpers.jai";
#load "math.jai";
#load "level.jai";
#load "editor.jai";

Game_Context :: struct {
    using gl_procs: GL_Procedures;
    using gl_extensions: GL_Extensions;
    os_print: (string);
    read_file: (string, [] u8) -> bool, int;
    imm_state: Imm_State;

    frame_arena: Memory_Arena;

    block_shader: GLuint;
    block_bitmap: GLuint;
    imm_color_shader: GLuint;
    color_shader: GLuint;
    wireframe_shader: GLuint;
    color_and_bitmap_shader: GLuint;

    // vaos: [Vertex_Format.COUNT] GLuint;
}

#add_context game_context: *Game_Context;

Game_Memory :: struct {
    game_context: Game_Context;
    using game: Game;
}

Game :: struct { 
    mode: Game_Mode;
    level: Level;
    editor: Editor;
    level_arena: Memory_Arena;

    time_elapsed: float64;
}

Game_Mode :: enum {
    GAME;
    EDITOR;
}

#assert GAME_MEMORY_SIZE >= size_of(Game_Memory);

#program_export "game_init"
game_init : Game_Init_Proc : (data: *Game_Init_Data) #no_context {
    game_memory := cast(*Game_Memory, data.game_memory);
    push_context {

        context.game_context = *game_memory.game_context;

        using context.game_context;

        frame_arena = make_arena(data.frame_arena_memory, FRAME_ARENA_SIZE);

        os_print = data.os_print;
        read_file = data.read_file;

        for * type_info(GL_Procedures).members {
            if it.flags & .CONSTANT continue; // OpenGL procs from versions 1.0 and 1.1 are constant because that's when they were introduced to windows.
            assert((it.flags & .PROCEDURE_WITH_VOID_POINTER_TYPE_INFO) != 0);

            // Works whether or not address is null.
            address := data.gl_extension_loader(it.name.data);
            dest := cast(*u8, *gl_procs) + it.offset_in_bytes;
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

            dest := cast(*u8, *gl_extensions) + member.offset_in_bytes;
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


        glClearColor(0, 0, 0, 1);
        glEnable(GL_DEPTH_TEST);
        glEnable(GL_CULL_FACE);


        // :GLDebugProcHotloadingHack
        stack_context := context;
        if GL_ARB_debug_output glDebugMessageCallbackARB(gl_debug_callback, *stack_context);
        
        // imm_init();

        block_shader = load_shader("shaders/block.gl");
        assert(block_shader != 0);
        imm_color_shader = load_shader("shaders/imm_color.gl");
        assert(imm_color_shader != 0);
        color_shader = load_shader("shaders/color.gl");
        assert(color_shader != 0);
        wireframe_shader = load_shader("shaders/wireframe.gl");
        assert(wireframe_shader != 0);
        color_and_bitmap_shader = load_shader("shaders/color_and_bitmap.gl");
        assert(color_and_bitmap_shader != 0);
        
        /*
        glGenVertexArrays(vaos.count, vaos.data);

        vao := vaos[Vertex_Format.BLOCK];
        glBindVertexArray(vao);
        glEnableVertexAttribArray(0);
        glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, size_of(Block_Vertex), null);
        glEnableVertexAttribArray(1);
        glVertexAttribIPointer(1, 3, GL_INT, size_of(Block_Vertex), *cast(*Block_Vertex, null).viewed_offset);
        glEnableVertexAttribArray(2);
        glVertexAttribPointer(2, 2, GL_FLOAT, GL_FALSE, size_of(Block_Vertex), *cast(*Block_Vertex, null).uv);
        */

        //
        // Now that the game_context is initted, we can init the game.
        //

        using game_memory.game;
        level_arena = make_arena(data.level_arena_memory, LEVEL_ARENA_SIZE);
        
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

        glGenTextures(1, *block_bitmap);
        assert(block_bitmap != 0);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, block_bitmap);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, 16, 16, 0, GL_RGB, GL_UNSIGNED_BYTE, *bitmap_data[0]);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        
        mode = .GAME;
        make_level(*level, *level_arena);

        if GL_ARB_debug_output glDebugMessageCallbackARB(null, null);
    }
}


#program_export "game_update"
game_update : Game_Update : (
    game_memory_: *void, 
    input: *Input,
    time_elapsed_: float64
) #no_context {
    push_context {
        game_memory := cast(*Game_Memory, game_memory_);
        context.game_context = *game_memory.game_context;
        using game_memory.game_context;
        using game_memory.game;

        defer assert(frame_arena.current == 0);
        // I'm trying to enforce people who use the stack arena to use it
        // like a stack and not just put stuff into it and expect it to
        // get cleared at the end of the frame.
        // Therefore, we check to make sure everyone has popped their stuff
        // off of the stack.
        
        for input.events {
            if it.key == Key.F_BASE + 1 && it.down {

                if mode == .GAME {
                    mode = .EDITOR;
                } else {
                    mode = .GAME;
                }

                free_level(*level, *level_arena);
                make_level(*level, *level_arena);
            } else {
                if #complete mode == {
                    case .GAME;
                        level_handle_input(*level, *level_arena, it);
                    case .EDITOR;
                        editor_handle_input(*level, *level_arena, *editor, input.mouse_x, input.mouse_y, it);
                }
            }
        }
        
        dt: float;
        if time_elapsed == 0 { // We're on the first tick. Set dt to something reasonable.
            dt = 1 / 60;
        } else {
            dt = cast(float, time_elapsed_ - time_elapsed);
        }
        time_elapsed = time_elapsed_;
        
        // @TODO We probably want to be able to draw while this is running.
        // However, we need to update the camera movement before we can set the projection for imm_state.
        if #complete mode == {
            case .EDITOR;
                editor_update(*level, *editor, input.mouse_x, input.mouse_y, dt);
            case .GAME;
                update_level_visibility(*level);
        }


        // @TODO: We should print the current editor mode in the top-left of the screen for clarity.

        // :GLDebugProcHotloadingHack
        // We need the GL callback to tank being hotloaded, so we load it, then unload it, every frame.
        stack_context := context;
        if GL_ARB_debug_output glDebugMessageCallbackARB(gl_debug_callback, *stack_context);

        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
        
        
        world_to_camera := get_camera_matrix(*level);

        using level;
        
        draw_vertex_mesh(*player.mesh, translate(world_to_camera, to_vector3(player.position)), .{1, 1, 1, 1});
        draw_vertex_mesh(*entrance.mesh, translate(world_to_camera, to_vector3(entrance.position)), .{75.0/255.0, 228.0/255.0, 1, 1});
        draw_vertex_mesh(*exit.mesh, translate(world_to_camera, to_vector3(exit.position)), .{146.0/255.0, 1, 118.0/255.0, 1});
        
        
        if mode == {
            case .GAME;
                glUseProgram(block_shader);

                glActiveTexture(GL_TEXTURE0);
                glBindTexture(GL_TEXTURE_2D, block_bitmap);
                glActiveTexture(GL_TEXTURE1);
                glBindTexture(GL_TEXTURE_BUFFER, collision.texture.tbo);

                set_uniform("bitmap", cast(s32, 0));
                set_uniform("viewed", cast(s32, 1));
                set_uniform("viewed_size", collision.size);

                for * blocks {
                    projection := translate(world_to_camera, to_vector3(it.position));
                    set_uniform("viewed_position", it.position - collision.position);
                    set_uniform("projection", *projection);
                    set_uniform("color", it.color);
                
                    glBindVertexArray(it.mesh.vao);
                    glBindBuffer(GL_ARRAY_BUFFER, it.mesh.vbo);
                    glDrawArrays(GL_TRIANGLES, 0, xx it.mesh.vertices.count);
                }
            
            case .EDITOR;
                glUseProgram(color_and_bitmap_shader);
                
                glActiveTexture(GL_TEXTURE0);
                glBindTexture(GL_TEXTURE_2D, block_bitmap);

                set_uniform("bitmap", cast(s32, 0));

                for * blocks {
                    projection := translate(world_to_camera, to_vector3(it.position));
                    set_uniform("projection", *projection);
                    set_uniform("color", it.color);

                    glBindVertexArray(it.mesh.vao);
                    glBindBuffer(GL_ARRAY_BUFFER, it.mesh.vbo);
                    glDrawArrays(GL_TRIANGLES, 0, xx it.mesh.vertices.count);
                }


                selected := get_selected(*level, *editor);
                if selected {
                    t := (cos(editor.selected_timer * TAU) + 1) / 2;
                    color := Vector4.{t, t, t, 1};

                    draw_wireframe_mesh(*selected.mesh, translate(world_to_camera, to_vector3(selected.position)), color);
                }
                
        }

        // This is code to do a visualization of a raycast. I'm keeping this around for future reference.
        // This might be valuable for debugging.
        /*
        {
            theta := cast(float, fmod_cycling(time_elapsed, TAU));
            RAY_LENGTH :: 2;
            ray_length_y := sin(theta) * RAY_LENGTH;
            ray_length_z := cos(theta) * RAY_LENGTH;

            Raycast_Data :: struct {
                shade: *float;
                col: *Collision;
            }

            raycast_visitor :: (position: Vector3, using data: Raycast_Data) -> bool {
                success, index := get_3d_index(to_vector3i(position), col.position, col.size);
                if !success return false;
                
                color: Vector4 = ---;

                filled := col.filled[index] != null;
                if filled {
                    color = Vector4.{0, 1, 0, 1};
                } else {
                    s := shade.*;
                    color = Vector4.{s, s, s, 1};
                }
                shade.* *= 0.8;

                end := position + Vector3.{1, 1, 1};
                imm_cuboid_outline(position, end, 0.03, color);

                return filled;
            }
            
            shade := 1.0;
            ray_start := Vector3.{1.5, 1.5, 0.5};
            ray_end := Vector3.{ray_start.x, ray_start.y + ray_length_y, ray_start.z + ray_length_z};
            raycast(ray_start, ray_end, raycast_visitor, .{shade=*shade, col=*collision});
            
            imm_flush();
        }
        */

        if GL_ARB_debug_output glDebugMessageCallbackARB(null, null);
    }
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

    push_context cast(*#Context, userParam) {
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
            "GL Debug Call - source: %, type: %, severity: %, message: %\n",
            source_str,
            type_str,
            severity_str,
            message_str
        );
    }
}
