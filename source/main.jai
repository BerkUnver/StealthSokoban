// In debug builds, this should just be a break with a stacktrace.
// In release builds, it should pop up a window and tell the user how to report the bug.
// @TODO: Find out how to disable Runtime_Support
// @TODO: Switch to the wide character version of everything.

BACKGROUND_R :: 12;
BACKGROUND_G :: 27;
BACKGROUND_B :: 19;

#load "imm.jai";
#load "helpers.jai";
#load "math.jai";
#load "gl.jai";
#load "windows_winapi.jai";


windows: struct {
    running := true;
    stdout: HANDLE;
}

using gl_procs: GL_Procedures;
using gl_extensions: GL_Extensions;
imm_state: Imm_State;

main :: () {
    windows.stdout = GetStdHandle(STD_OUTPUT_HANDLE);
    assert(windows.stdout != INVALID_HANDLE_VALUE);
    log("\n\n"); // Some blank lines to separate us from the compile messages

    assert(SetProcessDPIAware() != 0);
    module_handle := GetModuleHandleA(null);

    window_class := WNDCLASSEXA.{
        cbSize = size_of(WNDCLASSEXA),
        style = CS_VREDRAW | CS_HREDRAW | CS_OWNDC,
        lpfnWndProc = xx (window: HWND, message: u32, w_param: WPARAM, l_param: LPARAM) -> LRESULT #c_call {
            if message == {
            case WM_CLOSE;
                // We are using our own quit instead of WM_QUIT.
                windows.running = false;
                return 0;
            case;
                return DefWindowProcA(window, message, w_param, l_param);
            }
        },
        hInstance = module_handle,
        hCursor = LoadCursorA(null, IDC_ARROW),
        hbrBackground = CreateSolidBrush((BACKGROUND_B << 16) | (BACKGROUND_G << 8) | BACKGROUND_R),
        lpszClassName = "Window Class", // Jai string literals are zero-terminated for backwards-compatability.
    };

    assert(RegisterClassExA(*window_class) != 0);
    

    //
    // Get the coordinates to center the window
    //

    // @TODO: Support fullscreen, changing the window size
    WINDOW_FLAGS :: WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX;
    // This is WS_OVERLAPPEDWINDOW without the WS_MAXIMIZEBOX and WS_THICKFRAME.
    // Supposedly this is to prevent you from resizing

    INNER_WINDOW_W :: 1920;
    INNER_WINDOW_H :: 1080;
    
    monitor_w := GetSystemMetrics(SM_CXSCREEN);
    monitor_h := GetSystemMetrics(SM_CYSCREEN);
    
    window_x := (monitor_w - INNER_WINDOW_W) / 2;
    window_y := (monitor_h - INNER_WINDOW_H) / 2;

    rect := RECT.{
        right = INNER_WINDOW_W,
        bottom = INNER_WINDOW_H,
    };

    AdjustWindowRect(*rect, WINDOW_FLAGS, .FALSE);
    window_w := rect.right - rect.left;
    window_h := rect.bottom - rect.top;

    window := CreateWindowExA(
        0,
        "Window Class",
        "Sokoban",
        WINDOW_FLAGS,
        xx window_x,
        xx window_y,
        xx window_w,
        xx window_h,
        null,
        null,
        module_handle,
        null
    );
    assert(window != null);

    ShowWindow(window, SW_SHOW);






    // 
    // Begin the OpenGL init process
    //


    dummy_window_class := WNDCLASSEXA.{
        cbSize = size_of(WNDCLASSEXA),
        style = CS_OWNDC,
        lpfnWndProc = xx DefWindowProcA,
        hInstance = module_handle,
        lpszClassName = "Dummy GL Window Class"
    };

    assert(RegisterClassExA(*dummy_window_class) != 0);

    dummy_window := CreateWindowExA(
        0,
        dummy_window_class.lpszClassName,
        "Dummy GL Window",
        0,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        null,
        null,
        module_handle,
        null
    );
    assert(dummy_window != null);

    dummy_dc := GetDC(dummy_window);

    dummy_pixel_format_descriptor := PIXELFORMATDESCRIPTOR.{
        nSize = size_of(PIXELFORMATDESCRIPTOR),
        nVersion = 1,
        dwFlags = PFD_SUPPORT_OPENGL | PFD_DRAW_TO_WINDOW | PFD_DOUBLEBUFFER,
        iPixelType = PFD_TYPE_RGBA,
        cColorBits = 24 // Doesn't include the alpha, according to MSDN.
    };

    dummy_pixel_format := ChoosePixelFormat(dummy_dc, *dummy_pixel_format_descriptor);
    assert(dummy_pixel_format != 0);
    assert(SetPixelFormat(dummy_dc, dummy_pixel_format, *dummy_pixel_format_descriptor) != 0);

    // The reason we need a dummy window is because wglCreateContext is legacy.
    // There is new pixel format information we need to set with
    // wglCreateContextAttribsARB. However, this function is an extension, and to
    // call it, we need to have a window with a set pixel format so we can query
    // extensions and get wglCreateContextAttribsARB from the extensions.
    // Bruh.

    dummy_context := wglCreateContext(dummy_dc);
    assert(wglMakeCurrent(dummy_dc, dummy_context) != 0);

    wglCreateContextAttribsARB: (dc: HDC, hShareContext: HGLRC, attribList: *s32) -> HGLRC #c_call = xx wglGetProcAddress("wglCreateContextAttribsARB");
    assert(wglCreateContextAttribsARB != null);

    wglChoosePixelFormatARB: (dc: HDC, piAttribIList: *s32, pfAttribFList: *float, nMaxFormats: u32, piFormats: *s32, nNumFormats: *u32) -> BOOL #c_call = wglGetProcAddress("wglChoosePixelFormatARB");
    assert(wglChoosePixelFormatARB != null);

    // wglGetPixelFormatAttribivARB: (dc: HDC, iPixelFormat: s32, iLayerPlane: s32, nAttributes: u32, piAttributes: *s32, piValues: *s32) -> BOOL #c_call = xx wglGetProcAddress("wglGetPixelFormatAttribivARB");
    // assert(wglGetPixelFormatAttribivARB != null);
    // @TODO :MSAA This is used for MSAA. We probably want that in the future.
    
    // According to the example I'm following, once we have the extension functions,
    // we can delete all of the dummy stuff.
    assert(wglMakeCurrent(null, null) != 0);
    assert(wglDeleteContext(dummy_context) != 0);
    assert(DestroyWindow(dummy_window) != 0);
    assert(UnregisterClassA(dummy_window_class.lpszClassName, dummy_window_class.hInstance) != 0);




    
    // wglChoosePixelFormatARB finds all the pixel formats that fulfill
    // every requirement in this list.
    pixel_format: s32 = -1;
    pixel_format_count: u32;
    pixel_format_attributes := s32.[
        WGL_DRAW_TO_WINDOW_ARB,             1,
        WGL_ACCELERATION_ARB,               WGL_FULL_ACCELERATION_ARB,
        WGL_SUPPORT_OPENGL_ARB,             1,
        WGL_DOUBLE_BUFFER_ARB,              1,
        WGL_PIXEL_TYPE_ARB,                 WGL_TYPE_RGBA_ARB,
        WGL_COLOR_BITS_ARB,                 24,
        WGL_ALPHA_BITS_ARB,                 0,
        WGL_DEPTH_BITS_ARB,                 24,

        // @Investigate I think we can omit the ones that can be zero
        WGL_STENCIL_BITS_ARB,               0,
        WGL_ACCUM_BITS_ARB,                 0,
        WGL_AUX_BUFFERS_ARB,                0,
        WGL_FRAMEBUFFER_SRGB_CAPABLE_ARB,   1,
        WGL_SAMPLE_BUFFERS_ARB,             0,
        WGL_SAMPLES_ARB,                    0,
        0, 0
    ];
    
    // We're done with the dummy window. Now, free everything associated with it.
    dc := GetDC(window);
    assert(wglChoosePixelFormatARB(
        dc, 
        piAttribIList = pixel_format_attributes.data,
        // pixel format attributes that are integers
        
        pfAttribFList = null,
        // We don't need floating-point attributes.
        // @Investigate do we want a floating-point depth buffer?
        
        nMaxFormats = 1,
        // We only need this to give us one format.

        piFormats = *pixel_format,
        // The pointer to the actual format

        nNumFormats = *pixel_format_count
        // We only ask for one pixel format so this value should only ever be one.
    ) != 0);
    assert(pixel_format != -1);

    pixel_format_descriptor: PIXELFORMATDESCRIPTOR;
    assert(DescribePixelFormat(dc, pixel_format, size_of(PIXELFORMATDESCRIPTOR), *pixel_format_descriptor) != 0);
    
    assert(SetPixelFormat(dc, pixel_format, *pixel_format_descriptor) != 0);

    attributes := s32.[
        xx WGL_CONTEXT_MAJOR_VERSION_ARB, 3,
        xx WGL_CONTEXT_MINOR_VERSION_ARB, 3,
        xx WGL_CONTEXT_PROFILE_MASK_ARB, xx WGL_CONTEXT_CORE_PROFILE_BIT_ARB,
        xx WGL_CONTEXT_FLAGS_ARB, xx WGL_CONTEXT_DEBUG_BIT_ARB,
        0, 0
    ];

    opengl_context := wglCreateContextAttribsARB(dc, null, attributes.data);
    assert(wglMakeCurrent(dc, opengl_context) != 0);


    //
    // Initialize the game state
    //
    
    for * type_info(GL_Procedures).members {
        assert((it.flags & .PROCEDURE_WITH_VOID_POINTER_TYPE_INFO) != 0);
        
        // Works whether or not address is null.
        address := wglGetProcAddress(it.name.data);
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

    imm_state = imm_init();
   

    //
    // Initialization is done, and now we can start the message loop.
    //


    // @TODO: Enable OpenGL vsync by calling wglSwapIntervalEXT(1)
    glClearColor(0, 0, 0, 1);
    glEnable(GL_DEPTH_TEST);
   
    // We want to support Mac, so we can't support OpenGL 4.3 which is when this
    // extension became part of the standard. As such, we have to use the extension.
    if GL_ARB_debug_output { 
        glEnable(GL_DEBUG_OUTPUT_SYNCHRONOUS); // @Investigate
        // Make sure we do not have to also call glEnable(GL_DEBUG_OUTPUT);
        

        // MAKE SURE THIS STAYS OUT OF THE GAME DLL WHEN WE ADD DLL HOT RELOADING.
        // Or make it dynamically get the right proc out of the game dll?
        // We have to see how often this is called.
        gl_debug_callback :: (source: GLenum, type: GLenum, id: GLuint, severity: GLenum, length: GLsizei, message: *GLchar, userParam: *void) #c_call {
            // @Investigate: Maybe this will notify us when we don't want to hear from it. Keep an eye out.
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


                // :FormatPrint
                log("GL Debug Callback - source: ");
                log(source_str);
                log(", type: ");
                log(type_str);
                log(", severity: ");
                log(severity_str);
                log(", message: ");
                log(message_str);
                log("\n");
            }
        }
        
        glDebugMessageCallbackARB(gl_debug_callback, null);
    } else {
        log("glDebugMessageCallbackARB was not found.");
    }


    message: MSG;

    // @Investigate: Windows documentation mentions that if you do not pass the window handle (HINSTANCE)
    // directly to GetMessage, it gets all the messages for all windows belonging to the current
    // thread, as well as the THREAD message queue.
    // Does this mean that there is a separate message queue for each thread?
    // Investigate further.
    
    while windows.running {
        // @TODO: When we use OpenGL and the window proc is just for gathering input,
        // switch to PeekMessageA so we don't block.
        message_result := GetMessageA(*message, null, 0, 0);
        if (message_result > 0) {
            TranslateMessage(*message);
            DispatchMessageA(*message);

        } else {
            // @TODO: Log when this happens. Something goofy is going on.
            // We shouldn't be getting unsolicited WM_QUIT messages because we handle that manually.
            // This also shouldn't be returning -1 because that is an error condition.
            break;
        }

        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
        imm_begin(*imm_state);
        imm_rect(*imm_state, -0.5, -0.5, 1, 1, .{1, 1, 1, 1});
        imm_end(*imm_state);
        SwapBuffers(dc);
    }
}

log :: (s: string) {
    WriteConsoleA(windows.stdout, s.data, cast(u32, s.count), null, null);
    FlushFileBuffers(windows.stdout); 
    // This function is for debug output. We don't care about performance, so we flush every time we call this.
}


assert :: (condition: bool, message := "", loc := #caller_location) #no_debug #expand {
    // if !message message = "We've detected an error occuring in the game. This is almost definitely our fault. To prevent corruption, the game will crash now.";
    // @TODO: Open a user-level windows MessageBoxA that contains the message in release builds. Telemetry?

    // @Copypasta from modules/Basic
    assert_stack_trace :: (message: string, loc: Source_Code_Location) -> bool {
        if context.handling_assertion_failure  return false;  // Avoid infinite loops.
        context.handling_assertion_failure = true;

        // We provide 'loc' in case _STACK_TRACE is turned off, but assertion_failed may well
        // look at the stack trace if it is available.
        should_break := context.assertion_failed(loc, message);
        context.handling_assertion_failure = false;
        return true;
    }

    if !condition && assert_stack_trace(message, loc) debug_break();
}
