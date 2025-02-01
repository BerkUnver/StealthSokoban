#import "Math"; // @TODO: DELETE THIS DEPENDENCY!

#load "gl.jai";
#load "shared.jai";
#load "imm.jai";
#load "helpers.jai";
#load "math.jai";
#load "level.jai";
#load "editor.jai";

Game_Context :: struct {
    using gl_procs: GL_Procedures;
    using gl_extensions: GL_Extensions;
    os_print: (string);
    imm_state: Imm_State;

    block_shader: GLuint;
    block_bitmap: GLuint;
    color_shader: GLuint;
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

#program_export "game_init"
game_init : Game_Init : (
    game_memory_: *void,
    game_memory_size: u64,
    gl_extension_loader: (*u8) -> *void #c_call,
    os_print_: (string),
    level_arena_memory: *void
) #no_context {
    game_memory := cast(*Game_Memory, game_memory_);
    push_context {
        assert(game_memory_size >= size_of(Game_Memory));

        context.game_context = *game_memory.game_context;
        using context.game_context;


        
        os_print = os_print_;

        for * type_info(GL_Procedures).members {
            if it.flags & .CONSTANT continue; // OpenGL procs from versions 1.0 and 1.1 are constant because that's when they were introduced to windows.
            assert((it.flags & .PROCEDURE_WITH_VOID_POINTER_TYPE_INFO) != 0);

            // Works whether or not address is null.
            address := gl_extension_loader(it.name.data);
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

        level_arena = make_arena(level_arena_memory, LEVEL_ARENA_SIZE);

        block_shader = register_shader(BLOCK_SHADER);
        assert(block_shader != 0);
        color_shader = register_shader(PLAYER_SHADER);
        assert(color_shader != 0);
       
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

        mode = .EDITOR;
        test_level_init(*level, *level_arena);

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
        
        for input.events {
            if it.key == Key.F_BASE + 1 && it.down {

                clear_arena(*level_arena);
                memset(*level, 0, size_of(type_of(level)));

                if mode == .GAME {
                    mode = .EDITOR;
                    test_level_init(*level, *level_arena);
                    editor = .{};
                } else {
                    mode = .GAME;
                    test_level_init(*level, *level_arena);
                }
            } else {
                if #complete mode == {
                    case .GAME;
                        level_handle_input(*level, it);
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


        // :GLDebugProcHotloadingHack
        // We need the GL callback to tank being hotloaded, so we load it, then unload it, every frame.
        stack_context := context;
        if GL_ARB_debug_output glDebugMessageCallbackARB(gl_debug_callback, *stack_context);

        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
        

        imm_state.projection = get_camera_matrix(*level); // Is it really a good idea to rely on no one changing this?
        // Is it a good idea to draw when we update the editor?
        // Maybe...
        // @TODO: We should print the current editor mode in the top-left of the screen for clarity.
        if mode == .EDITOR editor_update(*level, *editor, input.mouse_x, input.mouse_y, dt);
        // @TODO This is dumb. Just in case the projection changes during the editor update. Remove.
        imm_state.projection = get_camera_matrix(*level); // Is it really a good idea to rely on no one changing this?

        using level;
        
        // @TODO: Pull these out into separate routines
        imm_state.shader = block_shader;
        imm_state.bitmap = block_bitmap;

        for blocks {
            for :iterate_vector3i coord: it.size {
                filled := it.filled[it_index];
                if !filled continue;
                begin := to_vector3(it.position + coord);
                end := begin + Vector3.{1,1,1};
                imm_cuboid_with_uvs(begin, end, it.color);
            }
        }

        imm_flush();
        
        
        player_corner := to_vector3(player_position);
        player_begin := player_corner + Vector3.{0.2, 0.2, 0.2};
        player_end   := player_corner + Vector3.{0.8, 0.8, 0.8};

        imm_state.shader = color_shader;
        imm_cuboid(player_begin, player_end, .{1, 1, 1, 1});

        imm_flush();

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
                coord := to_vector3i(position) - col.position;
                if !inside_positive_bounding_box(coord, col.size) return false;

                index := convert_3d_coordinate_to_index(coord, col.size);
                
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

        imm_flush();

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




BLOCK_SHADER :: #string END
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
