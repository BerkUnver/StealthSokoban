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
    imm_state: Imm_State;

    frame_arena: Memory_Arena;

    block_shader: GLuint;
    block_bitmap: GLuint;
    imm_color_shader: GLuint;
    color_shader: GLuint;
    wireframe_shader: GLuint;
    viewed_shader: GLuint;
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

        // @TODO: Enable OpenGL vsync by calling wglSwapIntervalEXT(1)
       
        imm_init();

        glClearColor(0, 0, 0, 1);
        glEnable(GL_DEPTH_TEST);
        glEnable(GL_CULL_FACE);

       
        //
        // Now that the game_context is initted, we can init the game.
        //


        using game_memory.game;

        // :GLDebugProcHotloadingHack
        stack_context := context;
        if GL_ARB_debug_output glDebugMessageCallbackARB(gl_debug_callback, *stack_context);

        level_arena = make_arena(data.level_arena_memory, LEVEL_ARENA_SIZE);

        block_shader = register_shader(BLOCK_SHADER);
        assert(block_shader != 0);
        imm_color_shader = register_shader(IMM_COLOR_SHADER);
        assert(imm_color_shader != 0);
        color_shader = register_shader(COLOR_SHADER);
        assert(color_shader != 0);
        wireframe_shader = register_shader(WIREFRAME_SHADER);
        assert(wireframe_shader != 0);
        viewed_shader = register_shader(VIEWED_SHADER);
        assert(viewed_shader != 0);
       
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

        for * blocks {
            draw_block_mesh(*it.mesh, translate(world_to_camera, to_vector3(it.position)), it.color);
        }
            
        
        
        if mode ==  {
            case .GAME; 

                glUseProgram(imm_color_shader);
                set_uniform("projection", *world_to_camera);

                for :iterate_vector3i collision.size {
                    if collision.viewed[it_index] & .VISIBLE {
                        begin := to_vector3(collision.position + it);
                        imm_cuboid(begin + Vector3.{0.4, 0.4, 0.4}, begin + Vector3.{0.6, 0.6, 0.6}, .{1, 1, 0, 1});
                    } else if collision.viewed[it_index] & .SEEN {
                        begin := to_vector3(collision.position + it);
                        imm_cuboid(begin + Vector3.{0.4, 0.4, 0.4}, begin + Vector3.{0.6, 0.6, 0.6}, .{0.5, 0.5, 0, 1});
                    }
                }
                imm_flush();

                
                /*
                glUseProgram(viewed_shader);
                
                set_uniform("projection", *world_to_camera);
                set_uniform("viewed", cast(s32, 0));
                set_uniform("viewed_size", collision.texture.size);

                glActiveTexture(GL_TEXTURE0);
                glBindTexture(GL_TEXTURE_BUFFER, collision.texture.tbo);

                imm_quad_y(1, 0, 0, 6, 4);

                imm_flush();
                */

            case .EDITOR;
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


IMM_COLOR_SHADER :: #string END
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


COLOR_SHADER :: #string END
#ifdef VERTEX_SHADER
layout(location=0) in vec3 vertex_position;
#else
layout(location=0) out vec4 fragment_color;
#endif

uniform mat4 projection;
uniform vec4 color;

void main () {
#ifdef VERTEX_SHADER
    gl_Position = projection * vec4(vertex_position, 1.0);
#else
    fragment_color = color;
#endif
}
END


BLOCK_SHADER :: #string END
#ifdef VERTEX_SHADER
layout(location=0) in vec3 vertex_position;
layout(location=1) in vec2 vertex_uv;
#else
layout(location=0) out vec4 fragment_color;
#endif

uniform sampler2D bitmap;
uniform mat4 projection;
uniform vec4 color;

OUTIN vec2 fragment_uv;

void main() {
#ifdef VERTEX_SHADER
    gl_Position = projection * vec4(vertex_position, 1.0);
    fragment_uv = vertex_uv;
#else
    fragment_color = color * texture(bitmap, fragment_uv);
#endif
}
END


WIREFRAME_SHADER :: #string END
#ifdef VERTEX_SHADER
layout(location=0) in vec3 vertex_position;
#else
layout(location=0) out vec4 fragment_color;
#endif

uniform mat4 projection;
uniform vec4 color;

void main() {
#ifdef VERTEX_SHADER
    vec4 position = projection * vec4(vertex_position, 1.0);
    position.z -= 0.0001;
    gl_Position = position;
#else
    fragment_color = color;
#endif
}
END


VIEWED_SHADER :: #string END
#ifdef VERTEX_SHADER
layout(location=0) in vec3 vertex_position;
#else
layout(location=0) out vec4 fragment_color;
#endif

uniform mat4 projection;
uniform usamplerBuffer viewed;
uniform ivec3 viewed_size;

OUTIN vec3 fragment_coordinates;

// @Volatile :ViewState
#define VIEW_STATE_SEEN 1u
#define VIEW_STATE_VISIBLE 2u

void main() {
#ifdef VERTEX_SHADER
    fragment_coordinates = vertex_position;
    gl_Position = projection * vec4(vertex_position, 1.0);
#else
    
    // @TODO: The reason this is flickering so much is because when
    // OpenGL interpolates fragment_coordinates, the value of y
    // dips ever-so-slightly below 1, and then it gets floored to 0.
    // Maybe this won't be an issue once the actual viewing system
    // is working, so it's not work trying to fix right now.
    int x = int(floor(fragment_coordinates.x));
    int y = int(floor(fragment_coordinates.y));
    int z = int(floor(fragment_coordinates.z));

    int index = y * viewed_size.z * viewed_size.x + z * viewed_size.x + x;
    uint filled = texelFetch(viewed, index).r;

    if ((filled & VIEW_STATE_VISIBLE) != 0u) {
        fragment_color = vec4(1, 0, 0, 1);
    } else if ((filled & VIEW_STATE_SEEN) != 0u) {
        fragment_color = vec4(0, 1, 0, 1);
    } else {
        fragment_color = vec4(0, 0, 1, 1);
    }
#endif
}
END
