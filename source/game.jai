#import "Math"; // @TODO: DELETE THIS DEPENDENCY!
#import "freetype-2.12.1";
#import "stb_image";
#import "stb_image_write";

#load "gl.jai";
#load "shared.jai";
#load "imm.jai";
#load "imgui.jai";
#load "font.jai";
#load "draw.jai";
#load "helpers.jai";
#load "audio.jai";
#load "math.jai";
#load "entities.jai";
#load "level.jai";
#load "editor.jai";
#load "serialize.jai";
#load "test.jai";

#if OS == .WINDOWS {
    #load "windows_game.jai";
} else {
    #assert false;
}


Game_Context :: struct {
    using gl_procs: GL_Procedures;
    using gl_extensions: GL_Extensions;
    
    using os_procs: OS_Procedures;
    keys_down: [] bool;

    frame_arena: Memory_Arena;
    permanent_arena: Memory_Arena;
    
    // @Incomplete:
    // We might just want to init a new freetype library every time we instanciate a font
    // and use the per-frame bump allocator as the allocator for FreeType.
    freetype: FT_Library;
    shader_include: string;

    // The above has to be initialized before anything else is intialized.

    imm_state: Imm_State;
    imgui_state: Imgui_State;
    
    editor_imgui_disabled: bool;
    
    using assets: struct {
        imm_color_shader: GLuint;
        imm_text_shader: GLuint;
        imm_saturation_value_shader: GLuint;
        imm_hue_shader: GLuint;
        gameplay_gridlike_shader: GLuint;
        editor_gridlike_shader: GLuint;
        color_shader: GLuint;
        wireframe_shader: GLuint;
        bitmap_shader: GLuint;
        item_and_color_shader: GLuint;
        item_and_bitmap_shader: GLuint;
        occlusion_shader: GLuint;


        consolas: Font;

        footstep: Wav;

        gridlike_bitmap: GLuint;
        gridlike_outline_bitmap: GLuint;
        enemy_mesh: Mesh;
        enemy_left_bitmap: GLuint;
        enemy_right_bitmap: GLuint;
        enemy_annihilation_mesh: Mesh;
        enemy_spawner_mesh: Mesh;
        enemy_despawner_mesh: Mesh;
        player_mesh: Mesh;
        player_bitmap: GLuint;
        entrance_mesh: Mesh;
        exit_mesh: Mesh;
    };
}

#add_context game_context: *Game_Context;

Game_Memory :: struct {
    game_context: Game_Context;
    game: Game;
}

Game :: struct { 
    mode: Game_Mode;

    level: Level;
    // Right now, the EDITOR and GAMEPLAY mode both use this member to store their
    // level state. When we switch modes, we just reload the level based on the
    // level index.
    level_arena: Memory_Arena;

    editor: Editor;
    // editor_level: Level;
    // editor_arena: Memory_Arena;
    editor_level_index: int;

    // gameplay_level: Level;
    // gameplay_arena: Memory_Arena;
    gameplay_level_index: int;

    time_elapsed: float64;
}

Game_Mode :: enum {
    GAMEPLAY;
    EDITOR;
}

#assert GAME_MEMORY_SIZE >= size_of(Game_Memory);

LEVELS :: string.[
    "levels/overworld.level",
    "levels/test.level",
    "levels/test2.level",
    "levels/test3.level",
    "levels/test4.level",
    "levels/intro.level",
    "levels/comb.level",
    "levels/comb2.level",
    "levels/chocolate_bar.level",
    "levels/bridge.level",
    "levels/prison_escape.level",
    "levels/enemies_intro.level",
    "levels/enemies_advanced.level",
];


NEAR_PLANE :: 0.1;
FAR_PLANE :: 1000.0;

IMGUI_POSITION :: Vector2.{0, 0};
IMGUI_SIZE :: Vector2.{700, INNER_WINDOW_H};

#program_export "game_init"
game_init : Game_Init_Proc : (context_base: *Context_Base, data: *Game_Init_Data) #no_context {
    game_memory := cast(*Game_Memory, data.game_memory);
    push_context {
        context.base = context_base.*;
        context.game_context = *game_memory.game_context;
        
        using context.game_context;

        frame_arena = make_arena(data.frame_arena_memory, FRAME_ARENA_SIZE);
        permanent_arena = make_arena(data.permanent_arena_memory, PERMANENT_ARENA_SIZE);
        
        os_procs = data.os_procs;
        keys_down = data.keys_down;

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
        } else {
            print("glDebugMessageCallbackARB was not found\n.");
        }

        game_dll_hotloaded_init();

        glClearColor(70.0/256.0, 85.0/256.0, 131.0/256.0, 1);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

        glEnable(GL_DEPTH_TEST);
        glEnable(GL_CULL_FACE);

        assert(FT_Init_FreeType(*freetype) == 0);
        success:, shader_include = read_file("shaders/include.gl", *permanent_arena);
        assert(success);
        
        imm_state = imm_init();
        imgui_state = imgui_init();

        imm_color_shader = load_shader("shaders/imm_color.gl");
        imm_text_shader = load_shader("shaders/imm_text.gl");
        imm_saturation_value_shader = load_shader("shaders/imm_saturation_value.gl");
        imm_hue_shader = load_shader("shaders/imm_hue.gl");
        gameplay_gridlike_shader = load_shader("shaders/gridlike.gl", "#define GAMEPLAY\n");
        editor_gridlike_shader = load_shader("shaders/gridlike.gl");
        color_shader = load_shader("shaders/color.gl");
        wireframe_shader = load_shader("shaders/wireframe.gl");
        bitmap_shader = load_shader("shaders/bitmap.gl");
        item_and_color_shader = load_shader("shaders/item_and_color.gl");
        item_and_bitmap_shader = load_shader("shaders/item_and_bitmap.gl");
        occlusion_shader = load_shader("shaders/occlusion.gl");

        consolas = load_font("consolas.ttf");

        footstep = load_wav("footstep.wav", *permanent_arena);

        gridlike_bitmap = load_bitmap("gridlike.tga");
        gridlike_outline_bitmap = load_bitmap("gridlike_outline.tga");
        
        enemy_mesh = load_mesh("enemy.my_mesh", *permanent_arena);
        enemy_left_bitmap = load_bitmap("enemy_left.tga");
        enemy_right_bitmap = load_bitmap("enemy_right.tga");
        enemy_annihilation_mesh = make_cuboid_vertex_mesh(.{0.01, 0.01, 0.01}, .{0.99, 0.99, 0.99}, *permanent_arena);
        enemy_spawner_mesh = load_mesh("enemy_spawner.my_mesh", *permanent_arena);
        enemy_despawner_mesh = make_cuboid_vertex_mesh(.{0.15, 0, 0.15}, .{0.85, 0.1, 0.85}, *permanent_arena);
        entrance_mesh = make_cuboid_vertex_mesh(.{0.15, 0, 0.15}, .{0.85, 0.1, 0.85}, *permanent_arena);
        exit_mesh = make_cuboid_vertex_mesh(.{0.15, 0, 0.15}, .{0.85, 0.1, 0.85}, *permanent_arena);
        player_mesh = load_mesh("player.my_mesh", *permanent_arena);
        player_bitmap = load_bitmap("player.tga");


        //
        // Now that the game_context is initted, we can init the game.
        //

        using game_memory;
        using game_memory.game;

        level_arena = make_arena(data.gameplay_arena_memory, GAMEPLAY_ARENA_SIZE);
        // editor_arena = make_arena(data.editor_arena_memory, EDITOR_ARENA_SIZE);
        // gameplay_arena = make_arena(data.gameplay_arena_memory. LEVEL_ARENA_SIZE);
        
        /*
        if !load_level_part_1_deserialize("test.level", *editor_level, *editor_arena) {
            load_level_part_1_new(*editor_level, *editor_arena);
        }
        assert(load_level_part_2_init_unserialized_fields("test.level", *editor_level, *editor_arena));
        */
        
        set_mode(*game, .EDITOR);
    }
}

#program_export "game_dll_hotloaded_init"
game_dll_hotloaded_init : Game_DLL_Hotloaded_Init : (
    context_base: *Context_Base,
    game_memory_: *void
) #no_context {
    push_context {
        context.base = context_base.*;
        context.game_context = game_memory_;

        game_dll_hotloaded_init();
    }
}


// I wish we didn't need to have a procedure like this.
// However, some libraries we use have globals that 
// get reset when we hotload, and the imgui uses the
// code loc to store the active widget, and those
// numbers could change, so we have to reset that.
game_dll_hotloaded_init :: () {
    using context.game_context;
    stbi_set_flip_vertically_on_load(1);
    stbi_flip_vertically_on_write(1);
    if GL_ARB_debug_output glDebugMessageCallbackARB(gl_debug_callback, context.game_context);
    imgui_state.active_widget_exists = false;
}



#program_export "game_update"
game_update : Game_Update : (
    context_base: *Context_Base,
    game_memory_: *void, 
    input: Input,
    time_elapsed_: float64
) #no_context {
    game_memory := cast(*Game_Memory, game_memory_);
    push_context {
        context.base = context_base.*;
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
        
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);

        mouse := Vector2.{input.mouse_x, input.mouse_y};
        
        imgui_state.event_count = 0;
        imgui_state.mouse = (imgui_state.camera_to_imgui * Vector4.{mouse.x, mouse.y, 0, 1}).xy;
        
        // Instead of using different focusing systems for the editor and imgui,
        // we could have a #caller_location-based focusing system for everything,
        // and not have to check both the 3d editor and the imgui like we do here.
        // However, I don't know if this is the clearly better option yet, so I am
        // going to leave it.
        //          -berk, 2025 - 3 - 15


        screenshot_requested: bool;


        for input.events {
            if it.key == .TILDE && it.state == .DOWN {
                free_level(*level, *level_arena);
                
                if #complete mode == {
                    case .GAMEPLAY; set_mode(*game, .EDITOR);
                    case .EDITOR;   set_mode(*game, .GAMEPLAY);
                }
                continue;
            }

            if #complete mode == {
                case .GAMEPLAY;
                    change_level :: (dir: int) #expand {
                        free_level(*level, *level_arena);
                        old_index := gameplay_level_index;
                        gameplay_level_index = (gameplay_level_index + dir + LEVELS.count) % LEVELS.count;
                        
                        success := load_level_part_1_deserialize(LEVELS[gameplay_level_index], *level, *level_arena);
                        if success success = load_level_part_2_init_unserialized_fields(LEVELS[gameplay_level_index], *level, .GAMEPLAY, *level_arena);

                        if !success {
                            log(.ERROR, "Loading level \"%\" failed due to a deserialization error. Going back to the last level.\n", LEVELS[gameplay_level_index]);
                            gameplay_level_index = old_index;
                            assert(load_level_part_1_deserialize(LEVELS[gameplay_level_index], *level, *level_arena));

                            assert(load_level_part_2_init_unserialized_fields(LEVELS[gameplay_level_index], *level, .GAMEPLAY, *level_arena));
                        }
                    }

                    if it.key == #char "[" && it.state == .DOWN {
                        change_level(-1);
                        continue;
                    }

                    if it.key == #char "]" && it.state == .DOWN {
                        change_level(1);
                        continue;
                    }

                    if it.key == #char "C" && it.state == .DOWN && keys_down[Key.CTRL] {
                        screenshot_requested = true;
                        continue;
                    }

                    gameplay_handle_input(*level, *level_arena, it);

                case .EDITOR;
                    imgui_capturing_input := 
                        !editor_imgui_disabled
                     && editor.mode == .IDLE 
                     && (imgui_state.active_widget_exists || inside(IMGUI_POSITION, IMGUI_SIZE, imgui_state.mouse));
                    
                    // Is it weird that I manually make these higher-priority than the imgui?
                    if it.key == #char "S" && keys_down[Key.CTRL] && it.state == .DOWN {
                        serialize_level(*level);
                        log(.OK, "Serialized level.\n");
                        continue;
                    }

                    if it.key == #char "[" && it.state == .DOWN {
                        editor_level_index = (editor_level_index - 1 + LEVELS.count) % LEVELS.count;
                        free_level(*level, *level_arena);
                        set_mode(*game, .EDITOR);
                        continue;    
                    }

                    if it.key == #char "]" && it.state == .DOWN {
                        editor_level_index = (editor_level_index + 1) % LEVELS.count;
                        free_level(*level, *level_arena);
                        set_mode(*game, .EDITOR);
                        continue;
                    }

                    if imgui_capturing_input {
                        assert(imgui_state.event_count < imgui_state.events.count);
                        imgui_state.events[imgui_state.event_count] = it;
                        imgui_state.event_count += 1;
                        continue;
                    }

                    if it.key == #char "T" && it.state == .DOWN {
                        test();
                        continue;
                    }

                    if it.key == .TAB && it.state == .DOWN {
                        editor_imgui_disabled = !editor_imgui_disabled;
                        continue;
                    }

                    editor_handle_input(*level, *level_arena, *editor, mouse, it);
            }
        }
        
        dt: float;
        if time_elapsed == 0 { // We're on the first tick. Set dt to something reasonable.
            dt = 1.0 / 60.0;
        } else {
            dt = cast(float, time_elapsed_ - time_elapsed);
        }
        time_elapsed = time_elapsed_;


        if #complete mode == {
            case .EDITOR;
                editor_update(*level, *editor, mouse, dt);
            case .GAMEPLAY;
                gameplay_level_update(*level, dt);
        }

        
        if mode == {
            case .EDITOR;
                editor_draw(*level, *editor);
            case .GAMEPLAY;
                gameplay_draw(*level);
        }


        if screenshot_requested {
            scope_mark(*frame_arena);
            data := alloc(*frame_arena, INNER_WINDOW_W * INNER_WINDOW_H * 3, zero_init = false);
            glReadPixels(0, 0, INNER_WINDOW_W, INNER_WINDOW_H, GL_RGB, GL_UNSIGNED_BYTE, data);
            
            write :: (ctx: *void, data: *void, size: s32) #c_call {
                push_context cast(*#Context, ctx) {
                    assert(create_directory("../screenshots"));

                    buf: [4096] u8 = ---;
                    date := get_date();
                    sb := make_string_builder(buf);

                    // @TODO: Pad with zeros for numbers that aren't long enough.
                    print(*sb, "../screenshots/%-%-%_%-%-%-%.png",
                        date.year, date.month, date.day,
                        date.hour, date.minute, date.second, date.millisecond);

                    name := get_string(*sb);
                    // It's very unlikely that we'll try to write two images within
                    // the same millisecond but if so I'm okay with on
                    assert(write_file(name, .{size, data}));
                }
            }

            stbi_write_png_to_func(write, *context, INNER_WINDOW_W, INNER_WINDOW_H, 3, data, INNER_WINDOW_W * 3);
            log(.OK, "Screenshot captured.\n");
        }
    }
}


// @TODO: Make a real renderer.
// This is all just temporary code to get stuff to draw on the screen.
// I'm not sure about what the editor drawing code vs gameplay drawing code distinction will 
// look like in the future, so I'm okay with the repetition here for now.
// Eventually, we will probably want a system resembling what an actual renderer looks like
// where you output "render commands" into a buffer, that then get sorted and drawn. That is
// too much complication for this initial phase of development, so I'm okay with doing this.
//          -berk, 2025 - 2 - 26

editor_draw :: (using level: *Level, editor: *Editor) {
    using context.game_context;

    glEnable(GL_DEPTH_TEST);
    glEnable(GL_CULL_FACE);
    glDisable(GL_BLEND);

    world_to_camera := get_editor_camera_matrix(editor);

    glUseProgram(editor_gridlike_shader);

    set_uniform_bitmap("bitmap", 0, gridlike_bitmap);
    set_uniform_bitmap("outline_bitmap", 1, gridlike_outline_bitmap);
    for * _Block {
        projection := translate(world_to_camera, to_vector3(it.position));
        set_uniform("projection", projection);
        set_uniform("color", it.color);
        bind_and_draw(*it.mesh);
    }

    set_uniform("color", Door.COLOR);
    for * _Door {
        projection := translate(world_to_camera, to_vector3(it.position));
        set_uniform("projection", projection);
        bind_and_draw(*it.mesh);
    }

    glUseProgram(color_shader);

    for * _Enemy_Spawner {
        matrix, color := get_enemy_spawner_draw_info(it); 
        set_uniform("projection", world_to_camera * matrix);
        set_uniform("color", color);
        bind_and_draw(*enemy_spawner_mesh);
    }


    draw_entities :: (e: [] $T/Entity, mesh: *Mesh) #expand {
        set_uniform("color", T.COLOR);
        for * e {
            matrix := world_to_camera * entity_mesh_to_world_matrix(level, it);
            set_uniform("projection", matrix);
            bind_and_draw(mesh);
        }
    }

    draw_entities(_Entrance, *entrance_mesh);
    draw_entities(_Exit, *exit_mesh);
    draw_entities(_Enemy_Despawner, *enemy_despawner_mesh);


    glUseProgram(bitmap_shader);

    for * _Enemy {
        matrix, bitmap := get_enemy_draw_info(level, it);
        set_uniform("projection", world_to_camera * matrix);
        
        // @Copypasta from the ordinary enemy drawing code.
        // Eventually enemies will just be one mesh anyway.
        set_uniform_bitmap("bitmap", 0, bitmap);
        bind_and_draw(*enemy_mesh);
    }


    set_uniform_bitmap("bitmap", 0, player_bitmap);
    for * _Player {
        matrix := world_to_camera * get_player_draw_info(it);
        set_uniform("projection", matrix);
        bind_and_draw(*player_mesh);
    }

    
    if editor.selected {
        t := (cos(editor.selected_timer * TAU) + 1) / 2;
        color := Vector4.{t, t, t, 1};
        
        e := get_entity(level, editor.selected);
        mesh := entity_mesh(e);
        mesh_to_world := entity_mesh_to_world_matrix(level, e);
        
        glUseProgram(wireframe_shader);
        set_uniform("projection", world_to_camera * mesh_to_world);
        set_uniform("color", color);

        glPolygonMode(GL_FRONT_AND_BACK, GL_LINE); // I don't think this will be set very often so we'll set then unset.
        bind_and_draw(mesh);
        glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
    }

    if editor.mode == .EXTRUDE {
        using editor.extrude;

        start := start_position;
        end := to_vector3i(floor(end_intersection));

        position, size := get_editor_extrude_size(editor);

        glUseProgram(imm_color_shader);
        set_uniform("projection", world_to_camera);

        R :: Vector3.{0.1, 0.1, 0.1};

        imm_cuboid(start_intersection - R, start_intersection + R, .{0, 1, 0, 1});
        imm_cuboid(end_intersection - R, end_intersection + R, .{1, 0, 0, 1});
        WIDTH :: 0.03;
        
        color: Vector4;
        if deletion color = .{1, 0, 0, 1};
        else        color = .{1, 1, 1, 1};

        for :iterate_vector3i size {
            cuboid_position := to_vector3(position + it);
            imm_cuboid_outline(cuboid_position, cuboid_position + Vector3.{1,1,1}, WIDTH, color);
        }

        imm_flush();
    }
    

    //
    // Detect the overlapping blocks in each level and draw where they are.
    // @Speed This is at worst (size_of_the_level * block_count time). This could get slow.
    // We could instead update this every time a Block is moved.
    //
    
    {
        mark := get_mark(*frame_arena);
        defer restore_mark(*frame_arena, mark);

        position, size := get_block_extents(_Block);
        
        overlapping := alloc_view(*frame_arena, size.x * size.y * size.z, int);

        for * block: _Block {
            offset := block.position - position;
            for :iterate_vector3i block.size {
                filled := block.filled[it_index];
                if !filled continue;

                success, index := get_3d_index(it + offset, size);
                assert(success);
                
                overlapping[index] += 1;
            }
        }

       
        glDisable(GL_DEPTH_TEST);
        glEnable(GL_BLEND);

        glUseProgram(imm_color_shader);
        set_uniform("projection", world_to_camera);

        OVERLAPPING_BLOCK_COLOR :: Vector4.{1, 0, 0, 0.5};

        for :iterate_vector3i size {
            count := overlapping[it_index];
            if count > 1 {
                start := position + it;
                end := start + Vector3i.{1,1,1};
                imm_cuboid(to_vector3(start), to_vector3(end), OVERLAPPING_BLOCK_COLOR);
            }
        }

        imm_flush();
    }
    
    if !editor_imgui_disabled {
        glDisable(GL_DEPTH_TEST);
        glDisable(GL_CULL_FACE);

        glUseProgram(imm_color_shader);
        set_uniform("projection", imgui_state.imgui_to_camera);
        imm_quad(IMGUI_POSITION, IMGUI_SIZE, .{0, 0, 0, 1});
        imm_flush();

        font := *consolas;
        item_height := font.ascender * 2;

        item_size := Vector2.{IMGUI_SIZE.x, item_height};
        head := IMGUI_POSITION;

        level_name: [STRING_ENTRY_MAX_COUNT] u8;
        level_name_count: int;

        assert(level_name.count >= name.count);
        memcpy(level_name.data, name.data, name.count);
        level_name_count = name.count;

        {
            margin := font.ascender * 0.2;
            length := head.x + text_length("Level", font) + margin * 2;
            text_position := round(Vector2.{
                head.x + margin,
                head.y + item_size.y / 2 + font.ascender / 2
            });

            imgui_draw_text("Level", text_position, font, HIGHLIGHT_COLOR);

            position := Vector2.{head.x + length, head.y};
            size := Vector2.{item_size.x - length, item_size.y};

            if string_entry(position, size, *imgui_state.test_string, *imgui_state.test_string_count) {
                // Maybe the correct thing to do is to load the new level, then rerender
                // the entire frame.

                // Things we need to do to make this work:
                
                // 1.
                // Separate imgui rendering from the rest of the drawing code.
                // It's okay if the imgui has stuff that is off by a frame, because
                // you did something in the imgui that affected a level element
                // that had its respective imgui already rendered.
                // HOWEVER, that should not contaminate the rest of the drawing.
            }
        }

        head.y += item_height;

        if editor.selected {
            // glEnable(GL_SCISSOR_TEST);
            // glScissor(
            //     xx IMGUI_SIZE.x,
            //     xx (INNER_WINDOW_H - IMGUI_SIZE.y - IMGUI_SIZE.y),
            //     xx IMGUI_SIZE.x,
            //     xx IMGUI_SIZE.y
            // );
            e := get_entity(level, editor.selected);
            type := ENTITIES[e.type];
            imgui_for_value(e, type, head, item_size);
        }
    }
}


gameplay_draw :: (using level: *Level) {
    using context.game_context;

    glEnable(GL_DEPTH_TEST);
    glEnable(GL_CULL_FACE);
    glDisable(GL_BLEND);

    //
    // Draw blocks.
    //
    
    // We need a special shader for blocks because blocks are grid-aligned.
    // We would get floating-point precision error if we just tried to 
    // determine which collision cell each vertex mapped to using just its
    // position.

    world_to_camera := get_gameplay_camera_matrix(level);

    glUseProgram(gameplay_gridlike_shader);
    
    set_uniform_bitmap("bitmap", 0, gridlike_bitmap);
    set_uniform_bitmap("outline_bitmap", 1, gridlike_outline_bitmap);
    set_uniform_bitmap("viewed", 2, view_texture.tbo, GL_TEXTURE_BUFFER);
    set_uniform("viewed_size", level_size);

    for * _Block {
        projection := translate(world_to_camera, to_vector3(it.position));
        set_uniform("viewed_position", it.position - level_position);
        set_uniform("projection", projection);
        set_uniform("color", it.color);
        bind_and_draw(*it.mesh);
    } 

    set_uniform("color", Door.COLOR);
    for * _Door {
        projection := translate(world_to_camera, to_vector3(it.position));
        set_uniform("viewed_position", it.position - level_position);
        set_uniform("projection", projection);
        bind_and_draw(*it.mesh);
    }



    //
    // Draw the other level elements
    //

    set_item_shader_uniforms :: () #expand {
        set_uniform("viewed_position", level_position);
        set_uniform("viewed_size", level_size);
        set_uniform_bitmap("viewed", 0, view_texture.tbo, GL_TEXTURE_BUFFER);
        set_uniform("world_to_camera", world_to_camera);
    }

    glUseProgram(item_and_color_shader);
    set_item_shader_uniforms();


    set_uniform("color", Vector4.{1, 143.0/255.0, 0, 1});
    for mutual_annihilations {
        set_uniform("model_to_world", make_translation_matrix4(to_vector3(it.position)));
        bind_and_draw(*enemy_annihilation_mesh);
    }


    for * _Enemy_Spawner {
        matrix, color := get_enemy_spawner_draw_info(it); 
        set_uniform("model_to_world", matrix);
        set_uniform("color", color);
        bind_and_draw(*enemy_spawner_mesh);
    }


    draw_entities :: (entities: [] $T/Entity, mesh: *Mesh) #expand {
        set_uniform("color", T.COLOR);
        for * entities {
            model_to_world := make_translation_matrix4(to_vector3(it.position));
            set_uniform("model_to_world", model_to_world);
            bind_and_draw(mesh);
        }
    }

    draw_entities(_Entrance, *entrance_mesh);
    draw_entities(_Exit, *exit_mesh);
    draw_entities(_Enemy_Despawner, *enemy_despawner_mesh);

    
    glUseProgram(item_and_bitmap_shader);
    set_item_shader_uniforms();

    for * _Enemy {
        matrix, bitmap := get_enemy_draw_info(level, it);
        set_uniform("model_to_world", matrix);
        set_uniform_bitmap("bitmap", 1, bitmap);
        bind_and_draw(*enemy_mesh);
    }


    //
    // Draw the mesh to conceal the invisible level parts
    //

    glEnable(GL_CULL_FACE);

    // Because this changes so frequently, it makes the most sense for me to draw this in immediate mode.
    glUseProgram(imm_color_shader); 
    set_uniform("projection", world_to_camera);
    
    // @Speed this is taking 1ms... Look into optimizing this.
    for :iterate_vector3i level_size {
        hidden := viewed[it_index] & (.SEEN | .VISIBLE) == 0;
    
        is_a_gridlike_at :: (using level: *Level, index: int) -> bool {
            block_eid := collision[index];
            if block_eid {
                if get_entity(level, block_eid).type == .Block return true;
            } 

            door_eid := doors[index];
            if door_eid {
                return true;
            }
            
            return false;
        }

        a_gridlike_is_here := is_a_gridlike_at(level, it_index);

        origin := to_vector3(level_position + it);

        check_cube_face :: (position: Vector3i, face: Cube_Vertex) #expand {
            in_bounds, index := get_3d_index(position, level_size);
            
            COLOR :: Vector4.{43.0/255.0, 42.0/255.0, 76.0/255.0, 1};
            if !in_bounds {
                if hidden || a_gridlike_is_here {
                    for 0..5 imm_vertex(origin + CUBE_VERTICES[xx face + it], COLOR);
                }
            } else {
                if hidden && !a_gridlike_is_here && viewed[index] & .SEEN != 0 {
                    if !is_a_gridlike_at(level, index) {
                        for 0..5 imm_vertex(origin + CUBE_VERTICES[xx face + it], COLOR);
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
    glEnable(GL_STENCIL_TEST);
    glDepthMask(GL_FALSE);
    glStencilFunc(GL_NOTEQUAL, 1, 0xFF);
    glStencilMask(0xFF);
    glStencilOp(GL_KEEP, GL_KEEP, GL_REPLACE);

    glUseProgram(occlusion_shader);
    
    // Do we want this? Also, it needs to be depth-sorted with the player.
    // set_uniform("projection", translate(world_to_camera, to_vector3(entrance.position)));
    // set_uniform("color", Vector4.{ENTRANCE_COLOR.x, ENTRANCE_COLOR.y, ENTRANCE_COLOR.z, 0.5});
    // bind_and_draw(*entrance_mesh);

    set_uniform("color", Vector4.{Player.COLOR.x, Player.COLOR.y, Player.COLOR.z, 0.5});
    for * _Player {
        matrix := world_to_camera * get_player_draw_info(it);
        set_uniform("projection", matrix);
        bind_and_draw(*player_mesh);
    }

    
    set_uniform("color", Vector4.{Exit.COLOR.x, Exit.COLOR.y, Exit.COLOR.z, 0.5});
    for * _Exit {
        set_uniform("projection", translate(world_to_camera, to_vector3(it.position)));
        bind_and_draw(*exit_mesh);
    }

    glDepthFunc(GL_LESS);
    glDepthMask(GL_TRUE);
    glDisable(GL_STENCIL_TEST);
    
    //
    // Draw the player
    //

    // We draw the player after so the player always draws on top
    // of the exit.

    glUseProgram(bitmap_shader);
    set_uniform_bitmap("bitmap", 0, player_bitmap);
    for * _Player {
        matrix := world_to_camera * get_player_draw_info(it);
        set_uniform("projection", matrix);
        bind_and_draw(*player_mesh);
    }
}


set_mode :: (using game: *Game, new_mode: Game_Mode) {
    mode = new_mode;
    if #complete new_mode == {
        case .GAMEPLAY;
            assert(load_level_part_1_deserialize(LEVELS[gameplay_level_index], *level, *level_arena));
            // Not every serialized level is a valid gameplay level.
            // (Player entity could be missing, Entrance entity could be missing, etc.)
            assert(load_level_part_2_init_unserialized_fields(LEVELS[gameplay_level_index], *level, .GAMEPLAY, *level_arena));
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

    push_context {
        context.game_context = userParam;
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


#program_export "game_get_audio_samples"
game_get_audio_samples : Game_Get_Audio_Samples : (
    game_memory_void_ptr: *void,
    samples_played: int,
    buffer: [] s16 // This is set to zero in the OS layer.
) #no_context {
    push_context {
        game_memory := cast(*Game_Memory, game_memory_void_ptr);
        context.game_context = *game_memory.game_context;
        using game_memory.game.level;
        using game_memory.game_context;

        for 0..playing_sound_count-1 {
            sound := *playing_sounds[it];
            sound.current_sample += samples_played;

            end: int;
            if sound.current_sample + buffer.count > sound.wav.data.count {
                end = sound.wav.data.count;
            } else {
                end = sound.current_sample + buffer.count;
            }

            for sound.current_sample..end-1 {
                sample := sound.wav.data[it];
                output := *buffer[it - sound.current_sample];
                result := cast(s32, sample) + cast(s32, output.*);
                if      result < S16_MIN output.* = S16_MIN;
                else if result > S16_MAX output.* = S16_MAX;
                else                     output.* = xx result;
            }
        }
    }
}
