// @TODO: Find out how to disable Runtime_Support
// @TODO: Switch to the wide character version of everything.

#load "windows_winapi.jai";
#load "windows_xaudio2.jai";
#load "shared.jai";


windows: struct {
    stdout: HANDLE;
    input_events: [MAX_INPUT_EVENTS_PER_TICK] Input_Event;
    input_event_count: s64;
    keys_down: [Key.COUNT] bool; // :BitArray
}

append_input_event :: (e: Input_Event) #no_context {
    using windows;
    keys_down[e.key] = e.down;
    if input_event_count < input_events.count {
        input_events[input_event_count] = e;
        input_event_count += 1;
    }
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
        
                translate_keycode_to_game_input :: (down: bool, keycode: WPARAM) #no_context {
                    using windows;

                    key: Key;

                    if #char "A" <= keycode && keycode <= #char "Z"
                    || #char "0" <= keycode && keycode <= #char "9"
                    || #char " " == keycode {
                        key = xx keycode;
                    } else if 0x6f < keycode && keycode <= 0x7B {
                        key = xx (xx Key.F_BASE + keycode - 0x6f);
                    } else if keycode == VK_LEFT {
                        key = .LEFT_ARROW;
                    } else if keycode == VK_UP {
                        key = .UP_ARROW;
                    } else if keycode == VK_RIGHT {
                        key = .RIGHT_ARROW;
                    } else if keycode == VK_DOWN {
                        key = .DOWN_ARROW;
                    } else if keycode == VK_BACK {
                        key = .BACKSPACE;
                    } else if keycode == VK_DELETE {
                        key = .DELETE;
                    } else if keycode == VK_OEM_3 {
                        key = .TILDE;
                    } else if keycode == VK_OEM_4 {
                        key = #char "[";
                    } else if keycode == VK_OEM_6 {
                        key = #char "]";
                    } else if keycode == VK_OEM_PLUS {
                        key = #char "=";
                    } else if keycode == VK_OEM_MINUS {
                        key = #char "-";
                    // @TODO: Properly handle left and right alts, shifts, and ctrls.
                    } else if keycode == VK_SHIFT {
                        key = .SHIFT;
                    } else if keycode == VK_CONTROL {
                        key = .CTRL;
                    } else return;
                    // @TODO: Handle alt (It is special on windows, and isn't recieved via WM_KEY... messages.

                    append_input_event(.{down=down, key=key});
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
                            translate_keycode_to_game_input(true, w_param);
                        }
                        return 0;
                    case WM_KEYUP;
                        if (l_param & REPEAT_FLAG) != 0 {
                            translate_keycode_to_game_input(false, w_param);
                        }
                        return 0;

                    case WM_LBUTTONDOWN;
                        SetCapture(window);
                        append_input_event(.{key=.MOUSE_LEFT_BUTTON, down=true});
                        return 0;

                    case WM_RBUTTONDOWN;
                        SetCapture(window);
                        append_input_event(.{key=.MOUSE_RIGHT_BUTTON, down=true});
                        return 0;


                    case WM_LBUTTONUP;
                        append_input_event(.{key=.MOUSE_LEFT_BUTTON, down=false});
                        if !keys_down[Key.MOUSE_LEFT_BUTTON] && !keys_down[Key.MOUSE_RIGHT_BUTTON] ReleaseCapture();
                        return 0;
                        
                    case WM_RBUTTONUP;
                        append_input_event(.{key=.MOUSE_RIGHT_BUTTON, down=false});
                        if !keys_down[Key.MOUSE_LEFT_BUTTON] && !keys_down[Key.MOUSE_RIGHT_BUTTON] ReleaseCapture();
                        return 0;

                    case WM_CLOSE;
                        PostQuitMessage(0);
                        return 0;
                    case; 
                }

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
    
    window_x := (GetSystemMetrics(SM_CXSCREEN) - INNER_WINDOW_W) / 2;
    window_y := (GetSystemMetrics(SM_CYSCREEN) - INNER_WINDOW_H) / 2;

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

    wglSwapIntervalEXT := cast((s32) -> BOOL #c_call, wglGetProcAddress("wglSwapIntervalEXT"));
    assert(wglSwapIntervalEXT(1) != 0);



    //
    // Init sound
    //
    
    // As far as I can tell, it would have been better to use WASAPI because I want to mix all our sounds ourself.
    // We don't need any of the WASAPI added functionality. However, we'll just do this for now.

    /*

    xaudio: *IXAudio2;
    assert(XAudio2Create(*xaudio, 0, XAUDIO2_DEFAULT_PROCESSOR) == 0);
  
    mastering_voice: *IXAudio2MasteringVoice;
    assert(xaudio.CreateMasteringVoice(xaudio, *mastering_voice) == 0);

    CHANNEL_COUNT :: 1;
    SAMPLES_PER_SECOND :: 44100;
    BYTES_PER_SAMPLE :: 2;

    format := WAVEFORMATEX.{
        wFormatTag = WAVE_FORMAT_PCM,
        nChannels = CHANNEL_COUNT,
        nSamplesPerSec = SAMPLES_PER_SECOND,
        nBlockAlign = CHANNEL_COUNT * BYTES_PER_SAMPLE, // 2 bytes per sample
        nAvgBytesPerSec = SAMPLES_PER_SECOND * CHANNEL_COUNT * BYTES_PER_SAMPLE,
        wBitsPerSample = 16,
        cbSize = 0
    };
    
    source_voice: *IXAudio2SourceVoice;
    assert(xaudio.CreateSourceVoice(xaudio, *source_voice, *format) == 0);

    audio_buffers: [2][SAMPLES_PER_SECOND / 20] s16;
    audio_buffer_inactive_index := 0;

    first_audio_buffer_submitted := false;
    */

    
    //
    // Init QueryPerformanceCounter stuff
    //

    ticks_per_second_s64: s64;
    assert(QueryPerformanceFrequency(xx *ticks_per_second_s64) != 0);
    ticks_per_second := cast(float64, ticks_per_second_s64);
    

    //
    // Set working directory to exe directory
    //

    { 
        // @TODO: Get rid of MAX_PATH
        exe_path: [MAX_PATH] u8;
        GetModuleFileNameA(null, exe_path.data, exe_path.count);

        index := 0;
        last_path_index := -1;
        second_to_last_path_index := -1;
        while exe_path[index] != #char "\0" {
            if exe_path[index] == #char "\\" {
                second_to_last_path_index = last_path_index;
                last_path_index = index;
            
            }
            index += 1;
        }

        assert(last_path_index >= 0 && second_to_last_path_index >= 0);
        game_path := string.{second_to_last_path_index + 1, exe_path.data};

        assets_path_buf: [MAX_PATH] u8;
        sb := make_string_builder(assets_path_buf);
        print(*sb, "%assets\0", game_path);
        assert(SetCurrentDirectoryA(get_string(*sb).data) != 0);
    }
   

    //
    // Initialize the game state
    //
    

    
    GAME_DLL_NAME_FRESH :: "stealth_sokoban_game_fresh.dll";
    GAME_DLL_NAME :: "stealth_sokoban_game.dll";
    
    dll_attrs := GetFileAttributesA(GAME_DLL_NAME_FRESH);
    if dll_attrs != INVALID_FILE_ATTRIBUTES {
        DeleteFileA(GAME_DLL_NAME);
        assert(MoveFileA(GAME_DLL_NAME_FRESH, GAME_DLL_NAME) != 0);
    }
    game_dll := LoadLibraryA(GAME_DLL_NAME);
    assert(game_dll != null);
    

    game_init := cast(Game_Init_Proc, GetProcAddress(game_dll, "game_init"));
    assert(game_init != null);
    
    game_memory := VirtualAlloc(null, GAME_MEMORY_SIZE, MEM_COMMIT, PAGE_READWRITE);

    data := Game_Init_Data.{
        game_memory            = game_memory,
        gl_extension_loader    = wglGetProcAddress,
        os_procs = .{
            os_print               = os_print,
            read_file              = read_file,
            write_file             = write_file,
            set_console_text_color = set_console_text_color,
        },
        level_arena_memory     = VirtualAlloc(null, LEVEL_ARENA_SIZE, MEM_COMMIT, PAGE_READWRITE),
        frame_arena_memory     = VirtualAlloc(null, FRAME_ARENA_SIZE, MEM_COMMIT, PAGE_READWRITE),
        permanent_arena_memory = VirtualAlloc(null, PERMANENT_ARENA_SIZE, MEM_COMMIT, PAGE_READWRITE),
    };

    game_init(*data);
    
    game_update := cast(Game_Update, GetProcAddress(game_dll, "game_update"));
    assert(game_update != null);

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
        
        new_dll_attrs := GetFileAttributesA(GAME_DLL_NAME_FRESH);
        if new_dll_attrs != INVALID_FILE_ATTRIBUTES {
            if MoveFileA(GAME_DLL_NAME_FRESH, GAME_DLL_NAME_FRESH) == 0 {
                // @Hack this is to prevent us from trying to move the file
                // when the compiler has locked it because it's writing to it.
                assert(cast(u32, GetLastError()) == ERROR_SHARING_VIOLATION);
            } else {
                assert(FreeLibrary(game_dll) != 0);
                assert(DeleteFileA(GAME_DLL_NAME) != 0);
                assert(MoveFileA(GAME_DLL_NAME_FRESH, GAME_DLL_NAME) != 0);
                game_dll = LoadLibraryA(GAME_DLL_NAME);
                assert(game_dll != null);
                game_update = GetProcAddress(game_dll, "game_update");
                assert(game_update != null);
                print("Game DLL has been hotloaded.\n");
            }
        }

        monitor_h := GetSystemMetrics(SM_CYSCREEN);

        client_rect: RECT;
        GetClientRect(window, *client_rect);

        window_top_left := POINT.{0, 0};
        ClientToScreen(window, *window_top_left);
        window_bottom_right := POINT.{x=client_rect.right, y=client_rect.bottom};
        ClientToScreen(window, *window_bottom_right);



        window_w := window_bottom_right.x - window_top_left.x;
        window_h := window_bottom_right.y - window_top_left.y;

        window_x := window_top_left.x;
        window_y := monitor_h - window_bottom_right.y - 1;

        mouse_pos: POINT;
        GetCursorPos(*mouse_pos);

        global_mouse_x := mouse_pos.x;
        global_mouse_y := monitor_h - mouse_pos.y - 1; // Flip so we're in the cartesian plane

        mouse_x := cast(float, global_mouse_x - window_x) / cast(float, window_w) * 2 - 1;
        mouse_y := cast(float, global_mouse_y - window_y) / cast(float, window_h) * 2 - 1;

        input := Input.{
            keys_down = *windows.keys_down,
            events = .{windows.input_event_count, windows.input_events.data},
            mouse_x = mouse_x,
            mouse_y = mouse_y
        };

        ticks_since_start: s64;
        assert(QueryPerformanceCounter(xx *ticks_since_start) != 0);
        time_elapsed := cast(float64, ticks_since_start) / ticks_per_second;



        game_update(game_memory, input, time_elapsed, /* audio_buffers[audio_buffer_inactive_index] */);
        windows.input_event_count = 0;
        
        /*
        
        { // Submit audio data for this frame
            if first_audio_buffer_submitted {
                source_voice.Stop(source_voice);
            } else {
                first_audio_buffer_submitted = true;
            }
            xaudio_audio_buffer := XAUDIO2_BUFFER.{
                Flags = XAUDIO2_END_OF_STREAM,
                AudioBytes = BYTES_PER_SAMPLE * audio_buffers[0].count,
                pAudioData = xx audio_buffers[audio_buffer_inactive_index].data
            };
            source_voice.SubmitSourceBuffer(source_voice, *xaudio_audio_buffer);
            source_voice.Start(source_voice);
            audio_buffer_inactive_index += 1;
            audio_buffer_inactive_index %= audio_buffers.count;
        }*/

        SwapBuffers(dc);
    }
}


print :: (s: string, args: ..Any) {
    buf: [4096] u8;
    sb := make_string_builder(buf);
    print(*sb, s, ..args);
    os_print(get_string(*sb));
}


os_print :: (s: string) {
    WriteConsoleA(windows.stdout, s.data, cast(u32, s.count), null, null);
    FlushFileBuffers(windows.stdout); 
    // This function is for debug output. We don't care about performance, so we flush every time we call this.
}


jai_string_to_path :: (str: string) -> [MAX_PATH] u8 {
    // @TODO: Maybe we can detect when name is a static string (it is zero-terminated) and skip translating it?

    path: [MAX_PATH] u8;
    assert(str.count <= MAX_PATH - 1);
    memcpy(path.data, str.data, str.count);
    path[str.count] = 0;
    return path;
}


// @TODO: Switch to using the Jai allocator-passing method so we can pass an allocator to this without it knowing about memory arenas?
read_file :: (name: string, buf: [] u8) -> bool, string {
    
    path := jai_string_to_path(name);

    handle := CreateFileA(path.data, FILE_GENERIC_READ);
    if handle == INVALID_HANDLE_VALUE return false, .{};
    defer CloseHandle(handle);

    size_l: LARGE_INTEGER;
    assert(GetFileSizeEx(handle, *size_l) != 0);
    assert(size_l.QuadPart < 0x7fffffff);
    size := cast(u32, size_l.QuadPart);
    assert(size <= buf.count);

    read_size: u32;
    ReadFile(handle, buf.data, size, *read_size);
    assert(read_size == size);

    return true, .{size, buf.data};
}


write_file :: (name: string, str: string) -> bool {
    path := jai_string_to_path(name);

    handle := CreateFileA(path.data, FILE_GENERIC_WRITE, creation = CREATE_ALWAYS);
    if handle == INVALID_HANDLE_VALUE return false;
    defer CloseHandle(handle);
    
    bytes_written: u32;
    WriteFile(handle, str.data, xx str.count, *bytes_written, null);
    if bytes_written < str.count return false;

    return true;
}


set_console_text_color :: (color: Console_Text_Color) {
    if #complete color == {
        case .WHITE; SetConsoleTextAttribute(windows.stdout, FOREGROUND_RED | FOREGROUND_GREEN | FOREGROUND_BLUE);
        case .RED;   SetConsoleTextAttribute(windows.stdout, FOREGROUND_RED);
        case .GREEN; SetConsoleTextAttribute(windows.stdout, FOREGROUND_GREEN);
    }
}
