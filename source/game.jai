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
#load "table.jai";
#load "test.jai";

Game_Context :: struct {
    using gl_procs: GL_Procedures;
    using gl_extensions: GL_Extensions;
    
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

    ui_to_camera: Matrix4;
    camera_to_ui: Matrix4;
    
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
        exit_mesh: Mesh;
        overworld_entrance_mesh: Mesh;
        overworld_entrance_sound: Wav;
        chroma_key_bitmap: GLuint;
        overworld_exit_mesh: Mesh;
        checkpoint_mesh: Mesh;
    };
}

#add_context game_context: *Game_Context;

Game_Memory :: struct {
    game_context: Game_Context;
    game: Game;
}

Game :: struct { 
    mode: Game_Mode;

    gameplay_level: *Level; // Stored in the arena.
    gameplay_arena: Memory_Arena;

    editor_level: *Level;
    editor_arena: Memory_Arena;

    time_elapsed: float64;
}

Game_Mode :: enum {
    GAMEPLAY;
    EDITOR;
}

#assert GAME_MEMORY_SIZE >= size_of(Game_Memory);

NEAR_PLANE :: 0.1;
FAR_PLANE :: 1000.0;

IMGUI_POSITION :: Vector2.{0, 0};
IMGUI_SIZE :: Vector2.{700, INNER_WINDOW_H};

OVERWORLD :: "levels/overworld.level";

#program_export "game_init"
game_init : Game_Init_Proc : (context_base: *Context_Base, data: *Game_Init_Data) #no_context {
    game_memory := cast(*Game_Memory, data.game_memory);
    push_context {
        context.base = context_base.*;
        context.game_context = *game_memory.game_context;
        
        using context.game_context;

        frame_arena = make_arena(data.frame_arena_memory, FRAME_ARENA_SIZE);
        permanent_arena = make_arena(data.permanent_arena_memory, PERMANENT_ARENA_SIZE);
        
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
        stack_context := context;
        if GL_ARB_debug_output {
            glEnable(GL_DEBUG_OUTPUT_SYNCHRONOUS); // @Investigate
            // Make sure we do not have to also call glEnable(GL_DEBUG_OUTPUT);
        } else {
            print("glDebugMessageCallbackARB was not found\n.");
        }

        hotloaded_dll_init();
        
        // We only ever set this stuff once.
        glClearColor(70.0/256.0, 85.0/256.0, 131.0/256.0, 1);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        glStencilFunc(GL_NOTEQUAL, 1, 0xFF);
        glStencilMask(0xFF);
        glStencilOp(GL_KEEP, GL_KEEP, GL_REPLACE);


        zoom_in_matrix := Matrix4_Identity;
        zoom_in_matrix._11 /= INNER_WINDOW_W / 2;
        zoom_in_matrix._22 /= -INNER_WINDOW_H / 2;
        ui_to_camera = make_translation_matrix4(.{-1, 1, 0}) * zoom_in_matrix;

        zoom_out_matrix := Matrix4_Identity;
        zoom_out_matrix._11 *= INNER_WINDOW_W / 2;
        zoom_out_matrix._22 *= -INNER_WINDOW_H / 2;
        camera_to_ui = zoom_out_matrix * make_translation_matrix4(.{1, -1, 0});

        assert(FT_Init_FreeType(*freetype) == 0);
        success:, shader_include = read_file("shaders/include.gl", *permanent_arena);
        assert(success);
        
        imm_state = imm_init();

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

        footstep = load_wav("sounds/footstep.wav", *permanent_arena);

        gridlike_bitmap = load_bitmap("gridlike.tga");
        gridlike_outline_bitmap = load_bitmap("gridlike_outline.tga");
        
        enemy_mesh = load_mesh("enemy.my_mesh", *permanent_arena);
        enemy_left_bitmap = load_bitmap("enemy_left.tga");
        enemy_right_bitmap = load_bitmap("enemy_right.tga");
        enemy_annihilation_mesh = make_cuboid_vertex_mesh(.{0.01, 0.01, 0.01}, .{0.99, 0.99, 0.99}, *permanent_arena);
        enemy_spawner_mesh = load_mesh("enemy_spawner.my_mesh", *permanent_arena);
        enemy_despawner_mesh = make_cuboid_vertex_mesh(.{0.15, 0, 0.15}, .{0.85, 0.1, 0.85}, *permanent_arena);
        overworld_entrance_mesh = load_mesh("overworld_entrance.my_mesh", *permanent_arena);
        overworld_entrance_sound = load_wav("sounds/overworld_entrance.wav", *permanent_arena);
        chroma_key_bitmap = load_bitmap("chroma_key.tga");
        overworld_exit_mesh = load_mesh("overworld_exit.my_mesh", *permanent_arena);
        exit_mesh = make_cuboid_vertex_mesh(.{0.15, 0, 0.15}, .{0.85, 0.1, 0.85}, *permanent_arena);
        checkpoint_mesh = load_mesh("checkpoint.my_mesh", *permanent_arena);
        player_mesh = load_mesh("player.my_mesh", *permanent_arena);
        player_bitmap = load_bitmap("player.tga");


        //
        // Now that the game_context is initted, we can init the game.
        //

        using game_memory;
        using game_memory.game;

        editor_arena = make_arena(data.editor_arena_memory, EDITOR_ARENA_SIZE);
        gameplay_arena = make_arena(data.gameplay_arena_memory, GAMEPLAY_ARENA_SIZE);
        
        
        editor_level = load_level_part_1_deserialize(OVERWORLD, *editor_arena);
        assert(editor_level != null);
        load_level_part_2_editor(OVERWORLD, editor_level, *editor_arena);

        gameplay_level = load_level_part_1_deserialize(OVERWORLD, *gameplay_arena);
        assert(gameplay_level != null);
        assert(load_level_part_2_gameplay(OVERWORLD, gameplay_level, *gameplay_arena));

        mode = .EDITOR;    
    }
}


// I wish we didn't need to have a procedure like this.
// However, some libraries we use have globals that 
// get reset when we hotload, and the imgui uses the
// code loc to store the active widget, and those
// numbers could change, so we have to reset that.
hotloaded_dll_init :: () {
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
    time_elapsed_: float64,
    hotloaded: bool
) #no_context {
    game_memory := cast(*Game_Memory, game_memory_);
    push_context {
        context.base = context_base.*;
        context.game_context = *game_memory.game_context;

        if hotloaded {
            hotloaded_dll_init();
            print("Game DLL has been hotloaded.\n");
        }

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
        imgui_state.mouse = (camera_to_ui * Vector4.{mouse.x, mouse.y, 0, 1}).xy;
        
        // Instead of using different focusing systems for the editor and imgui,
        // we could have a #caller_location-based focusing system for everything,
        // and not have to check both the 3d editor and the imgui like we do here.
        // However, I don't know if this is the clearly better option yet, so I am
        // going to leave it.
        //          -berk, 2025 - 3 - 15


        screenshot_requested: bool;
        level_select_popup_requested: bool;
        
        for input.events {
            if it.key == .TILDE && it.state == .DOWN {
                if #complete mode == {
                    case .GAMEPLAY; mode = .EDITOR;
                    case .EDITOR;   mode = .GAMEPLAY;
                }
                continue;
            }

            if it.key == #char "C" && it.state == .DOWN && keys_down[Key.CTRL] {
                screenshot_requested = true;
                continue;
            }

            if it.key == #char "L" && it.state == .DOWN && keys_down[Key.CTRL] {
                level_select_popup_requested = true;
                continue;
            }


            load_next_level :: (ascending: bool, mode: Game_Mode, level: **Level, arena: *Memory_Arena) {
                using context.game_context;

                Find_Data :: struct {
                    level: *Level;
                    closest_name: string;
                    furthest_name: string;
                    mark: s64;
                    ascending: bool;
                }
                
                // right now, iterate_directory does not hit the frame_arena, so we can 
                // just store the closest_name on top of the frame_arena.

                find :: (data_: *void, level_name: string) {
                    using context.game_context;
                    using data := cast(*Find_Data, data_);

                    if !closest_name {
                        comparison := strcmp(level_name, level.name);
                        if (ascending && comparison > 0) || (!ascending && comparison < 0) {
                            closest_name = copy_string(*frame_arena, level_name);
                        }
                    } else {    
                        closest_name_comparison := strcmp(level_name, closest_name);
                        level_name_comparison := strcmp(level_name, level.name);

                        if (ascending && level_name_comparison > 0 && closest_name_comparison < 0)
                        || (!ascending && closest_name_comparison > 0 && level_name_comparison < 0) {
                            restore_mark(*frame_arena, mark);
                            closest_name = copy_string(*frame_arena, level_name);
                        }
                    }
                }

                data := Find_Data.{
                    level = level.*,
                    mark = get_mark(*frame_arena),
                    ascending = ascending
                };


                iterate_directory("levels", *data, find);

                if data.closest_name {
                    free_level(level.*, arena);
                    level.* = load_level_part_1_deserialize(data.closest_name, arena);
                    assert(level.* != null);
                    if #complete mode == {
                        case .GAMEPLAY;
                            assert(load_level_part_2_gameplay(data.closest_name, level.*, arena, skip_intro=true));
                        case .EDITOR;
                            load_level_part_2_editor(data.closest_name, level.*, arena);
                    }
                }

                restore_mark(*frame_arena, data.mark);
            }

            if it.key == #char "[" && (it.state == .DOWN || it.state == .REPEAT) {
                if #complete mode == {
                    case .GAMEPLAY; load_next_level(false, .GAMEPLAY, *gameplay_level, *gameplay_arena);
                    case .EDITOR;   load_next_level(false, .EDITOR,   *editor_level,   *editor_arena);
                }
                continue;
            }

            if it.key == #char "]" && (it.state == .DOWN || it.state == .REPEAT) {
                if #complete mode == {
                    case .GAMEPLAY; load_next_level(true, .GAMEPLAY, *gameplay_level, *gameplay_arena);
                    case .EDITOR;   load_next_level(true, .EDITOR,   *editor_level,   *editor_arena);
                }
                continue;

            }


            if #complete mode == {
                case .GAMEPLAY;
                    using gameplay_level;

                    if it.key == #char "R" && it.state == .DOWN {
                        scope_mark(*frame_arena);

                        level_name := string.{name.count, alloc(*frame_arena, name.count, zero_init = true)};
                        // We need the name to persist freeing the old level for when we load the new level.
                        memcpy(level_name.data, name.data, level_name.count);
                        free_level(gameplay_level, *gameplay_arena);

                        gameplay_level = load_level_part_1_deserialize(level_name, *gameplay_arena);
                        assert(gameplay_level != null);
                        assert(load_level_part_2_gameplay(level_name, gameplay_level, *gameplay_arena, skip_intro=true));
                        continue;
                    }

                    gameplay_handle_input(gameplay_level, it);

                case .EDITOR;
                    using editor_level;
                    
                    // Is it weird that I manually make these higher-priority than the imgui?
                    // I do this so if you try to save while an imgui widget is active, you can still save and don't
                    // lose progress if you then try to switch to another level.
                    if it.key == #char "S" && keys_down[Key.CTRL] && it.state == .DOWN {
                        serialize_level(editor_level);
                        log(.OK, "Serialized level.\n");
                        continue;
                    }

                    
                    imgui_capturing_input: bool;
                    if !editor_imgui_disabled && editor.mode == .IDLE {
                        if imgui_state.active_widget_exists || (inside(IMGUI_POSITION, IMGUI_SIZE, imgui_state.mouse) && it.key == .MOUSE_LEFT_BUTTON && it.state == .DOWN) {
                           imgui_capturing_input = true;
                        }
                    } 

                    if imgui_capturing_input {
                        assert(imgui_state.event_count < imgui_state.events.count);
                        imgui_state.events[imgui_state.event_count] = it;
                        imgui_state.event_count += 1;
                        continue;
                    }


                    if it.key == #char "M" && it.state == .DOWN && keys_down[Key.CTRL] && keys_down[Key.SHIFT] {
                        serialize_level(editor_level);
                        log(.OK, "Serialized level before munge.\n");

                        Munge_Data :: struct {
                            level_ptr: **Level;
                            arena: *Memory_Arena;
                        }

                        munge_data := Munge_Data.{
                            level_ptr = *editor_level,
                            arena = *editor_arena
                        };

                        munge :: (data_: *void, level_name: string) {
                            print("Munging level \"%\"\n", level_name);
                            // If there is some kind of breaking change that you need to make between versions of the
                            // serialization system, do whatever you need to do here.

                            using data := cast(*Munge_Data, data_);
                            free_level(level_ptr.*, arena);
                            level_ptr.* = load_level_part_1_deserialize(level_name, arena);
                            level := level_ptr.*;
                            assert(level != null);
                            load_level_part_2_editor(level_name, level, arena);

                            serialize_level(level);
                        }

                        assert(iterate_directory("levels", *munge_data, munge));
                        return;
                    }



                    if it.key == #char "T" && it.state == .DOWN {
                        test();
                        continue;
                    }

                    if it.key == .TAB && it.state == .DOWN {
                        editor_imgui_disabled = !editor_imgui_disabled;
                        continue;
                    }

                    editor_handle_input(editor_level, *editor_arena, mouse, it);
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
                editor_update(editor_level, mouse, dt);
                draw(editor_level, .EDITOR);


                if !editor_imgui_disabled {
                    scope_mark(*frame_arena);
                    new_level_name := editor_draw_imgui(editor_level, *editor_arena);
                    if new_level_name {
                        free_level(editor_level, *editor_arena);
                        success, data := read_file(new_level_name, *frame_arena);
                        if success {
                            editor_level = load_level_part_1_deserialize_mem(new_level_name, data, *editor_arena);
                            assert(editor_level != null);
                        } else {
                            editor_level = alloc(*editor_arena, Level, zero_init = false);
                            editor_level.* = .{};
                        }
                        load_level_part_2_editor(new_level_name, editor_level, *editor_arena);
                    }
                }
            case .GAMEPLAY;
                using gameplay_level;
                gameplay_update(gameplay_level, dt);
                if state == {
                    case .FADE_OUT_ENTRANCE;
                        using fade_out_entrance;
                        if interp >= 1 {
                            assert(eid != 0);

                            e := get_entity(gameplay_level, eid);
                            entrance := as(e, Overworld_Entrance);
                            assert(entrance != null);
                            
                            assert(entrance.level_name != "");
                            scope_mark(*frame_arena);
                            // We need to copy the string because it is going to be freed when we free the old level.
                            level_name := copy_string(*frame_arena, entrance.level_name);
                            free_level(gameplay_level, *gameplay_arena);

                            gameplay_level = load_level_part_1_deserialize(level_name, *gameplay_arena);
                            assert(gameplay_level != null);
                            assert(load_level_part_2_gameplay(level_name, gameplay_level, *gameplay_arena));
                        }
                    case .FADE_OUT_EXIT;
                        using fade_out_exit;
                        if interp >= 1 {
                            scope_mark(*frame_arena);
                            level_name := copy_string(*frame_arena, name);
                            free_level(gameplay_level, *gameplay_arena);

                            gameplay_level = load_level_part_1_deserialize(OVERWORLD, *gameplay_arena);
                            assert(gameplay_level != null);
                            assert(load_level_part_2_gameplay(level_name, gameplay_level, *gameplay_arena));
                            
                            for * _Overworld_Exit {
                                entrance := get_entrance_for_overworld_exit(gameplay_level, it);
                                if entrance && entrance.level_name == level_name {
                                    player := *_Player[0];
                                    player.position = it.position;

                                    // @Hack keep the camera focused on the player because otherwise it will fly
                                    // from wherever the player entity was placed in the level to where we want
                                    // the player to spawn.
                                    camera_focus_x = player.position.x;
                                    camera_focus_z = player.position.z;
                                }
                            }
                        }
                }
                draw(gameplay_level, .GAMEPLAY);
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
                    // the same millisecond but if so I'm okay with one overwriting
                    // the other.
                    assert(write_file(name, .{size, data}));
                }
            }

            stbi_write_png_to_func(write, *context, INNER_WINDOW_W, INNER_WINDOW_H, 3, data, INNER_WINDOW_W * 3);
            log(.OK, "Screenshot captured.\n");
        }
    }
}


editor_draw_imgui :: (using level: *Level, arena: *Memory_Arena) -> new_level_name: string {
    using context.game_context;

    set_shader(imm_color_shader, .{flags = .BLEND});
    set_uniform("projection", ui_to_camera);
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

    new_level_name: string;

    label_length := label("Level", head, item_size);
    if string_entry(.{head.x + label_length, head.y}, .{item_size.x - label_length, item_size.y}, *level_name, *level_name_count) {
        data := alloc(*frame_arena, level_name_count, zero_init=false);
        memcpy(data, level_name.data, level_name_count);
        new_level_name = .{level_name_count, data};
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

    head.y += item_height;


    entity_type: [STRING_ENTRY_MAX_COUNT] u8;
    entity_type_count: int; 

    entity_name := ENTITIES[editor.entity_type].name;
    assert(entity_name.count <= entity_type.count);
    memcpy(entity_type.data, entity_name.data, entity_name.count);
    entity_type_count = entity_name.count;

    label_length_2 := label("Entity Type", head, item_size);
    if string_entry(.{head.x + label_length_2, head.y}, .{item_size.x - label_length_2, item_size.y}, *entity_type, *entity_type_count) {
        str := string.{entity_type_count, entity_type.data};
        for ENTITIES {
            if it.name == str {
                editor.entity_type = xx it_index;
                break;
            }
        }
    }
    


    head.y += item_height;
    head.y += item_height; // A little spacing
    

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
        imgui_for_value(e, type, head, item_size, arena);
    }

    return new_level_name;
}


// @TODO: Make a real renderer.
// This is all just temporary code to get stuff to draw on the screen.
// I'm not sure about what the editor drawing code vs gameplay drawing code distinction will 
// look like in the future, so I'm okay with the repetition here for now.
// Eventually, we will probably want a system resembling what an actual renderer looks like
// where you output "render commands" into a buffer, that then get sorted and drawn. That is
// too much complication for this initial phase of development, so I'm okay with doing this.
//          -berk, 2025 - 2 - 26



draw :: (using level: *Level, mode: Game_Mode) {
    using context.game_context;

    world_to_camera: Matrix4;
    
    position, size: Vector3i;

    if #complete mode == {
        case .GAMEPLAY;
            camera_position, camera_quat := get_gameplay_camera_info(level);
            world_to_camera = multiply(GAMEPLAY_FRUSTUM, multiply(rotation_matrix(Matrix4, camera_quat), make_translation_matrix4(-camera_position)));

            position = level_position;
            size = level_size;
        case .EDITOR;
            world_to_camera = get_editor_camera_matrix(level);
            position, size = get_block_extents(_Block); // :LevelSizeInEditor
    }


    if #complete mode == {
        case .GAMEPLAY;
            set_shader(gameplay_gridlike_shader);
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


        case .EDITOR;
            set_shader(editor_gridlike_shader);
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
    }


    set_item_shader_uniforms :: () #expand {
        set_uniform("viewed_position", position);
        set_uniform("viewed_size", size);
        set_uniform_bitmap("viewed", 0, view_texture.tbo, GL_TEXTURE_BUFFER);
        set_uniform("world_to_camera", world_to_camera);
    }
    
    set_shader(item_and_color_shader);
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

    draw_entities(_Exit, *exit_mesh);
    draw_entities(_Enemy_Despawner, *enemy_despawner_mesh);

         
    set_shader(item_and_bitmap_shader);
    set_item_shader_uniforms();

    for * _Enemy {
        matrix, bitmap := get_enemy_draw_info(level, it);
        set_uniform("model_to_world", matrix);
        set_uniform_bitmap("bitmap", 1, bitmap);
        bind_and_draw(*enemy_mesh);
    }

    
    set_uniform_bitmap("bitmap", 1, chroma_key_bitmap);
    for * _Overworld_Entrance {
        set_uniform("model_to_world", make_translation_matrix4(to_vector3(it.position)));
        set_uniform("substitute_color", it.color);
        bind_and_draw(*overworld_entrance_mesh);
    }


    set_uniform_bitmap("bitmap", 1, chroma_key_bitmap);
    for * _Overworld_Exit {
        substitute_color := Vector4.{0, 0, 0, 1};
        if it.entrance {
            e := get_entity(level, it.entrance);
            entrance := as(e, Overworld_Entrance);
            if entrance {
                substitute_color = entrance.color;
            }
        }

        set_uniform("model_to_world", make_translation_matrix4(to_vector3(it.position)));
        set_uniform("substitute_color", substitute_color);


        bind_and_draw(*overworld_exit_mesh);
    }


    for * _Checkpoint {
        color: Vector4;

        if #complete it.state == {
            case .UNUSED;
                color = .{0, 0, 0, 1};
            case .USED;
                color = .{75.0/255.0, 228.0/255.0, 1, 1};
            case .CURRENT;
                color = .{146.0/255.0, 1, 118.0/255.0, 1};
                // @TODO This is the exit color. Figure out what used checkpoints
                // actually look like once exits look better.
        }

        set_uniform("substitute_color", color);
        set_uniform("model_to_world", make_translation_matrix4(to_vector3(it.position)));
        bind_and_draw(*checkpoint_mesh);    
    }


    if mode == .GAMEPLAY {
        set_shader(imm_color_shader);
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
    }


    //
    // Draw the occlusion effects
    //

    set_shader(occlusion_shader, .{flags = .BLEND | .STENCIL_TEST | .CULL_FACE, depth_func = .GREATER});
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
    
    //
    // Draw the player
    //

    // We draw the player after so the player always draws on top
    // of the exit.

    set_shader(bitmap_shader);
    set_uniform_bitmap("bitmap", 0, player_bitmap);
    for * _Player {
        matrix := world_to_camera * get_player_draw_info(it);
        set_uniform("projection", matrix);
        bind_and_draw(*player_mesh);
    }

    
    if mode == {
        case .GAMEPLAY;

            draw_fade :: (alpha: float) {
                using context.game_context;
                color := Vector4.{0, 0, 0, alpha};
                color.w = alpha;

                set_shader(imm_color_shader, .{flags = .BLEND});
                set_uniform("projection", Matrix4_Identity);
                imm_quad(.{-1, -1}, .{2, 2}, color);
                imm_flush();
            }

            if #complete state == {
                case .FADE_IN_START;
                    using fade_in_start;
                    draw_fade(1 - interp);
                case .FADE_IN_CHECKPOINT;
                    using fade_in_checkpoint;
                    draw_fade(1 - interp);
                case .PLAYING;
                case .FADE_OUT_ENTRANCE;
                    using fade_out_entrance;
                    draw_fade(interp);
                case .FADE_OUT_CHECKPOINT;
                    using fade_out_checkpoint;
                    draw_fade(interp);
                case .FADE_OUT_EXIT;
                    using fade_out_exit;
                    draw_fade(interp);
            }
        case .EDITOR;
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

               
                set_shader(imm_color_shader, .{flags = .BLEND | .CULL_FACE});
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

            if editor.selected {
                //
                // Draw the wireframe
                //

                t := (cos(editor.selected_timer * TAU) + 1) / 2;
                color := Vector4.{t, t, t, 1};
                
                e := get_entity(level, editor.selected);
                mesh := entity_mesh(e);
                mesh_to_world := entity_mesh_to_world_matrix(level, e);
                
                set_shader(wireframe_shader, .{polygon_mode = .LINE});
                set_uniform("projection", world_to_camera * mesh_to_world);
                set_uniform("color", color);

                bind_and_draw(mesh);

            }

            if editor.mode == .EXTRUDE {
                using editor.extrude;

                start := start_position;
                end := to_vector3i(floor(end_intersection));

                position, size := get_editor_extrude_size(level);

                set_shader(imm_color_shader);
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
            // Draw the dragging widget
            //

            if editor.selected {
                e := get_entity(level, editor.selected);

                set_shader(imm_color_shader, .{flags = .BLEND});
                set_uniform("projection", world_to_camera);

                COLORS :: Vector4.[
                    .{1, 0.5, 0.5, 1},
                    .{0.5, 1, 0.5, 1},
                    .{0.5, 0.5, 1, 1},
                ];

                draw_plane :: (position: Vector3, index: int, color: Vector4) #expand {
                    index_1 := (index + 1) % 3;
                    index_2 := (index + 2) % 3;

                    a0 := position.component[index_1] + DRAG_START;
                    b0 := position.component[index_2] + DRAG_START;
                    a1 := position.component[index_1] + DRAG_END;
                    b1 := position.component[index_2] + DRAG_END;

                    c := cast(float, position.component[index]);

                    p0, p1, p2, p3: Vector3;

                    p0.component[index] = c;
                    p0.component[index_1] = a0;
                    p0.component[index_2] = b0;

                    p1.component[index] = c;
                    p1.component[index_1] = a1;
                    p1.component[index_2] = b0;

                    p2.component[index] = c;
                    p2.component[index_1] = a1;
                    p2.component[index_2] = b1;

                    p3.component[index] = c;
                    p3.component[index_1] = a0;
                    p3.component[index_2] = b1;

                    imm_vertex(p0, color);
                    imm_vertex(p1, color);
                    imm_vertex(p2, color);
                    imm_vertex(p0, color);
                    imm_vertex(p2, color);
                    imm_vertex(p3, color);
                }

                if editor.mode == {
                    case .IDLE; #through;
                    case .CAMERA;
                        e_position := to_vector3(e.position);
                        for 0..2 {
                            position := e_position;
                            index_1 := (it + 1) % 3;
                            index_2 := (it + 2) % 3;

                            if editor.camera_position.component[index_1] < xx e.position.component[index_1] {
                                position.component[index_1] -= 1;
                            }

                            if editor.camera_position.component[index_2] < xx e.position.component[index_2] {
                                position.component[index_2] -= 1;
                            }

                            color := COLORS[it];
                            color.w = 0.5;
                            draw_plane(position, it, color);
                        }
                    case .DRAG;
                        using editor.drag;
                        color := COLORS[index];
                        color.w = 0.8;
                        
                        position := to_vector3(e.position);
                        position.component[(index + 1) % 3] += offset_axis_1;
                        position.component[(index + 2) % 3] += offset_axis_2;

                        draw_plane(position, index, color);
                }

                imm_flush();
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
    buffer: [] Sample // This is set to zero in the OS layer.
) #no_context {
    push_context {
        game_memory := cast(*Game_Memory, game_memory_void_ptr);
        context.game_context = *game_memory.game_context;
        using context.game_context;
        using game_memory.game;
        if mode != .GAMEPLAY return;

        using gameplay_level;

        player := *_Player[0];
        player_position := to_vector3(player.position) + Vector3.{0.5, 0.5, 0.5};
        camera_position, camera_quat := get_gameplay_camera_info(gameplay_level);
        
        // @TODO: Accound for the player's current position when considering procedural animation
        // once procedural animation is added to the player.

        player_to_camera := camera_position - player_position;
        player_to_camera_distance := length(player_to_camera);
        

        PLAYER_TO_CAMERA_RATIO :: 0.05;
        listener_distance := player_to_camera_distance * PLAYER_TO_CAMERA_RATIO;

        LISTENER_MIN_DISTANCE_FROM_PLAYER :: 1.5;
        if listener_distance < LISTENER_MIN_DISTANCE_FROM_PLAYER listener_distance = LISTENER_MIN_DISTANCE_FROM_PLAYER;
        if listener_distance > player_to_camera_distance listener_distance = player_to_camera_distance;

        // The listener position is somewhere between the camera position and the player position.
        listener_position := player_position + normalize(player_to_camera) * listener_distance;


        // @TODO:
        // I am moving on from this part of the audio as of now. However, there
        // are some things I can do to improve audio.
        
        // - Audio attenuation curve: Make sounds fall off in a nicer fashion.
        // In reality, volume decreases by half as distance doubles.
        // I'm sensing that, like realistic graphics, realistic audio is a hole
        // that I don't want to go down because that's not the joy of games
        // for me. We can do a minimal amount of work to get it "good enough",
        // however, any further is excessive.

        // A much more artistically-valid thing to do is to change how sound
        // works specifically to suit the game design I am going for. The original
        // idea for this game was as a stealth game where one of the aspects was
        // being able to hear enemies through walls, and using sound to better
        // inform your decision-making.

        // I do want to continue heading into the idea of having more realtime
        // level elements in this game. As such, I should consider making audio
        // better-suited for that.

        // - Only activate sound effects in the same enclosed space as the
        // player: Using pathfinding to figure out how loud to make the sound
        // seems like overkill, we can just use distance. Perhaps there can be a
        // little audio leakage from one enclosed space, so that if you are standing
        // near a wall and there is something on the other side of the wall,
        // you can hear it. However, this opens a whole can of worms. You start
        // asking, "Hey, shouldn't we put a low-pass filter over the audio to 
        // make it more realistic?". The way you do that on PCM audio is with
        // Fast Fourier Transform, and that opens up a whole can of worms I don't
        // ever want to touch. So we will avoid that.

        //          -berk, 2025 - 4 - 20


        i := 0;
        while true {
            if i == playing_sound_count break;

            sound := *playing_sounds[i];
            sound.current_sample += samples_played;

            if sound.current_sample >= sound.wav.data.count {
                sound.* = playing_sounds[playing_sound_count-1];
                playing_sound_count -= 1;
                continue;
            }

            i += 1;

            end := min(sound.wav.data.count, sound.current_sample + buffer.count);

            if sound.type == {
                case .SIMPLE;
                    for sound.current_sample..end-1 {
                        sample := cast(s32, sound.wav.data[it]);
                        output := *buffer[it - sound.current_sample];

                        l_s32 := cast(s32, output.l) + sample;
                        r_s32 := cast(s32, output.r) + sample;
                        
                        output.l = cast(s16, clamp(r_s32, S16_MIN, S16_MAX));
                        output.r = cast(s16, clamp(l_s32, S16_MIN, S16_MAX));
                    }
                case .POSITIONAL;
                    using sound.positional;
                    
                    MIN_RADIUS :: 2.0;
                    MAX_RADIUS :: 5.0;

                    distance := length(position - listener_position);
                    distance_volume := 1 - clamp((distance - MIN_RADIUS) / (MAX_RADIUS - MIN_RADIUS), 0, 1);
                    
                    if distance_volume > 0 {
                        // This kind of panning is called "constant power panning",
                        // where the pan is calculated as a sine curve that is
                        // 1 when the sound is at the chosen ear and 0 when the
                        // sound is at the opposite ear.
                        
                        // Source:
                        // https://www.cs.cmu.edu/~music/icm-online/readings/panlaws/

                        offset := sound.positional.position - listener_position;
                        rotate(*offset, camera_quat);

                        angle := get_angle(.{0, 1}, .{offset.x, offset.z});

                        // Zero means directly in front of the listener.
                        // PI / 2 means to the left of the listener.
                        // -PI / 2 means to the right of the listener.

                        l_volume := cos((angle - PI/2) / 2);
                        r_volume := cos((angle + PI/2) / 2);

                        l_volume *= distance_volume;
                        r_volume *= distance_volume;

                        if r_volume != 0 || l_volume != 0 {
                            for sound.current_sample..end-1 {
                                in := sound.wav.data[it];
                                sample := cast(float, sound.wav.data[it]);
                                l_sample := cast(s32, sample * l_volume);
                                r_sample := cast(s32, sample * r_volume);
                                
                                output := *buffer[it - sound.current_sample];

                                l_s32 := cast(s32, output.l) + l_sample;
                                r_s32 := cast(s32, output.r) + r_sample;
                                
                                output.l = cast(s16, clamp(l_s32, S16_MIN, S16_MAX));
                                output.r = cast(s16, clamp(r_s32, S16_MIN, S16_MAX));
                            }
                        }
                }
            }
        }
    }
}
