// @TODO: :Assert Working assert.
// In debug builds, this should just be a break with a stacktrace.
// In release builds, it should pop up a window and tell the user how to report the bug.
// @TODO: Find out how to disable Runtime_Support
// @TODO: Switch to the wide character version of everything.

BACKGROUND_R :: 12;
BACKGROUND_G :: 27;
BACKGROUND_B :: 19;

#import "GL";
// @TODO: REMOVE THIS DEPENDENCY! We do almost everything this does manually, we just need this for the gl extension procs loading.
// @TODO: ALSO MAKE THE GL_PROCS STRUCT PART OF THE GAME STATE SO WE CAN USE DLL HOT-RELOADING!

#load "windows_winapi.jai";
#load "imm.jai";
#load "math.jai";


windows: struct {
    running := true;
}

main :: () {
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

    RegisterClassExA(*window_class); // :Assert
    
    window := CreateWindowExA(
        0,
        "Window Class",
        "Sokoban",
        WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        null,
        null,
        module_handle,
        null
    );
    // :Assert make sure this succeeds

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

    RegisterClassExA(*dummy_window_class); // :Assert

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
    // :Assert make sure this succeeds

    dummy_dc := GetDC(dummy_window);

    dummy_pixel_format_descriptor := PIXELFORMATDESCRIPTOR.{
        nSize = size_of(PIXELFORMATDESCRIPTOR),
        nVersion = 1,
        dwFlags = PFD_SUPPORT_OPENGL | PFD_DRAW_TO_WINDOW | PFD_DOUBLEBUFFER,
        iPixelType = PFD_TYPE_RGBA,
        cColorBits = 24 // Doesn't include the alpha, according to MSDN.
    };

    dummy_pixel_format := ChoosePixelFormat(dummy_dc, *dummy_pixel_format_descriptor);
    // :Assert Make sure this is nonzero
    SetPixelFormat(dummy_dc, dummy_pixel_format, *dummy_pixel_format_descriptor);
    // :Assert Make sure this is nonzero

    // The reason we need a dummy window is because wglCreateContext is legacy.
    // There is new pixel format information we need to set with
    // wglCreateContextAttribsARB. However, this function is an extension, and to
    // call it, we need to have a window with a set pixel format so we can query
    // extensions and get wglCreateContextAttribsARB from the extensions.
    // Bruh.

    dummy_context := wglCreateContext(dummy_dc);
    wglMakeCurrent(dummy_dc, dummy_context);
    // :Assert

    // :Assert make sure all three of these are not null.
    wglCreateContextAttribsARB: (dc: HDC, hShareContext: HGLRC, attribList: *s32) -> HGLRC #c_call = xx wglGetProcAddress("wglCreateContextAttribsARB");

    wglChoosePixelFormatARB: (dc: HDC, piAttribIList: *s32, pfAttribFList: *float, nMaxFormats: u32, piFormats: *s32, nNumFormats: *u32) -> BOOL #c_call = wglGetProcAddress("wglChoosePixelFormatARB");

    // wglGetPixelFormatAttribivARB: (dc: HDC, iPixelFormat: s32, iLayerPlane: s32, nAttributes: u32, piAttributes: *s32, piValues: *s32) -> BOOL #c_call = xx wglGetProcAddress("wglGetPixelFormatAttribivARB");
    // @TODO :MSAA This is used for MSAA. We probably want that in the future.
    
    // According to the example I'm following, once we have the extension functions,
    // we can delete all of the dummy stuff.
    wglMakeCurrent(null, null);
    wglDeleteContext(dummy_context);
    UnregisterClassA(dummy_window_class.lpszClassName, dummy_window_class.hInstance);
    DestroyWindow(dummy_window);




    
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
    wglChoosePixelFormatARB(
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
    ); // :Assert make sure this succeeds

    // :Assert make sure pixel_format is not -1, meaning it is invalid.

    pixel_format_descriptor: PIXELFORMATDESCRIPTOR;
    DescribePixelFormat(dc, pixel_format, size_of(PIXELFORMATDESCRIPTOR), *pixel_format_descriptor); // :Assert nonzero
    
    SetPixelFormat(dc, pixel_format, *pixel_format_descriptor); // :Assert nonzero

    attributes := s32.[
        xx WGL_CONTEXT_MAJOR_VERSION_ARB, 3,
        xx WGL_CONTEXT_MINOR_VERSION_ARB, 3,
        xx WGL_CONTEXT_PROFILE_MASK_ARB, xx WGL_CONTEXT_CORE_PROFILE_BIT_ARB,
        xx WGL_CONTEXT_FLAGS_ARB, xx WGL_CONTEXT_DEBUG_BIT_ARB,
        0, 0
    ];

    opengl_context := wglCreateContextAttribsARB(dc, null, attributes.data);
    wglMakeCurrent(dc, opengl_context); // :Assert nonzero


    //
    // Done with the OpenGL init. Now we can start the message loop.
    //

    // @TODO: Enable OpenGL vsync by calling wglSwapIntervalEXT(1)
    // @TODO: Install an OpenGL debug message handler with glDebugMessageCallbackARB.
    // It's an extension until OpenGL 4.3, and we want to support only up until 3.3.
    // So we need to deal with that.
    
    gl_load(*gl);
    glClearColor(BACKGROUND_R/255.0, BACKGROUND_G/255.0, BACKGROUND_B/255.0, 1);
    glViewport(0, 0, 100, 100);
    glEnable(GL_DEPTH_TEST);

    imm_state := imm_init();

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
        imm_rect(*imm_state, -0.5, 0.5, 0.5, 0.5, .{0, 0, 0, 1});
        imm_end(*imm_state);
        SwapBuffers(dc);
    }
}
