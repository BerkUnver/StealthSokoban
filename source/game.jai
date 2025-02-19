#import "Math"; // @TODO: DELETE THIS DEPENDENCY!

#load "gl.jai";
#load "shared.jai";
#load "imm.jai";
#load "draw.jai";
#load "helpers.jai";
#load "math.jai";
#load "level.jai";
#load "editor.jai";
#load "entities.jai";

Game_Context :: struct {
    using gl_procs: GL_Procedures;
    using gl_extensions: GL_Extensions;
    os_print: (string);
    read_file: (string, [] u8) -> bool, int;
    imm_state: Imm_State;

    frame_arena: Memory_Arena;
    permanent_arena: Memory_Arena;

    block_shader: GLuint;
    block_bitmap: GLuint;
    imm_color_shader: GLuint;
    color_shader: GLuint;
    wireframe_shader: GLuint;
    color_and_bitmap_shader: GLuint;
    item_shader: GLuint;
    unviewed_color_item_shader: GLuint;
    seen_color_item_shader: GLuint;
    occlusion_shader: GLuint;
    
    enemy_mesh: Mesh;
    enemy_annihilation_mesh: Mesh;
    enemy_spawner_mesh: Mesh;
    player_mesh: Mesh;
    entrance_mesh: Mesh;
    exit_mesh: Mesh;
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
        permanent_arena = make_arena(data.permanent_arena_memory, PERMANENT_ARENA_SIZE);

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
        // :GLDebugProcHotloadingHack
        stack_context := context;
        if GL_ARB_debug_output {
            glEnable(GL_DEBUG_OUTPUT_SYNCHRONOUS); // @Investigate
            // Make sure we do not have to also call glEnable(GL_DEBUG_OUTPUT);
            glDebugMessageCallbackARB(gl_debug_callback, *stack_context);
        } else {
            print("glDebugMessageCallbackARB was not found\n.");
        }


        glClearColor(0, 0, 0, 1);
        glEnable(GL_DEPTH_TEST);
        glEnable(GL_CULL_FACE);

        imm_init();

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
        item_shader = load_shader("shaders/item.gl");
        assert(item_shader != 0);
        unviewed_color_item_shader = load_shader("shaders/item.gl", "#define UNVIEWED_COLOR\n");
        assert(unviewed_color_item_shader != 0);
        seen_color_item_shader = load_shader("shaders/item.gl", "#define SEEN_COLOR\n");
        assert(seen_color_item_shader != 0);
        occlusion_shader = load_shader("shaders/occlusion.gl");
        assert(occlusion_shader != 0);
       
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

        enemy_mesh = make_cuboid_vertex_mesh(.{0.2, 0.2, 0.2}, .{0.8, 0.8, 0.8}, *permanent_arena);
        enemy_annihilation_mesh = make_cuboid_vertex_mesh(.{0.01, 0.01, 0.01}, .{0.99, 0.99, 0.99}, *permanent_arena);
        enemy_spawner_mesh = make_cuboid_vertex_mesh(.{0.15, 0, 0.15}, .{0.85, 0.1, 0.85}, *permanent_arena);
        entrance_mesh = make_cuboid_vertex_mesh(.{0.15, 0, 0.15}, .{0.85, 0.1, 0.85}, *permanent_arena);
        exit_mesh = make_cuboid_vertex_mesh(.{0.15, 0, 0.15}, .{0.85, 0.1, 0.85}, *permanent_arena);
        player_mesh = make_cuboid_vertex_mesh(.{0.2, 0.2, 0.2}, .{0.8, 0.8, 0.8}, *permanent_arena);

        
        mode = .GAME;
        make_level_for_game(*level, *level_arena);

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
        
        // glClear up here so it doesn't happen after anyone does any debug drawing
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

        mouse := Vector2.{input.mouse_x, input.mouse_y};
        
        for input.events {
            if it.key == .TILDE && it.down {
                free_level(*level, *level_arena);
                
                if #complete mode == {
                    case .GAME;
                        mode = .EDITOR;
                        editor = .{};
                        editor.camera_position = .{0, 8, -4};
                        editor.camera_yaw = 0;
                        editor.camera_pitch = -PI / 3;
                        make_level_for_editor(*level, *level_arena);
                    case .EDITOR;
                        mode = .GAME;
                        make_level_for_game(*level, *level_arena);
                }
            } else {
                if #complete mode == {
                    case .GAME;
                        level_handle_input(*level, *level_arena, it);
                    case .EDITOR;
                        editor_handle_input(*level, *level_arena, *editor, mouse, it);
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
                editor_update(*level, *editor, mouse, dt);
            case .GAME;
                level_update(*level, dt);
        }


        // @TODO: We should print the current editor mode in the top-left of the screen for clarity.

        // :GLDebugProcHotloadingHack
        // We need the GL callback to tank being hotloaded, so we load it, then unload it, every frame.
        stack_context := context;
        if GL_ARB_debug_output glDebugMessageCallbackARB(gl_debug_callback, *stack_context);

        
        
        world_to_camera: Matrix4 = ---;
        if #complete mode == {
            case .GAME;
                world_to_camera = get_gameplay_camera_matrix(*level);
            case .EDITOR;
                world_to_camera = get_editor_camera_matrix(*editor);
        }

        using level;
        
        //
        // Draw blocks.
        //
        
        // We need a special shader for blocks because blocks are grid-aligned.
        // We would get floating-point precision error if we just tried to 
        // determine which collision cell each vertex mapped to using just its
        // position.
        glUseProgram(block_shader);

        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, block_bitmap);
        glActiveTexture(GL_TEXTURE1);
        glBindTexture(GL_TEXTURE_BUFFER, view_texture.tbo);

        set_uniform("bitmap", cast(s32, 0));
        set_uniform("viewed", cast(s32, 1));
        set_uniform("viewed_size", level_size);

        for * _Block {
            projection := translate(world_to_camera, to_vector3(it.position));
            set_uniform("viewed_position", it.position - level_position);
            set_uniform("projection", projection);
            set_uniform("color", it.color);
            bind_and_draw(*it.mesh);
        } 

        
        //
        // Draw enemies
        //

        glDisable(GL_CULL_FACE);

        set_uniforms_for_item_shaders :: () #expand {
            set_uniform("viewed_position", level_position);
            set_uniform("viewed_size", level_size);
            glActiveTexture(GL_TEXTURE0);
            glBindTexture(GL_TEXTURE_BUFFER, view_texture.tbo);
            set_uniform("viewed", cast(s32, 0));
            set_uniform("world_to_camera", world_to_camera);
        }

        glUseProgram(item_shader);
        set_uniforms_for_item_shaders();

        // @Speed draw instanced 
        for * _Enemy {
            matrix: Matrix4;
            color: Vector4;
            if #complete it.state == {
                case .IDLE;
                    matrix = make_translation_matrix4(to_vector3(it.position));
                    color = .{1, 0, 0, 1};

                case.MOVING;
                    weight := enemy_timer / Enemy.MOVING_TIME;
                    weight = weight * weight;
                    position := lerp(it.moving_from, to_vector3(it.position), weight);

                    matrix = make_translation_matrix4(position);
                    color = .{1, 0, 0, 1};

                case .SPAWNING;
                    weight := enemy_timer / Enemy.SPAWNING_TIME;
                    position := to_vector3(it.position) + (1 - weight) * Vector3.{0.5, 0.5, 0.5};
                    scale := make_scale_matrix4(.{weight, weight, weight});

                    matrix = make_translation_matrix4(position) * scale;
                    color = .{weight, 0, 0, 1};
            }

            set_uniform("model_to_world", matrix);
            set_uniform("color", color);

            bind_and_draw(*enemy_mesh);
        }

        set_uniform("color", Vector4.{1, 143.0/255.0, 0, 1});
        for enemy_annihilations {
            set_uniform("model_to_world", make_translation_matrix4(to_vector3(it)));
            bind_and_draw(*enemy_annihilation_mesh);
        }

        //
        // Draw things that only appear when seen
        //

        glUseProgram(seen_color_item_shader);
        set_uniforms_for_item_shaders();

        set_uniform("color", Vector4.{0.5, 0, 0, 1});
        for * _Enemy_Spawner {
            set_uniform("model_to_world", make_translation_matrix4(to_vector3(it.position)));
            bind_and_draw(*enemy_spawner_mesh);
        }

        //
        // Draw things that always appear
        //

        glUseProgram(unviewed_color_item_shader);
        set_uniforms_for_item_shaders();

        draw_unviewed_item :: (position: Vector3i, mesh: *Mesh, color: Vector4, unviewed_color: Vector4) {
            using context.game_context;
            model_to_world := make_translation_matrix4(to_vector3(position));
            set_uniform("model_to_world", model_to_world);
            set_uniform("color", color);
            set_uniform("unviewed_color", unviewed_color);
            bind_and_draw(mesh);
        }
        
        ENTRANCE_COLOR :: Vector4.{75.0/255.0, 228.0/255.0, 1, 1};
        draw_unviewed_item(entrance.position, *entrance_mesh, ENTRANCE_COLOR, ENTRANCE_COLOR / 2);
        EXIT_COLOR :: Vector4.{146.0/255.0, 1, 118.0/255.0, 1};
        draw_unviewed_item(exit.position, *exit_mesh, EXIT_COLOR, EXIT_COLOR / 2);

        glEnable(GL_CULL_FACE);

        
        //
        // Draw the player
        //

        glUseProgram(color_shader);
        set_uniform("projection", translate(world_to_camera, to_vector3(player.position)));
        set_uniform("color", Vector4.{1, 1, 1, 1});
        bind_and_draw(*player_mesh);

        
        //
        // Draw the occlusion effects
        //

        // @TODO: Depth sorting. Possibly for when we need a real renderer.
        glDepthFunc(GL_GREATER);
        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

        glUseProgram(occlusion_shader);
        
        // Do we want this? Also, it needs to be depth-sorted with the player.
        // set_uniform("projection", translate(world_to_camera, to_vector3(entrance.position)));
        // set_uniform("color", Vector4.{ENTRANCE_COLOR.x, ENTRANCE_COLOR.y, ENTRANCE_COLOR.z, 0.5});
        // bind_and_draw(*entrance_mesh);

        set_uniform("projection", translate(world_to_camera, to_vector3(exit.position)));
        set_uniform("color", Vector4.{EXIT_COLOR.x, EXIT_COLOR.y, EXIT_COLOR.z, 0.5});
        bind_and_draw(*exit_mesh);

        set_uniform("projection", translate(world_to_camera, to_vector3(player.position)));
        set_uniform("color", Vector4.{1, 1, 1, 0.5});
        bind_and_draw(*player_mesh);

        glDisable(GL_BLEND); 
        glDepthFunc(GL_LESS);



        if mode == .EDITOR {
            if editor.selected_exists {
                t := (cos(editor.selected_timer * TAU) + 1) / 2;
                color := Vector4.{t, t, t, 1};
                
                e := get_entity(*entities, editor.selected);
                mesh := entity_mesh(e, editor.selected);
                position := to_vector3(entity_position(e, editor.selected).*);

                draw_wireframe_mesh(mesh, translate(world_to_camera, position), color);
            }

            if editor.mode == .EXTRUDE {
                using editor.extrude;

                start := start_position;
                end := to_vector3i(floor(end_intersection));

                position, size := get_editor_extrude_size(*editor);

                glUseProgram(imm_color_shader);
                set_uniform("projection", world_to_camera);

                R :: Vector3.{0.1, 0.1, 0.1};

                imm_cuboid(start_intersection - R, start_intersection + R, .{0, 1, 0, 1});
                imm_cuboid(end_intersection - R, end_intersection + R, .{1, 0, 0, 1});
                WIDTH :: 0.03;
                COLOR :: Vector4.{1, 1, 1, 1};
                for :iterate_vector3i size {
                    cuboid_position := to_vector3(position + it);
                    imm_cuboid_outline(cuboid_position, cuboid_position + Vector3.{1,1,1}, WIDTH, COLOR);
                }

                imm_flush();
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


FRUSTUM :: #run -> Matrix4 {
    FOV :: PI / 3;
    NEAR :: 0.1;

    right := cast(float, NEAR * tan(FOV / 2));
    top := right * cast(float, INNER_WINDOW_H) / cast(float, INNER_WINDOW_W);
     
    return make_left_handed_frustum_matrix(-right, -top, NEAR, right, top, 1000);
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
