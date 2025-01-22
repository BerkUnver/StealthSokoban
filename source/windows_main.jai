// In debug builds, this should just be a break with a stacktrace.
// In release builds, it should pop up a window and tell the user how to report the bug.
// @TODO: Find out how to disable Runtime_Support
// @TODO: Switch to the wide character version of everything.

#load "windows_winapi.jai";
#load "shared.jai";


windows: struct {
    stdout: HANDLE;
    game_dll: HMODULE;
    input_events: Fixed_Array(INPUT_EVENT_COUNT, Input_Event);
}


main :: () {
    windows.stdout = GetStdHandle(STD_OUTPUT_HANDLE);
    assert(windows.stdout != INVALID_HANDLE_VALUE);
    print("\n\n"); // Some blank lines to separate us from the compile messages

    assert(SetProcessDPIAware() != 0);
    module_handle := GetModuleHandleA(null);

    window_class := WNDCLASSEXA.{
        cbSize = size_of(WNDCLASSEXA),
        style = CS_VREDRAW | CS_HREDRAW | CS_OWNDC,
        lpfnWndProc = xx (window: HWND, message: u32, w_param: WPARAM, l_param: LPARAM) -> LRESULT #c_call {
            push_context .{} {
                translate_keycode_to_game_input :: (keycode: WPARAM) -> bool, Input #no_context {
                    if keycode == #char "W" || keycode == VK_UP    return true, .FORWARD;
                    if keycode == #char "A" || keycode == VK_LEFT  return true, .LEFT;
                    if keycode == #char "S" || keycode == VK_DOWN  return true, .BACKWARD;
                    if keycode == #char "D" || keycode == VK_RIGHT return true, .RIGHT;

                    if keycode == #char "Q" return true, .UP;
                    if keycode == #char "E" return true, .DOWN;

                    if keycode == VK_SPACE return true, .PULL;

                    return false, 0;
                }

                REPEAT_FLAG :: 0x40000000;
                // This flag is 1 if the key was down before the message was sent,
                // and 0 if it was up before the message was sent. Use this to filter
                // out key repeats.

                using windows;
                if message == {
                    // @Investigate: When is the lpfnWndProc called directly?
                    // Can it be called while it is executing? Is this a thread-safety problem,
                    // if it is writing to the input_event queue but then gets interrupted by 
                    // a direct call? The internet seems to say "no" but I'm not getting a
                    // definitive answer.

                    // The common consensus is that this proc only gets called nonqueued from 
                    // SendMessage if it's in the same thread or GetMessage / PeekMessage if it
                    // is not.
                    case WM_KEYDOWN;
                        if (l_param & REPEAT_FLAG) == 0 {
                            success, input := translate_keycode_to_game_input(w_param);
                            if success {
                                event := append(*input_events);
                                if event event.* = .{input=input, down=true};
                            }
                        }
                        return 0;
                    case WM_KEYUP;
                        if (l_param & REPEAT_FLAG) != 0 {
                            success, input := translate_keycode_to_game_input(w_param);
                            if success {
                                event := append(*input_events);
                                if event event.* = .{input=input, down=false};
                            }
                        }
                        return 0;
                    case WM_CLOSE;
                        PostQuitMessage(0);
                        return 0;
                    case; 
                        return DefWindowProcA(window, message, w_param, l_param);
                }
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
    
    SetCurrentDirectoryA("..\\assets\\");

    GAME_MEMORY_SIZE :: 1 << 24; // @TODO: See how much of this memory is actually used!

    game_memory := VirtualAlloc(null, GAME_MEMORY_SIZE, MEM_COMMIT, PAGE_READWRITE);
    windows.game_dll = LoadLibraryA("stealth_sokoban_game.dll"); 
    assert(windows.game_dll != null);
    
    level_arena := VirtualAlloc(null, LEVEL_ARENA_SIZE, MEM_COMMIT, PAGE_READWRITE);
    game_init := cast(Game_Init, GetProcAddress(windows.game_dll, "game_init"));
    assert(game_init != null);
    game_init(game_memory, GAME_MEMORY_SIZE, wglGetProcAddress, print, level_arena);
    
    while main_loop := true {
        message: MSG;

        // @Investigate: Windows documentation mentions that if you do not pass the window handle (HINSTANCE)
        // directly to GetMessage, it gets all the messages for all windows belonging to the current
        // thread, as well as the THREAD message queue.
        // Does this mean that there is a separate message queue for each thread?

        while (PeekMessageA(*message, null, 0, 0, PM_REMOVE)) {
            if message.message == WM_QUIT break main_loop;
            TranslateMessage(*message);
            DispatchMessageA(*message);
        }

        game_update := cast(Game_Update, GetProcAddress(windows.game_dll, "game_update"));
        game_update(game_memory, windows.input_events);
        windows.input_events.count = 0;

        SwapBuffers(dc);
    }
}


print :: (s: string) {
    WriteConsoleA(windows.stdout, s.data, cast(u32, s.count), null, null);
    FlushFileBuffers(windows.stdout); 
    // This function is for debug output. We don't care about performance, so we flush every time we call this.
}
