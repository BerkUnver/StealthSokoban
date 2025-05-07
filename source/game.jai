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
#load "sound.jai";
#load "math.jai";
#load "entities.jai";
#load "level.jai";
#load "editor.jai";
#load "serialize.jai";
#load "table.jai";
#load "assets.jai";
#load "test.jai";

#if OS == .WINDOWS {
    #load "windows_game.jai";
} else {
    #assert false;
}

Game_Context :: struct {
    using gl_procs: GL_Procedures;
    using gl_extensions: GL_Extensions;
    
    keys_down: [] bool;

    frame_arena: *Memory_Arena;
    permanent_arena: *Memory_Arena;
    
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

    viewport_w: int;
    viewport_h: int;
    
    editor_imgui_disabled: bool;
  


    asset_table: Asset_Table;

    imm_color_shader: Shader;
    imm_text_shader: Shader;
    imm_saturation_value_shader: Shader;
    imm_hue_shader: Shader;
    gameplay_gridlike_shader: Shader;
    editor_gridlike_shader: Shader;
    color_shader: Shader;
    wireframe_shader: Shader;
    bitmap_shader: Shader;
    item_and_color_shader: Shader;
    item_and_bitmap_shader: Shader;
    occlusion_shader: Shader;

    consolas_small: Font;
    consolas_large: Font;

    footstep: *Sound;
    gridlike_bitmap: *Bitmap;
    gridlike_outline_bitmap: *Bitmap;
    enemy_mesh: *Mesh;
    enemy_left_bitmap: *Bitmap;
    enemy_right_bitmap: *Bitmap;
    enemy_annihilation_mesh: Mesh;
    enemy_spawner_mesh: *Mesh;
    enemy_despawner_mesh: *Mesh;
    enemy_item_bitmap: *Bitmap;
    player_mesh: *Mesh;
    player_bitmap: *Bitmap;
    player_item_bitmap: *Bitmap;
    exit_mesh: *Mesh;
    overworld_entrance_mesh: *Mesh;
    overworld_entrance_sound: *Sound;
    chroma_key_bitmap: *Bitmap;
    overworld_exit_mesh: *Mesh;
    checkpoint_mesh: *Mesh;
}

#add_context game_context: *Game_Context;

Game_Memory :: struct {
    game_context: Game_Context;

    mode: Game_Mode;
    gameplay: Gameplay;

    editor_level: *Level;
    editor_arena: *Memory_Arena;
}


Game_Mode :: enum {
    GAMEPLAY;
    EDITOR;
}


Gameplay :: struct {
    arena: *Memory_Arena;
    
    state: Gameplay_State;
    overworld: *Level;
    sublevel: *Level;
    dt_modifier: float;
    sublevel_exists: bool;

    paused: union {
        overworld: struct {
            selected: Paused_Overworld_Selection;
        }
        sublevel: struct {
            selected: Paused_Sublevel_Selection;
        }
    } 
}


Gameplay_State :: enum {
    PLAYING;
    PAUSED;
}


// This does not take ownership of "name".
push_sublevel :: (using gameplay: *Gameplay, name: string, skip_intro := false) {
    assert(!sublevel_exists);
    sublevel_exists = true;
    sublevel = load_level_gameplay(name, arena, skip_intro=skip_intro);
}


pop_sublevel :: (using gameplay: *Gameplay, skip_intro := false) {
    assert(sublevel_exists);
    free_level(sublevel, arena);
    assert(arena.current == overworld.checkpoint_block.count + overworld.self_block.count);
    sublevel_exists = false;
    
    if !skip_intro {
        set_state(overworld, .FADE_IN);
        player := *overworld._Player[0];
        set_state(player, .SPAWNING);
    }
}


set_state :: (using gameplay: *Gameplay, new_state: Gameplay_State) {
    if #complete new_state == {
        case .PLAYING;
           state = new_state; 
        case .PAUSED;   
            paused = .{};
            state = new_state;
    }
}


Paused_Sublevel_Selection :: enum {
    RESUME;
    PREVIOUS_CHECKPOINT;
    OVERWORLD;
    RESET_DEMO;
    COUNT;
}


Paused_Overworld_Selection :: enum {
    RESUME;
    RESET_DEMO;
    COUNT;
}



NEAR_PLANE :: 0.1;
FAR_PLANE :: 1000.0;

OVERWORLD :: "levels/overworld.level";

#program_export "game_init"
game_init : Game_Init_Proc : (context_base: *Context_Base, data: *Game_Init_Data) -> *void #no_context {
    push_context {
        game_memory := alloc(data.permanent_arena, Game_Memory); // This should already be zero-initted, right?

        context.base = context_base.*;
        context.game_context = *game_memory.game_context;
        
        using context.game_context;

        frame_arena = data.frame_arena;
        permanent_arena = data.permanent_arena;
        
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
        if GL_ARB_debug_output {
            glEnable(GL_DEBUG_OUTPUT_SYNCHRONOUS); // @Investigate
            // Make sure we do not have to also call glEnable(GL_DEBUG_OUTPUT);
        } else {
            print("glDebugMessageCallbackARB was not found\n.");
        }

        hotloaded_dll_init(false);
        // This hotloaded_dll_init has freetype loading code, it needs to happen
        // before window_resize_init, which has font loading code.

        window_resize_init(data.window_w, data.window_h, false);
        
        // We only ever set this stuff once.
        glClearColor(70.0/256.0, 85.0/256.0, 131.0/256.0, 1);
        glEnable(GL_SCISSOR_TEST); // :ClearAndScissor
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        glStencilFunc(GL_NOTEQUAL, 1, 0xFF);
        glStencilMask(0xFF);
        glStencilOp(GL_KEEP, GL_KEEP, GL_REPLACE);


        success:, shader_include = read_file("shaders/include.gl", permanent_arena);
        assert(success);

        imm_state = imm_init();

        
        asset_table = make_asset_table();

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

        footstep                    = load_asset(Sound, *asset_table, "sounds/footstep.wav");
        gridlike_bitmap             = load_asset(Bitmap, *asset_table, "gridlike.tga");
        gridlike_outline_bitmap     = load_asset(Bitmap, *asset_table, "gridlike_outline.tga");
        enemy_mesh                  = load_asset(Mesh, *asset_table, "enemy.my_mesh");
        enemy_left_bitmap           = load_asset(Bitmap, *asset_table, "enemy_left.tga");
        enemy_right_bitmap          = load_asset(Bitmap, *asset_table, "enemy_right.tga");
        enemy_annihilation_mesh     = make_cuboid_vertex_mesh(.{0.01, 0.01, 0.01}, .{0.99, 0.99, 0.99}, permanent_arena);
        enemy_spawner_mesh          = load_asset(Mesh, *asset_table, "enemy_spawner.my_mesh");
        enemy_item_bitmap           = load_asset(Bitmap, *asset_table, "enemy_item.tga");
        enemy_despawner_mesh        = load_asset(Mesh, *asset_table, "enemy_despawner.my_mesh");
        overworld_entrance_mesh     = load_asset(Mesh, *asset_table, "overworld_entrance.my_mesh");
        overworld_entrance_sound    = load_asset(Sound, *asset_table, "sounds/overworld_entrance.wav");
        chroma_key_bitmap           = load_asset(Bitmap, *asset_table, "chroma_key.tga");
        overworld_exit_mesh         = load_asset(Mesh, *asset_table, "overworld_exit.my_mesh");
        exit_mesh                   = load_asset(Mesh, *asset_table, "exit.my_mesh");
        player_item_bitmap          = load_asset(Bitmap, *asset_table, "player_item.tga");
        checkpoint_mesh             = load_asset(Mesh, *asset_table, "checkpoint.my_mesh");
        player_mesh                 = load_asset(Mesh, *asset_table, "player.my_mesh");
        player_bitmap               = load_asset(Bitmap, *asset_table, "player.tga");


        //
        // Now that the game_context is initted, we can init the game.
        //

        using game_memory;

        editor_arena = data.editor_arena;
        gameplay.arena = data.gameplay_arena;
        
        
        editor_level = load_level_editor(OVERWORLD, editor_arena);
        
        gameplay.dt_modifier = 1;
        gameplay.overworld = load_level_gameplay(OVERWORLD, gameplay.arena);
        
        mode = .GAMEPLAY;

        return game_memory;
    }
}


// I wish we didn't need to have a procedure like this.
// However, some libraries we use have globals that 
// get reset when we hotload, and the imgui uses the
// code loc to store the active widget, and those
// numbers could change, so we have to reset that.
hotloaded_dll_init :: (already_initted: bool) {
    using context.game_context;
    stbi_set_flip_vertically_on_load(1);
    stbi_flip_vertically_on_write(1);
    if GL_ARB_debug_output glDebugMessageCallbackARB(gl_debug_callback, context.game_context);
    imgui_state.active_widget_exists = false;
    
    // @Leak!
    // Freetype does NOT like dll hotloading!
    // If we use the old FT_Library, it crashes the program whenever you try to use it.
    // I assume this is because it stores some kind of global state needed to free it.
    // The thing to do would be to:
    //      1.) Make a pre_dll_hotload and post_dll_hotload in game dll for the exe to call
    //      2.) Write our own font loading
    //      3.) Prebake our font textures
    //      4.) Use another library with no globals (stbtt?)

    // if already_initted {
    //     assert(FT_Done_FreeType(freetype) == 0);
    // }

    assert(FT_Init_FreeType(*freetype) == 0);
}


window_resize_init :: (new_window_w: int, new_window_h: int, already_initted: bool) {
    using context.game_context;

    old_viewport_h := viewport_h;
    
    // Make the inner window 16x9.
    
    // :FontScaling we use 45 and 80 instead of 9 and 16 so the fonts
    // always cleanly increment in size by at least an integer value.

    viewport_w = new_window_w / 80 * 80;
    viewport_h = new_window_h / 45 * 45;
    
    if viewport_w / 16 * 9 < viewport_h {
        viewport_h = viewport_w / 16 * 9;
    } else {
        viewport_w = viewport_h / 9 * 16;
    }

    viewport_x := (new_window_w - viewport_w) / 2;
    viewport_y := (new_window_h - viewport_h) / 2;

    x := cast(s32, viewport_x);
    y := cast(s32, viewport_y);
    w := cast(u32, viewport_w);
    h := cast(u32, viewport_h);

    glViewport(x, y, w, h);
    // :ClearAndScissor we need to set a scissor rect to prevent glClear from
    // clearing the entire window instead of just what we need it to clear.
    glScissor(x, y, w, h);

    // Don't resize fonts unless we absolutely need to
    if already_initted && old_viewport_h == viewport_h return;

    zoom_in_matrix := Matrix4_Identity;
    zoom_in_matrix._11 /= viewport_w / 2;
    zoom_in_matrix._22 /= -viewport_h / 2;
    ui_to_camera = make_translation_matrix4(.{-1, 1, 0}) * zoom_in_matrix;

    zoom_out_matrix := Matrix4_Identity;
    zoom_out_matrix._11 *= viewport_w / 2;
    zoom_out_matrix._22 *= -viewport_h / 2;
    camera_to_ui = zoom_out_matrix * make_translation_matrix4(.{1, -1, 0});
    
    
    if already_initted {
        free_font(*consolas_small);
        free_font(*consolas_large);
    }

    
    // :FontScaling
    BASE :: 0.0222222;
    
    // font_height_in_pixels = 16 at 720p
    // font_height_in_pixels = 24 at 1080p
    // font_height_in_pixels = 32 at 1440p
    // font_height_in_pixels = 48 at 2160p

    font_height_in_pixels := cast(int, round(BASE * viewport_h));
    
    consolas_small = load_font("consolas.ttf", font_height_in_pixels);
    consolas_large = load_font("consolas.ttf", font_height_in_pixels * 2);
}



#program_export "game_update"
game_update : Game_Update : (
    context_base: *Context_Base,
    game_memory_: *void, 
    input: Input,
    dt: float,
    hotloaded: bool,
    changed_file_names: [] string,
    new_window_w: int,
    new_window_h: int
) #no_context {
    game_memory := cast(*Game_Memory, game_memory_);
    push_context {
        context.base = context_base.*;
        context.game_context = *game_memory.game_context;

        if hotloaded {
            hotloaded_dll_init(true);
            log(.OK, "Game DLL has been hotloaded.\n");
        }

        using game_memory;
        using game_memory.game_context;

        window_resize_init(new_window_w, new_window_h, true);

        reload_assets(*asset_table, changed_file_names);
        
        // :ClearAndScissor
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);

        mouse := Vector2.{input.mouse_x, input.mouse_y};
        
        imgui_state.event_count = 0;
        imgui_state.mouse = (camera_to_ui * Vector4.{mouse.x, mouse.y, 0, 1}).xy;

        imgui_position := Vector2.{0, 0};
        imgui_size := Vector2.{viewport_w / 4.0, xx viewport_h};
        
        // Instead of using different focusing systems for the editor and imgui,
        // we could have a #caller_location-based focusing system for everything,
        // and not have to check both the 3d editor and the imgui like we do here.
        // However, I don't know if this is the clearly better option yet, so I am
        // going to leave it.
        //          -berk, 2025 - 3 - 15


        screenshot_requested: bool;
        
        for input.events {
            
            #if DEVELOPER {
                if it.key == .TILDE && it.state == .DOWN {
                    if #complete mode == {
                        case .GAMEPLAY; 
                            mode = .EDITOR;
                            enable_cursor(true);
                        case .EDITOR;
                            mode = .GAMEPLAY;
                            enable_cursor(false);
                    }
                    continue;
                }

                if it.key == #char "C" && it.state == .DOWN && keys_down[Key.CTRL] {
                    screenshot_requested = true;
                    continue;
                }
            
                get_next_level_name :: (old_name: string, ascending: bool) -> string {
                    using context.game_context;

                    Find_Data :: struct {
                        old_name: string;
                        closest_name: string;
                        furthest_name: string;
                        mark: s64;
                        ascending: bool;
                    }

                    find :: (data_: *void, level_name: string) {
                        using context.game_context;
                        using data := cast(*Find_Data, data_);

                        if !closest_name {
                            comparison := strcmp(level_name, old_name);
                            if (ascending && comparison > 0) || (!ascending && comparison < 0) {
                                closest_name = copy_string(frame_arena, level_name);
                            }
                        } else {    
                            closest_name_comparison := strcmp(level_name, closest_name);
                            level_name_comparison := strcmp(level_name, old_name);

                            if (ascending && level_name_comparison > 0 && closest_name_comparison < 0)
                            || (!ascending && closest_name_comparison > 0 && level_name_comparison < 0) {
                                restore_mark(frame_arena, mark);
                                closest_name = copy_string(frame_arena, level_name);
                            }
                        }
                    }

                    data := Find_Data.{
                        old_name = old_name,
                        mark = get_mark(frame_arena),
                        ascending = ascending
                    };


                    iterate_directory("levels", *data, find);

                    return data.closest_name;
                }


                load_next_level_gameplay :: (ascending: bool) #expand {
                    if gameplay.sublevel_exists {
                        scope_mark(frame_arena);
                        closest_name := get_next_level_name(gameplay.sublevel.name, ascending);
                        if !closest_name return;

                        pop_sublevel(*gameplay, skip_intro=true);

                        if closest_name != OVERWORLD {
                            push_sublevel(*gameplay, closest_name, skip_intro=true);
                        }
                    } else {    
                        closest_name := get_next_level_name(gameplay.overworld.name, ascending);
                        if !closest_name return;
                        assert(closest_name != OVERWORLD);

                        push_sublevel(*gameplay, closest_name, skip_intro=true);
                    }
                }


                load_next_level_editor :: (ascending: bool) #expand {
                    closest_name := get_next_level_name(editor_level.name, ascending);
                    if !closest_name return;
                    free_level(editor_level, editor_arena);
                    editor_level = load_level_editor(closest_name, editor_arena);
                }


                if it.key == #char "[" && (it.state == .DOWN || it.state == .REPEAT) {
                    if #complete mode == {
                        case .GAMEPLAY; load_next_level_gameplay(false);
                        case .EDITOR;   load_next_level_editor(false);
                    }
                    continue;
                }

                if it.key == #char "]" && (it.state == .DOWN || it.state == .REPEAT) {
                    if #complete mode == {
                        case .GAMEPLAY; load_next_level_gameplay(true);
                        case .EDITOR;   load_next_level_editor(true);
                    }
                    continue;
                }
            }

            if #complete mode == {
                case .GAMEPLAY;
                    using gameplay;

                    level := ifx sublevel_exists then sublevel else overworld;

                    #if DEVELOPER {
                        if it.key == #char "-" && it.state == .DOWN {
                            if 1.0 / 16.0 < dt_modifier dt_modifier /= 2;
                            continue;
                        }

                        if it.key == #char "=" && it.state == .DOWN {
                            if dt_modifier < 16 dt_modifier *= 2;
                            continue;
                        }

                        if it.key == #char "U" && it.state == .DOWN && keys_down[Key.SHIFT] {
                            for * level._Overworld_Entrance {
                                it.activated = true;
                            }
                            continue;
                        }

                        if it.key == #char "R" && it.state == .DOWN {
                            if sublevel_exists {
                                name := copy_string(frame_arena, sublevel.name);
                                free_level(sublevel, arena);
                                sublevel = load_level_gameplay(name, arena, skip_intro=true);
                            } else {
                                free_level(overworld, arena);
                                overworld = load_level_gameplay(OVERWORLD, arena, skip_intro=true);
                            }
                            continue;
                        }
                    }

                    if #complete state == {
                        case .PLAYING; 

                            if (level.flags & .CHECKPOINT_EXISTS) && it.key == .ESCAPE && it.state == .DOWN {
                                set_state(*gameplay, .PAUSED);
                                continue;
                            }

                            gameplay_handle_input(level, it);
                        case .PAUSED;
                            if it.key == .ESCAPE && it.state == .DOWN {
                                set_state(*gameplay, .PLAYING);
                                continue;
                            }

                            // Should we have an illustration or something that clarifies which inputs
                            // are which in the pause menu?
                            
                            // @Sfx
                            if it.key == #char "W" && it.state == .DOWN {
                                if sublevel_exists {
                                    paused.sublevel.selected = (paused.sublevel.selected - 1 + .COUNT) % .COUNT;
                                } else {
                                    paused.overworld.selected = (paused.overworld.selected - 1 + .COUNT) % .COUNT;
                                }
                                continue;
                            }

                            // @Sfx
                            if it.key == #char "S" && it.state == .DOWN {
                                if sublevel_exists {
                                    paused.sublevel.selected = (paused.sublevel.selected + 1) % .COUNT;
                                } else {
                                    paused.overworld.selected = (paused.overworld.selected + 1) % .COUNT;
                                }
                            }

                            if it.key == #char " " && it.state == .DOWN {
                                if sublevel_exists {
                                    if paused.sublevel.selected == {
                                        case .RESUME;
                                        case .PREVIOUS_CHECKPOINT;
                                            restore_checkpoint(level);
                                        case .OVERWORLD;
                                            pop_sublevel(*gameplay);
                                        case .RESET_DEMO;
                                            pop_sublevel(*gameplay);
                                            free_level(overworld, arena);
                                            assert(arena.current == 0);
                                            overworld = load_level_gameplay(OVERWORLD, arena);
                                    }
                                    set_state(*gameplay, .PLAYING);
                                } else {
                                    if paused.overworld.selected == {
                                        case .RESUME;
                                        case .RESET_DEMO;
                                            free_level(overworld, arena);
                                            assert(arena.current == 0);
                                            overworld = load_level_gameplay(OVERWORLD, arena);
                                    }
                                    set_state(*gameplay, .PLAYING);
                                }
                            }
                    }

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
                        if imgui_state.active_widget_exists || (inside(imgui_position, imgui_size, imgui_state.mouse) && it.key == .MOUSE_LEFT_BUTTON && it.state == .DOWN) {
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
                            arena = editor_arena
                        };

                        munge :: (data_: *void, level_name: string) {
                            print("Munging level \"%\"\n", level_name);
                            // If there is some kind of breaking change that you need to make between versions of the
                            // serialization system, do whatever you need to do here.

                            using data := cast(*Munge_Data, data_);
                            free_level(level_ptr.*, arena);
                            level_ptr.* = load_level_editor(level_name, arena);
                            serialize_level(level_ptr.*);
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

                    editor_handle_input(editor_level, editor_arena, mouse, it);
            }
        }
        

        if #complete mode == {
            case .EDITOR;
                using editor_level;
                editor_update(editor_level, mouse, dt);
                draw(editor_level, .EDITOR);

                if !editor_imgui_disabled {
                    scope_mark(frame_arena);

                    new_level_name: string;

                    set_shader(imm_color_shader, .{flags = .BLEND});
                    set_uniform("projection", ui_to_camera);
                    imm_quad(imgui_position, imgui_size, .{0, 0, 0, 1});
                    imm_flush();

                    font := *consolas_small;
                    item_height := font.ascender * 2;

                    item_size := Vector2.{imgui_size.x, item_height};
                    head := imgui_position;


                    level_name: [STRING_ENTRY_MAX_COUNT] u8;
                    level_name_count: int;

                    assert(level_name.count >= name.count);
                    memcpy(level_name.data, name.data, name.count);
                    level_name_count = name.count;

                    label_length := label("Level", head, item_size);
                    if string_entry(.{head.x + label_length, head.y}, .{item_size.x - label_length, item_size.y}, *level_name, *level_name_count) {
                        data := alloc(frame_arena, level_name_count, zero_init=false);
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
                        e := get_entity(editor_level, editor.selected);
                        type := ENTITIES[e.type];
                        imgui_for_value(e, type, head, item_size, editor_arena);
                    } else {
                        imgui_for_value(editor_level, type_info(Level), head, item_size, editor_arena);
                    }


                    if new_level_name {
                        free_level(editor_level, editor_arena);
                        editor_level = load_level_editor(new_level_name, editor_arena, make_if_not_exists=true);
                    }
                }

            case .GAMEPLAY;
                using gameplay;
                if state == .PLAYING {
                    dt_modified := dt * dt_modifier;
                    if sublevel_exists {
                        gameplay_update(sublevel, dt_modified);

                        if sublevel.state == .FADE_OUT_EXIT {
                            if sublevel.fade_out_exit.interp >= 1 {

                                // We need to copy this because the level is going to get freed
                                // and this will be freed along with it.
                                scope_mark(frame_arena);
                                level_name := copy_string(frame_arena, sublevel.name);

                                pop_sublevel(*gameplay);

                                found := false;

                                for * overworld._Overworld_Exit {
                                    entrance := get_entrance_for_overworld_exit(overworld, it);
                                    if entrance && entrance.level_name == level_name {
                                        entrance.activated = true;

                                        player := *overworld._Player[0];
                                        player.position = it.position;

                                        // @Hack keep the camera focused on the player because otherwise it will fly
                                        // from wherever the player entity was placed in the level to where we want
                                        // the player to spawn.
                                        reset_camera_focus(overworld);

                                        found = true;
                                        break;
                                    }
                                }

                                if !found {
                                    log(.ERROR, "There is no Overworld_Exit that corresponds to the level \"%\".\n", level_name);
                                }
                            }
                        }
                    } else {
                        gameplay_update(overworld, dt_modified);
                        if overworld.state == .FADE_OUT_ENTRANCE {
                            if overworld.fade_out_entrance.interp >= 1 {
                                assert(overworld.fade_out_entrance.eid != 0);
                                e := get_entity(overworld, overworld.fade_out_entrance.eid);
                                entrance := as(e, Overworld_Entrance);

                                assert(entrance != null);
                                assert(entrance.level_name != "");
                                
                                push_sublevel(*gameplay, entrance.level_name);
                            }
                        }
                    }
                }

                if sublevel_exists {
                    draw(sublevel, .GAMEPLAY);
                } else {
                    draw(overworld, .GAMEPLAY);
                }

                if gameplay.state == .PAUSED {
                    h := cast(float, viewport_h) / 1.5;
                    y := cast(float, viewport_h) / 2 - h / 2;


                    x := viewport_w / 2 - h / 2;
                    w := h;

                    set_shader(imm_color_shader, .{flags = .BLEND});
                    set_uniform("projection", ui_to_camera);
                    imm_quad(Vector2.{0, 0}, Vector2.{xx viewport_w, xx viewport_h}, .{0, 0, 0, 0.5});
                    imm_quad(.{x, y}, .{w, h}, .{0, 0, 0, 1});
                    imm_flush();

                    
                    font := *consolas_large;


                    draw_pause_menu :: (selected: $T) #expand {
                        head := y + w / 2 - (T.COUNT - 1) * font.ascender;

                        for 0..T.COUNT-1 {
                            SELECTED_COLOR :: Vector4.{1, 1, 1, 1};
                            UNSELECTED_COLOR :: Vector4.{0.5, 0.5, 0.5, 1};

                            color: Vector4;
                            if it == selected {
                                color = SELECTED_COLOR;
                            } else {
                                color = UNSELECTED_COLOR;
                            }


                            text: string;
                            #if T == Paused_Overworld_Selection {
                                if it == {
                                    case .RESUME;               text = "Resume Playing";
                                    case .RESET_DEMO;           text = "Reset Demo";
                                }
                            } else #if T == Paused_Sublevel_Selection {
                                if it == {
                                    case .RESUME;               text = "Resume Playing";
                                    case .PREVIOUS_CHECKPOINT;  text = "Go to Previous Checkpoint";
                                    case .OVERWORLD;            text = "Return to Overworld";
                                    case .RESET_DEMO;           text = "Reset Demo";
                                }
                            } else {
                                #assert false;
                            }


                            length := text_length(text, font);
                            text_position := round(Vector2.{x + w / 2 - length / 2, head});
                            draw_text(text, text_position, font, color);
                            head += font.ascender * 2;
                        }
                    }

                    if gameplay.sublevel_exists {
                        draw_pause_menu(gameplay.paused.sublevel.selected);
                    } else {
                        draw_pause_menu(gameplay.paused.overworld.selected);
                    }
                }
        }

        #if DEVELOPER {
            if screenshot_requested {
                scope_mark(frame_arena);
                data := alloc(frame_arena, viewport_w * viewport_h * 3, zero_init = false);
                glReadPixels(0, 0, xx viewport_w, xx viewport_h, GL_RGB, GL_UNSIGNED_BYTE, data);
                
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

                stbi_write_png_to_func(write, *context, xx viewport_w, xx viewport_h, 3, data, xx (viewport_w * 3));
                log(.OK, "Screenshot captured.\n");
            }
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



draw :: (using level: *Level, mode: Game_Mode) {
    using context.game_context;

    world_to_camera: Matrix4;
    
    position, size: Vector3i;
    
    // @TODO: Detect when the camera is inside a block, and when it is draw a quad that covers
    // the camera so we don't see geometry from the inside.

    if #complete mode == {
        case .GAMEPLAY;
            camera_position, camera_quat := get_gameplay_camera_info(level);

            FOV :: PI / 5;

            right := cast(float, NEAR_PLANE * tan(FOV / 2));
            top := right * cast(float, viewport_h) / cast(float, viewport_w);
             
            frustum_matrix := make_left_handed_frustum_matrix(-right, -top, NEAR_PLANE, right, top, FAR_PLANE);

            world_to_camera = multiply(frustum_matrix, multiply(rotation_matrix(Matrix4, camera_quat), make_translation_matrix4(-camera_position)));

            position = level_position;
            size = level_size;

            set_shader(gameplay_gridlike_shader);
            set_uniform_bitmap("bitmap", 0, gridlike_bitmap);
            set_uniform_bitmap("outline_bitmap", 1, gridlike_outline_bitmap);
            set_uniform_view_texture("viewed", 2, *view_texture);
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
            world_to_camera = get_editor_camera_matrix(level);
            position, size = get_block_extents(_Block); // :LevelSizeInEditor

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
        set_uniform_view_texture("viewed", 0, *view_texture);
        set_uniform("world_to_camera", world_to_camera);
    }
    
    set_shader(item_and_color_shader);
    set_item_shader_uniforms();


    set_uniform("color", Vector4.{1, 143.0/255.0, 0, 1});
    for mutual_annihilations {
        set_uniform("model_to_world", make_translation_matrix4(to_vector3(it.position)));
        bind_and_draw(*enemy_annihilation_mesh);
    }

    
    set_shader(item_and_bitmap_shader);
    set_item_shader_uniforms();

    for * _Enemy {
        matrix, bitmap := get_enemy_draw_info(level, it);
        set_uniform("model_to_world", matrix);
        set_uniform_bitmap("bitmap", 1, bitmap);
        bind_and_draw(enemy_mesh);
    }

    for * _Enemy_Despawner {
        matrix := make_translation_matrix4(to_vector3(it.position));
        set_uniform("model_to_world", matrix);
        set_uniform_bitmap("bitmap", 1, enemy_item_bitmap);
        bind_and_draw(enemy_despawner_mesh);
    }

         

    
    OVERWORLD_ENTRANCE_DEFAULT_COLOR :: Vector4.{0, 0, 0, 1};
    overworld_entrance_color :: (entrance: *Overworld_Entrance) -> Vector4 #expand {
        player := *_Player[0];
        if #complete mode == {
            case .EDITOR;
                return entrance.color;
            case .GAMEPLAY;
                if entrance.activated || player.position == entrance.position {
                    return entrance.color;
                } else {
                    return OVERWORLD_ENTRANCE_DEFAULT_COLOR;
                }
        }
    }

    set_uniform_bitmap("bitmap", 1, enemy_item_bitmap);
    for * _Enemy_Spawner {
        matrix, color := get_enemy_spawner_draw_info(it); 
        set_uniform("model_to_world", matrix);
        set_uniform("substitute_color", color);
        bind_and_draw(enemy_spawner_mesh);
    }
    
    set_uniform_bitmap("bitmap", 1, chroma_key_bitmap);
    for * _Overworld_Entrance {

        set_uniform("model_to_world", make_translation_matrix4(to_vector3(it.position)));
        set_uniform("substitute_color", overworld_entrance_color(it));
        bind_and_draw(overworld_entrance_mesh);
    }


    set_uniform_bitmap("bitmap", 1, chroma_key_bitmap);
    for * _Overworld_Exit {
        substitute_color := OVERWORLD_ENTRANCE_DEFAULT_COLOR;
        entrance := get_entrance_for_overworld_exit(level, it, log_errors=false);
        if entrance substitute_color = overworld_entrance_color(entrance);

        set_uniform("model_to_world", make_translation_matrix4(to_vector3(it.position)));
        set_uniform("substitute_color", substitute_color);

        bind_and_draw(overworld_exit_mesh);
    }


    set_uniform_bitmap("bitmap", 1, player_item_bitmap);
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
        bind_and_draw(checkpoint_mesh);    
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
        bind_and_draw(player_mesh);
    }

    
    set_uniform("color", Vector4.{0.463, 0.571, 0.796, 0.5});
    for * _Exit {
        set_uniform("projection", translate(world_to_camera, to_vector3(it.position)));
        bind_and_draw(exit_mesh);
    }

    //
    // Draw the player
    //

    // We draw the player after so the player always draws on top
    // of the exit.

    set_shader(item_and_bitmap_shader);
    set_item_shader_uniforms();

    for * _Exit {
        matrix := make_translation_matrix4(to_vector3(it.position));
        set_uniform_bitmap("bitmap", 1, player_item_bitmap);
        set_uniform("model_to_world", matrix);
        bind_and_draw(exit_mesh);
    }


    set_shader(bitmap_shader);
    set_uniform_bitmap("bitmap", 0, player_bitmap);
    for * _Player {
        matrix := world_to_camera * get_player_draw_info(it);
        set_uniform("projection", matrix);
        bind_and_draw(player_mesh);
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
                case .FADE_IN;
                    using fade_in;
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
                scope_mark(frame_arena);

                position, size := get_block_extents(_Block);
                
                overlapping := alloc_view(frame_arena, size.x * size.y * size.z, int);

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
                
                set_shader(wireframe_shader, .{flags = .DEPTH_TEST | .CULL_FACE, polygon_mode = .LINE});
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

        severity_str: string;
        if severity == {
            case GL_DEBUG_SEVERITY_HIGH;            severity_str = "HIGH";
            case GL_DEBUG_SEVERITY_MEDIUM;          severity_str = "MEDIUM";
            case GL_DEBUG_SEVERITY_LOW;             severity_str = "LOW";
            case GL_DEBUG_SEVERITY_NOTIFICATION;    return;
            case; assert(false);
        }

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

        using game_memory;
        using game_memory.game_context;

        if mode != .GAMEPLAY return;

        using level := ifx gameplay.sublevel_exists then gameplay.sublevel else gameplay.overworld;

        player := *_Player[0];
        player_position := to_vector3(player.position) + Vector3.{0.5, 0.5, 0.5};
        camera_position, camera_quat := get_gameplay_camera_info(level);
        
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
            
            // This should catch when the sound is reloaded and the new one is shorter
            // than the old one.

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
