#import "Math"; // @TODO: DELETE THIS DEPENDENCY!

#load "gl.jai";
#load "shared.jai";
#load "imm.jai";
#load "draw.jai";
#load "helpers.jai";
#load "math.jai";
#load "entities.jai";
#load "level.jai";
#load "editor.jai";
#load "serialize.jai";
#load "test.jai";

Game_Context :: struct {
    using gl_procs: GL_Procedures;
    using gl_extensions: GL_Extensions;
    
    using os_procs: OS_Procedures;

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
    occlusion_shader: GLuint;
    texture_and_color_shader: GLuint;
    
    enemy_mesh: Mesh;
    enemy_nose_mesh: Mesh; // This is very @Temporary. This will go away once mesh loading works.
    enemy_annihilation_mesh: Mesh;
    enemy_spawner_mesh: Mesh;
    player_mesh: Mesh;
    entrance_mesh: Mesh;
    exit_mesh: Mesh;
}

#add_context game_context: *Game_Context;

Game_Memory :: struct {
    game_context: Game_Context;
    game: Game;
}

Game :: struct { 
    mode: Game_Mode;
    level: Level;
    editor: Editor;
    editor_level_index: int;
    game_level_index: int;
    level_arena: Memory_Arena;

    time_elapsed: float64;
}

Game_Mode :: enum {
    GAME;
    EDITOR;
}

#assert GAME_MEMORY_SIZE >= size_of(Game_Memory);

LEVELS :: string.[
    "levels/test.level",
    "levels/test2.level",
    "levels/test3.level",
    "levels/test4.level",
    "levels/intro.level",
    "levels/comb.level",
];

#program_export "game_init"
game_init : Game_Init_Proc : (data: *Game_Init_Data) #no_context {
    game_memory := cast(*Game_Memory, data.game_memory);
    push_context {

        context.game_context = *game_memory.game_context;

        using context.game_context;

        frame_arena = make_arena(data.frame_arena_memory, FRAME_ARENA_SIZE);
        permanent_arena = make_arena(data.permanent_arena_memory, PERMANENT_ARENA_SIZE);
        
        os_procs = data.os_procs;

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


        glClearColor(70.0/256.0, 85.0/256.0, 131.0/256.0, 1);
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
        occlusion_shader = load_shader("shaders/occlusion.gl");
        assert(occlusion_shader != 0);
        texture_and_color_shader = load_shader("shaders/texture_and_color.gl");
        assert(texture_and_color_shader != 0);
       
        //
        // Now that the game_context is initted, we can init the game.
        //
        
        using game_memory;
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

        enemy_mesh = make_cuboid_vertex_mesh(.{-0.3, 0.2, -0.3}, .{0.3, 0.8, 0.3}, *permanent_arena);
        enemy_nose_mesh = make_cuboid_vertex_mesh(Vector3.{0.3, 0.5, 0.0} - Vector3.{0.08, 0.08, 0.08}, Vector3.{0.3, 0.5, 0.0} + Vector3.{0.08, 0.08, 0.08}, *permanent_arena);
        enemy_annihilation_mesh = make_cuboid_vertex_mesh(.{0.01, 0.01, 0.01}, .{0.99, 0.99, 0.99}, *permanent_arena);
        enemy_spawner_mesh = make_cuboid_vertex_mesh(.{0.15, 0, 0.15}, .{0.85, 0.1, 0.85}, *permanent_arena);
        entrance_mesh = make_cuboid_vertex_mesh(.{0.15, 0, 0.15}, .{0.85, 0.1, 0.85}, *permanent_arena);
        exit_mesh = make_cuboid_vertex_mesh(.{0.15, 0, 0.15}, .{0.85, 0.1, 0.85}, *permanent_arena);
        player_mesh = make_cuboid_vertex_mesh(.{0.2, 0.2, 0.2}, .{0.8, 0.8, 0.8}, *permanent_arena);

        set_mode(*game, .GAME);
        
        if GL_ARB_debug_output glDebugMessageCallbackARB(null, null);
    }
}

#program_export "game_update"
game_update : Game_Update : (
    game_memory_: *void, 
    input: Input,
    time_elapsed_: float64
) #no_context {
    push_context {
        game_memory := cast(*Game_Memory, game_memory_);
        context.game_context = *game_memory.game_context;

        using game_memory;
        using game_memory.game;
        using game_memory.game_context;

        defer assert(frame_arena.current == 0);
        // I'm trying to enforce people who use the stack arena to use it
        // like a stack and not just put stuff into it and expect it to
        // get cleared at the end of the frame.
        // Therefore, we check to make sure everyone has popped their stuff
        // off of the stack.

        // @TODO: This isn't a very good check because someone higher up the call
        // stack could just call "restore_mark" and set the current to 0 even if
        // someone lower in the call stack could have done it.
        // This causes us to use more memory than we should.
        
        // glClear up here so it doesn't happen after anyone does any debug drawing
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

        mouse := Vector2.{input.mouse_x, input.mouse_y};
        
        for input.events {
            if it.key == .TILDE && it.down {
                free_level(*level, *level_arena);
                
                if #complete mode == {
                    case .GAME;    set_mode(*game, .EDITOR);
                    case .EDITOR; set_mode(*game, .GAME);
                }
                continue;
            }


            if it.key == #char "T" && it.down {
                test();
                continue;
            }


            if #complete mode == {
                case .GAME;
                    change_level :: (dir: int) #expand {
                        free_level(*level, *level_arena);
                        old_index := game_level_index;
                        game_level_index = (game_level_index + dir + LEVELS.count) % LEVELS.count;
                        
                        success := load_level_part_1_deserialize(LEVELS[game_level_index], *level, *level_arena);
                        if success success = load_level_part_2_init_unserialized_fields(LEVELS[game_level_index], *level, .GAME, *level_arena);

                        if !success{
                            log(.ERROR, "Loading level \"%\" failed due to a deserialization error. Going back to the last level.\n", LEVELS[game_level_index]);
                            game_level_index = old_index;
                            assert(load_level_part_1_deserialize(LEVELS[game_level_index], *level, *level_arena));

                            assert(load_level_part_2_init_unserialized_fields(LEVELS[game_level_index], *level, .GAME, *level_arena));
                        }
                    }

                    if it.key == #char "[" && it.down {
                        change_level(-1);
                        continue;
                    }

                    if it.key == #char "]" && it.down {
                        change_level(1);
                        continue;
                    }

                    level_handle_input(*level, *level_arena, it);
                case .EDITOR;
                    if it.key == #char "[" && it.down {
                        editor_level_index = (editor_level_index - 1 + LEVELS.count) % LEVELS.count;
                        free_level(*level, *level_arena);
                        set_mode(*game, .EDITOR);
                        continue;    
                    }

                    if it.key == #char "]" && it.down {
                        editor_level_index = (editor_level_index + 1) % LEVELS.count;
                        free_level(*level, *level_arena);
                        set_mode(*game, .EDITOR);
                        continue;
                    }

                    editor_handle_input(*level, *level_arena, *editor, mouse, it, input.keys_down);
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
                editor_update(*level, *editor, mouse, input.keys_down, dt);
            case .GAME;
                level_update(*level, dt);
        }


        // @TODO: We should print the current editor mode in the top-left of the screen for clarity.

        // :GLDebugProcHotloadingHack
        // We need the GL callback to tank being hotloaded, so we load it, then unload it, every frame.
        stack_context := context;
        if GL_ARB_debug_output glDebugMessageCallbackARB(gl_debug_callback, *stack_context);

        
        using level;


        // @TODO: Make a real renderer.
        // This is all just temporary code to get stuff to draw on the screen.
        // I'm not sure about what the editor drawing code vs gameplay drawing code distinction will 
        // look like in the future, so I'm okay with the repetition here for now.
        // Eventually, we will probably want a system resembling what an actual renderer looks like
        // where you output "render commands" into a buffer, that then get sorted and drawn. That is
        // too much complication for this initial phase of development, so I'm okay with doing this.

        //          -berk, 2025 - 26 - 2
        
        if #complete mode == {
            case .GAME;
                //
                // Draw blocks.
                //
                
                // We need a special shader for blocks because blocks are grid-aligned.
                // We would get floating-point precision error if we just tried to 
                // determine which collision cell each vertex mapped to using just its
                // position.

                world_to_camera := camera_matrix;

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
                // Draw things that only appear when seen
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

                for * _Enemy {
                    matrix, color := get_enemy_draw_info(*level, it);
                    set_uniform("model_to_world", matrix);

                    set_uniform("color", color);
                    bind_and_draw(*enemy_mesh);

                    set_uniform("color", 0.5 * color);
                    bind_and_draw(*enemy_nose_mesh);
                }
                
                set_uniform("color", Vector4.{1, 143.0/255.0, 0, 1});
                for enemy_annihilations {
                    set_uniform("model_to_world", make_translation_matrix4(to_vector3(it)));
                    bind_and_draw(*enemy_annihilation_mesh);
                }

                draw_entities :: (e: [] $T/Entity, mesh: *Mesh) {
                    set_uniform("color", T.COLOR);
                    for * e {
                        set_uniform("model_to_world", make_translation_matrix4(to_vector3(it.position)));
                        bind_and_draw(mesh);
                    }
                }

                draw_entities(_Enemy_Spawner, *enemy_spawner_mesh);

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
                
                for * _Entrance draw_unviewed_item(it.position, *entrance_mesh, Entrance.COLOR, Entrance.COLOR / 2);
                for * _Exit draw_unviewed_item(it.position, *exit_mesh, Exit.COLOR, Exit.COLOR / 2);

                glEnable(GL_CULL_FACE);

                //
                // Draw the player
                //

                glUseProgram(color_shader);
                set_uniform("color", Player.COLOR);
                for * _Player {
                    set_uniform("projection", translate(world_to_camera, to_vector3(it.position)));
                    bind_and_draw(*player_mesh);
                }

                //
                // Draw the mesh to conceal the invisible level parts
                //
            
                // Because this changes so frequently, it makes the most sense for me to draw this in immediate mode.
                glUseProgram(imm_color_shader); 
                set_uniform("projection", world_to_camera);

                for :iterate_vector3i level_size {
                    hidden := viewed[it_index] & (.SEEN | .VISIBLE) == 0;
                    a_block_is_here := collision[it_index] && get_entity(*level, collision[it_index]).type == .Block;

                    origin := to_vector3(level_position + it);

                    check_cube_face :: (position: Vector3i, face: Cube_Vertex) #expand {
                        in_bounds, index := get_3d_index(position, level_size);

                        if !in_bounds {
                            if hidden || a_block_is_here {
                                for 0..5 imm_vertex(origin + cube_vertices[xx face + it], .{0,0,0,1});
                            }
                        } else {
                            if hidden && !a_block_is_here && viewed[index] & .SEEN != 0 {
                                a_block_is_there := collision[index] && get_entity(*level, collision[index]).type == .Block;

                                if !a_block_is_there {
                                    for 0..5 imm_vertex(origin + cube_vertices[xx face + it], .{0,0,0,1});
                                }
                            }
                        }
                    }

                    check_cube_face(.{it.x-1, it.y, it.z}, .X_NEGATIVE);
                    check_cube_face(.{it.x+1, it.y, it.z}, .X_POSITIVE);
                    check_cube_face(.{it.x, it.y-1, it.z}, .Y_NEGATIVE);
                    check_cube_face(.{it.x, it.y+1, it.z}, .Y_POSITIVE);
                    check_cube_face(.{it.x, it.y, it.z-1}, .Z_NEGATIVE);
                    check_cube_face(.{it.x, it.y, it.z+1}, .Z_POSITIVE);
                }
                imm_flush();

                
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
                
                set_uniform("color", Vector4.{Exit.COLOR.x, Exit.COLOR.y, Exit.COLOR.z, 0.5});
                for * _Exit {
                    set_uniform("projection", translate(world_to_camera, to_vector3(it.position)));
                    bind_and_draw(*exit_mesh);
                }


                set_uniform("color", Vector4.{Player.COLOR.x, Player.COLOR.y, Player.COLOR.z, 0.5});
                for * _Player {
                    set_uniform("projection", translate(world_to_camera, to_vector3(it.position)));
                    bind_and_draw(*player_mesh);
                }

                glDisable(GL_BLEND); 
                glDepthFunc(GL_LESS);

            case .EDITOR;
                world_to_camera := get_editor_camera_matrix(*editor);

                glUseProgram(texture_and_color_shader);

                glActiveTexture(GL_TEXTURE0);
                glBindTexture(GL_TEXTURE_2D, block_bitmap);
                set_uniform("bitmap", cast(s32, 0));

                for * _Block {
                    projection := translate(world_to_camera, to_vector3(it.position));
                    set_uniform("projection", projection);
                    set_uniform("color", it.color);
                    bind_and_draw(*it.mesh);
                }

                glUseProgram(color_shader);

                for * _Enemy {
                    matrix, color := get_enemy_draw_info(*level, it);
                    set_uniform("projection", world_to_camera * matrix);
                    
                    // @Copypasta from the ordinary enemy drawing code.
                    // Eventually enemies will just be one mesh anyway.
                    set_uniform("color", color);
                    bind_and_draw(*enemy_mesh);

                    set_uniform("color", 0.5 * color);
                    bind_and_draw(*enemy_nose_mesh);
                }


                draw_entities :: (e: [] $T/Entity, mesh: *Mesh) #expand {
                set_uniform("color", T.COLOR);
                    for * e {
                        set_uniform("projection", translate(world_to_camera, to_vector3(it.position)));
                        bind_and_draw(mesh);
                    }
                }

                draw_entities(_Enemy_Spawner, *enemy_spawner_mesh);
                draw_entities(_Entrance, *entrance_mesh);
                draw_entities(_Exit, *exit_mesh);
                draw_entities(_Player, *player_mesh);

                if editor.selected {
                    t := (cos(editor.selected_timer * TAU) + 1) / 2;
                    color := Vector4.{t, t, t, 1};
                    
                    e := get_entity(*level, editor.selected);
                    mesh := entity_mesh(e);
                    position := to_vector3(e.position);
                    
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
                success, index := get_3d_index(to_vector3i(position), col.position, col}, .{};
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


set_mode :: (using game: *Game, new_mode: Game_Mode) {
    mode = new_mode;
    if #complete new_mode == {
        case .GAME;
            assert(load_level_part_1_deserialize(LEVELS[game_level_index], *level, *level_arena));
            // Not every serialized level is a valid game level.
            // (Player entity could be missing, Entrance entity could be missing, etc.)
            assert(load_level_part_2_init_unserialized_fields(LEVELS[game_level_index], *level, .GAME, *level_arena));
        case .EDITOR;
            if !load_level_part_1_deserialize(LEVELS[editor_level_index], *level, *level_arena) {
                load_level_part_1_new(*level, *level_arena);
            } 
            assert(load_level_part_2_init_unserialized_fields(LEVELS[editor_level_index], *level, .EDITOR, *level_arena)); // This should not fail in editor mode


            editor = .{};

            editor.camera_yaw = 0;
            editor.camera_pitch = -PI / 3;

            if level._Block.count != 0 {
                // :LevelSizeInEditor
                // It makes me slightly uncomfortable at how this code overlaps with the 
                // gameplay code but we don't have access to the level size in the editor.

                position, size := get_block_extents(level._Block);
                level_center := to_vector3(position) + to_vector3(size) / 2;
                level_radius := cast(float, max(size.x, max(size.y, size.z)));

                camera_distance := level_radius * 2;
                camera_y := sin(PI / 3) * camera_distance;
                camera_z := cos(PI / 3) * camera_distance;

                editor.camera_position = .{level_center.x, level_center.y + camera_y, level_center.z - camera_z};

            } else {
                editor.camera_position = .{0, 8, -4};
            }
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
