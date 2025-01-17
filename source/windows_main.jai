// In debug builds, this should just be a break with a stacktrace.
// In release builds, it should pop up a window and tell the user how to report the bug.
// @TODO: Find out how to disable Runtime_Support
// @TODO: Switch to the wide character version of everything.

BACKGROUND_R :: 12;
BACKGROUND_G :: 27;
BACKGROUND_B :: 19;

#load "windows_winapi.jai";
#load "shared.jai";


windows: struct {
    stdout: HANDLE;
}

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
                    PostQuitMessage(0);
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
        WS_EX_TOPMOST,
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

    _wglCreateContextAttribsARB: (dc: HDC, hShareContext: HGLRC, attribList: *s32) -> HGLRC #c_call = xx wglGetProcAddress("wglCreateContextAttribsARB");
    assert(_wglCreateContextAttribsARB != null);

    _wglChoosePixelFormatARB: (dc: HDC, piAttribIList: *s32, pfAttribFList: *float, nMaxFormats: u32, piFormats: *s32, nNumFormats: *u32) -> BOOL #c_call = wglGetProcAddress("wglChoosePixelFormatARB");
    assert(_wglChoosePixelFormatARB != null);

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
    assert(_wglChoosePixelFormatARB(
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

    opengl_context := _wglCreateContextAttribsARB(dc, null, attributes.data);
    assert(wglMakeCurrent(dc, opengl_context) != 0);

    //
    // Initialize the game state
    //
    
    GAME_MEMORY_SIZE :: 1 << 24;
    game_memory := VirtualAlloc(null, GAME_MEMORY_SIZE, MEM_COMMIT, PAGE_READWRITE);
    game_dll := LoadLibraryA("stealth_sokoban_game.dll"); 
    assert(game_dll != null);
    
    game_main := cast(Game_Main, GetProcAddress(game_dll, "game_main"));
    assert(game_main != null);
    game_main(game_memory, GAME_MEMORY_SIZE, dc);

}



log :: (s: string) {
    WriteConsoleA(windows.stdout, s.data, cast(u32, s.count), null, null);
    FlushFileBuffers(windows.stdout); 
    // This function is for debug output. We don't care about performance, so we flush every time we call this.
}
