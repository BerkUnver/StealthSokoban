// @BeforeDemo Handle alt and f10 freezing the game until another key is pressed
// @BeforeDemo Disable the mouse while in gameplay mode

// @TODO: Find out how to disable Runtime_Support
// @TODO: Switch to the wide character version of everything.
// @TODO: Handle switching monitors. Right now the window might become weirdly stretched and unresponsive.
// @TODO: Detect keys that were pressed when you alt-tabbed away from this application, then alt-tabbed back.
// @TODO: Handle not rendering while window is being dragged

#load "shared.jai";
#load "windows_winapi.jai";

#program_export NvOptimusEnablement: u32 = 1;
#program_export AmdPowerXpressRequestHighPerformance: s32 = 1;


window: HWND;
keys_down: [Key.COUNT] bool; // :BitArray

append_input_event :: (event: Input_Event) {    
    append(*input_events, *frame_arena).* = event;
    if event.state == .UP {
        keys_down[event.key] = false;
    } else {
        keys_down[event.key] = true;
    }
}

frame_arena: Memory_Arena;
input_events: [..] Input_Event;


// GetClientRect lies to us if the window is minimized
window_minimized: bool;

window_w: int;
window_h: int;

main :: () {
    assert(SetProcessDPIAware() != 0);
    module_handle := GetModuleHandleA(null);

    window_class := WNDCLASSEXA.{
        cbSize = size_of(WNDCLASSEXA),
        style = CS_VREDRAW | CS_HREDRAW | CS_OWNDC,
        lpfnWndProc = xx (window: HWND, message: u32, w_param: WPARAM, l_param: LPARAM) -> LRESULT #c_call {
            push_context {
                translate_keycode_to_game_input :: (state: Input_Event_State, keycode: WPARAM) {
                    key: Key;

                    if #char "A" <= keycode && keycode <= #char "Z"
                    || #char "0" <= keycode && keycode <= #char "9"
                    || #char " " == keycode {
                        key = xx keycode;
                    } else if 0x6f < keycode && keycode <= 0x7B {
                        key = xx (xx Key.F_BASE + keycode - 0x6f);
                    } else if keycode == {
                        case VK_LEFT;       key = .LEFT_ARROW;
                        case VK_UP;         key = .UP_ARROW;
                        case VK_RIGHT;      key = .RIGHT_ARROW;
                        case VK_DOWN;       key = .DOWN_ARROW;
                        case VK_BACK;       key = .BACKSPACE;
                        case VK_DELETE;     key = .DELETE;
                        case VK_OEM_1;      key = #char ";";
                        case VK_OEM_2;      key = #char "/";
                        case VK_OEM_3;      key = .TILDE;
                        case VK_OEM_4;      key = #char "[";
                        case VK_OEM_5;      key = #char "\\";
                        case VK_OEM_6;      key = #char "]";
                        case VK_OEM_7;      key = #char "'";
                        case VK_OEM_PLUS;   key = #char "=";
                        case VK_OEM_MINUS;  key = #char "-";
                        case VK_OEM_COMMA;  key = #char ",";
                        case VK_OEM_PERIOD; key = #char ".";
                        case VK_TAB;        key = .TAB;    
                        case VK_RETURN;     key = .ENTER;
                        case VK_ESCAPE;     key = .ESCAPE;
                            // @TODO: Properly handle left and right alts, shifts, and ctrls.
                        case VK_SHIFT;      key = .SHIFT;
                        case VK_CONTROL;    key = .CTRL;
                        case VK_HOME;       key = .HOME;
                        case VK_END;        key = .END;
                        case;
                            return;
                            // @TODO: Handle alt, f10 (they is special on windows, and isn't recieved via WM_KEY... messages).
                    }
                    append_input_event(.{key=key, state=state});
                }


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
                        // This flag is 1 if the key was down before the message was sent,
                        // and 0 if it was up before the message was sent. Use this to filter
                        // out key repeats.
                        KEY_WAS_DOWN_FLAG :: 0x40000000;
                        if (l_param & KEY_WAS_DOWN_FLAG) == 0 {
                            translate_keycode_to_game_input(.DOWN, w_param);
                        } else {
                            translate_keycode_to_game_input(.REPEAT, w_param);
                        }
                        return 0;
                    case WM_KEYUP;
                        // Microsoft documentation says that the KEY_WAS_DOWN flag will always be set for 
                        // WM_KEYUP messages.
                        translate_keycode_to_game_input(.UP, w_param);
                        return 0;

                    case WM_LBUTTONDOWN;
                        SetCapture(window);
                        append_input_event(.{key=.MOUSE_LEFT_BUTTON, state=.DOWN});
                        return 0;

                    case WM_RBUTTONDOWN;
                        SetCapture(window);
                        append_input_event(.{key=.MOUSE_RIGHT_BUTTON, state=.DOWN});
                        return 0;


                    case WM_LBUTTONUP;
                        append_input_event(.{key=.MOUSE_LEFT_BUTTON, state=.UP});
                        if !keys_down[Key.MOUSE_LEFT_BUTTON] && !keys_down[Key.MOUSE_RIGHT_BUTTON] ReleaseCapture();
                        return 0;
                        
                    case WM_RBUTTONUP;
                        append_input_event(.{key=.MOUSE_RIGHT_BUTTON, state=.UP});
                        if !keys_down[Key.MOUSE_LEFT_BUTTON] && !keys_down[Key.MOUSE_RIGHT_BUTTON] ReleaseCapture();
                        return 0;

                    case WM_SIZE;
                        if w_param == {
                            case SIZE_MAXIMIZED;
                                window_minimized = false;
                                client_rect: RECT;
                                GetClientRect(window, *client_rect);
                                window_w = client_rect.right;
                                window_h = client_rect.bottom;

                            case SIZE_RESTORED;
                                window_minimized = false;
                                client_rect: RECT;
                                GetClientRect(window, *client_rect);
                                window_w = client_rect.right;
                                window_h = client_rect.bottom;

                            case SIZE_MINIMIZED;
                                window_minimized = true;
                        }
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
        hbrBackground = CreateSolidBrush(0),
        lpszClassName = "Window Class", // Jai string literals are zero-terminated for backwards-compatability.
    };

    assert(RegisterClassExA(*window_class) != 0);
    
    window = CreateWindowExA(
        0,
        "Window Class",
        "Stealth Sokoban",
        0,
        0,
        0,
        0,
        0,
        null,
        null,
        module_handle,
        null
    );
    assert(window != null);
    
    fullscreen := false;

    toggle_fullscreen :: () #expand {
        if fullscreen {
            // @TODO: Pick reasonable values based on the monitor size
            WINDOW_W :: 1280;
            WINDOW_H :: 720;

            outer_window_x := (GetSystemMetrics(SM_CXSCREEN) - WINDOW_W) / 2;
            outer_window_y := (GetSystemMetrics(SM_CYSCREEN) - WINDOW_H) / 2;

            outer_rect := RECT.{
                right = xx WINDOW_W,
                bottom = xx WINDOW_H,
            };

            AdjustWindowRect(*outer_rect, WS_OVERLAPPEDWINDOW, .FALSE);
            outer_window_w := outer_rect.right - outer_rect.left;
            outer_window_h := outer_rect.bottom - outer_rect.top;

            SetWindowLongA(window, GWL_STYLE, WS_OVERLAPPEDWINDOW);

            SetWindowPos(
                window,
                HWND_TOP, 
                xx outer_window_x,
                xx outer_window_y,
                xx outer_window_w,
                xx outer_window_h,
                SWP_FRAMECHANGED | SWP_SHOWWINDOW
            );

            window_w = WINDOW_W;
            window_h = WINDOW_H;

        } else {
            SetWindowLongA(window, GWL_STYLE, 0);
            monitor := MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
            info: MONITORINFO;
            info.cbSize = size_of(type_of(info));

            assert(GetMonitorInfoA(monitor, *info) == .TRUE);
            SetWindowPos(
                window,
                HWND_TOP,
                info.rcMonitor.left,
                info.rcMonitor.top,
                info.rcMonitor.right - info.rcMonitor.left,
                info.rcMonitor.bottom - info.rcMonitor.top,
                SWP_FRAMECHANGED | SWP_SHOWWINDOW
            );

            window_w = info.rcMonitor.right - info.rcMonitor.left;
            window_h = info.rcMonitor.bottom - info.rcMonitor.top;
        }

        fullscreen = !fullscreen;
    }

    toggle_fullscreen();


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
        WGL_STENCIL_BITS_ARB,               8,
        WGL_SAMPLE_BUFFERS_ARB,             0,
        WGL_SAMPLES_ARB,                    0,

        // @Investigate I think we can omit the ones that can be zero
        WGL_ACCUM_BITS_ARB,                 0,
        WGL_AUX_BUFFERS_ARB,                0,
        WGL_FRAMEBUFFER_SRGB_CAPABLE_ARB,   1,
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
    // Init audio
    //

    AUDIO_BUFFER_SIZE :: AUDIO_SAMPLES_PER_SECOND / 2;
    // 0.5 sec of audio data. This is what the Thekla Sound_Player uses.
    // I don't know if this is a good value.

    dsound: *IDirectSound8;
    assert(DirectSoundCreate8(null, *dsound, null) == 0);
    
    dsound.SetCooperativeLevel(dsound, window, DSSCL_PRIORITY);

    primary_buffer_descriptor := DSBUFFERDESC.{
        dwSize        = size_of(DSBUFFERDESC),
        dwFlags       = DSBCAPS_PRIMARYBUFFER,
        dwBufferBytes = 0,
    };
    
    primary_buffer: *IDirectSoundBuffer8;
    assert(dsound.CreateSoundBuffer(dsound, *primary_buffer_descriptor, *primary_buffer, null) == 0);

    wave_format := WAVEFORMATEX.{
        wFormatTag = WAVE_FORMAT_PCM,
        nChannels = 2,
        nAvgBytesPerSec = AUDIO_SAMPLES_PER_SECOND * size_of(Sample),
        nSamplesPerSec = AUDIO_SAMPLES_PER_SECOND,
        nBlockAlign = size_of(Sample),
        wBitsPerSample = 16,
        cbSize = 0
    };

    assert(primary_buffer.SetFormat(primary_buffer, *wave_format) == 0);

    secondary_buffer_descriptor := DSBUFFERDESC.{
        dwSize = size_of(DSBUFFERDESC),
        dwFlags = DSBCAPS_GLOBALFOCUS | DSBCAPS_GETCURRENTPOSITION2 | DSBCAPS_CTRLVOLUME, // @Investigate do we actually need the DSBCAPS_CTRLVOLUME flag? The Jai Sound_Player had it.
        dwBufferBytes = AUDIO_BUFFER_SIZE * size_of(Sample),
        lpwfxFormat = *wave_format
    };

    secondary_buffer: *IDirectSoundBuffer8;
    dsound.CreateSoundBuffer(dsound, *secondary_buffer_descriptor, *secondary_buffer, null);

    
    audio_started: bool; // We only can start the audio if we've got samples once.
    previous_write_sample: int;

    //
    // Init QueryPerformanceCounter stuff
    //

    ticks_per_second_s64: s64;
    assert(QueryPerformanceFrequency(xx *ticks_per_second_s64) != 0);
    ticks_per_second := cast(float64, ticks_per_second_s64);

    time_elapsed: float64;
    
    frame_arena = make_arena(VirtualAlloc(null, FRAME_ARENA_SIZE, MEM_COMMIT, PAGE_READWRITE), FRAME_ARENA_SIZE);

    //
    // Set working directory to exe directory
    //

    { 
        exe_path: [MAX_PATH] u8;
        GetModuleFileNameA(null, exe_path.data, exe_path.count);

        index := 0;
        last_path_index := -1;
     
        while exe_path[index] != #char "\0" {
            if exe_path[index] == #char "\\" {
                last_path_index = index;
            
            }
            index += 1;
        }

        game_path := string.{last_path_index + 2, exe_path.data};
        game_path[game_path.count-1] = #char "\0";
        
        assert(SetCurrentDirectoryA(game_path.data) != 0);
    }


    //
    // Initialize the game state
    //
    

    
    GAME_DLL_NAME_FRESH :: "stealth_sokoban_game_fresh.dll";
    GAME_DLL_NAME :: "stealth_sokoban_game.dll";
    
    dll_attrs := GetFileAttributesA(GAME_DLL_NAME_FRESH);
    if dll_attrs != INVALID_FILE_ATTRIBUTES {
        // :MoveFileAFileWatcher
        assert(CopyFileA(GAME_DLL_NAME_FRESH, GAME_DLL_NAME, .FALSE) != 0);
    }

    game_dll := LoadLibraryA(GAME_DLL_NAME);
    assert(game_dll != null);
    

    game_init := cast(Game_Init_Proc, GetProcAddress(game_dll, "game_init"));
    assert(game_init != null);
    
    gameplay_arena := make_arena(VirtualAlloc(null, GAMEPLAY_ARENA_SIZE, MEM_COMMIT, PAGE_READWRITE), GAMEPLAY_ARENA_SIZE);
    editor_arena := make_arena(VirtualAlloc(null, EDITOR_ARENA_SIZE, MEM_COMMIT, PAGE_READWRITE), EDITOR_ARENA_SIZE);
    permanent_arena := make_arena(VirtualAlloc(null, PERMANENT_ARENA_SIZE, MEM_COMMIT, PAGE_READWRITE), PERMANENT_ARENA_SIZE);

    data := Game_Init_Data.{
        gl_extension_loader    = wglGetProcAddress,
        keys_down = keys_down,
        gameplay_arena = *gameplay_arena,
        editor_arena = *editor_arena,
        frame_arena = *frame_arena,
        permanent_arena = *permanent_arena,
        window_w = window_w,
        window_h = window_h,
    };

    game_memory := game_init(*context.base, *data);

    game_update: Game_Update = xx GetProcAddress(game_dll, "game_update");
    assert(game_update != null);
    game_get_audio_samples: Game_Get_Audio_Samples = xx GetProcAddress(game_dll, "game_get_audio_samples");
    assert(game_get_audio_samples != null);



    //
    // Init the file watcher for game assets
    //
    // Set this up after we load the dll so we don't detect
    // the name changes and deleting the old dll if it exists.
    //

    // We only need to handle files being changed.
    // This ignores things like files / directories being moved, files being deleted, etc.
    // As such, this implementation can be very simple.
    
    dir := CreateFileA(
        ".",
        FILE_LIST_DIRECTORY,
        FILE_SHARE_DELETE | FILE_SHARE_READ | FILE_SHARE_WRITE,
        null,
        OPEN_EXISTING,
        FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OVERLAPPED,
        null
    );
    assert(dir != INVALID_HANDLE_VALUE);

    event := CreateEventA(null, BOOL.FALSE, BOOL.FALSE, null);
    assert(event != null);

    overlapped := OVERLAPPED.{hEvent = event};
    
    // The Windows documentation says that this memory has to be DWORD-aligned.
    // The extra three bytes are so we can make sure it's stack-aligned properly.
    // It appears to always be DWORD-aligned when I compile it but just in case...
    file_notification_memory: [4099] u8; 
    file_notification_ptr := file_notification_memory.data;
    alignment := cast(u64, file_notification_ptr) % 4;
    if alignment != 0 {
        file_notification_ptr += alignment;
    }
    assert(cast(u64, file_notification_ptr) % 4 == 0);

    file_notifications: [] u8 = .{4096, file_notification_ptr};
    
    read_directory_changes :: () #expand {
        assert(ReadDirectoryChangesW(
            dir,
            file_notifications.data,
            xx file_notifications.count,
            .TRUE,
            FILE_NOTIFY_CHANGE_FILE_NAME | FILE_NOTIFY_CHANGE_CREATION | FILE_NOTIFY_CHANGE_DIR_NAME | FILE_NOTIFY_CHANGE_SIZE | FILE_NOTIFY_CHANGE_LAST_WRITE,
            null,
            *overlapped,
            null
        ) == .TRUE);
    }
    read_directory_changes();
    
    // :DynamicArray Hopefully Windows doesn't spam us with file reloaded messages.
    changed_file_memory: [4096] u8;
    changed_file_arena := make_arena(changed_file_memory.data, changed_file_memory.count);
    

    Changed_File :: struct {
        name: string;
        batch_interp: float;
    }

    changed_files: [..] Changed_File;


    while main_loop := true {
        //
        // Do the gameplay update and render
        //

        ticks_since_start: s64;
        assert(QueryPerformanceCounter(xx *ticks_since_start) != 0);
        new_time_elapsed := cast(float64, ticks_since_start) / ticks_per_second;


        //
        // Check for reloaded files.
        //


        if HasOverlappedIoCompleted(overlapped) {
            bytes_transferred: u32;
            success := GetOverlappedResult(dir, *overlapped, *bytes_transferred, .FALSE);
            if success && bytes_transferred != 0 {
               notif := cast(*FILE_NOTIFY_INFORMATION, file_notifications.data);
                while true {
                     // The FILE_NOTIFY_CHANGE_FILE_NAME flag specified when initting the watcher causes it to 
                     // detect file deletions. We don't care about those, but we do care about name changes.
                    
                    if notif.Action != FILE_ACTION_REMOVED && notif.Action != FILE_ACTION_RENAMED_OLD_NAME {
                        mark := get_mark(*changed_file_arena);
                        success, name := utf16_to_ascii(.{notif.FileNameLength / 2, notif.FileName.data}, *changed_file_arena);
                        if !success continue;
                        
                        found := false;
                        for * changed_files {
                            if it.name == name {
                                restore_mark(*changed_file_arena, mark);
                                found = true;
                                break;
                            }
                        }

                        if !found {
                            append(*changed_files, *changed_file_arena).* = .{name = name};
                        }
                    }

                    if notif.NextEntryOffset == 0 break;
                    notif = xx (cast(*u8, notif) + notif.NextEntryOffset);
                }
            }

            read_directory_changes();
        }


        dt: float;
        if time_elapsed == 0 {
            dt = 1.0 / 60.0;
        } else {
            dt = cast(float, new_time_elapsed - time_elapsed);
        }
        time_elapsed = new_time_elapsed;

        {
            assert(frame_arena.current == 0);
            scope_mark(*frame_arena);

            // :InputEventsInFrameArena

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


            for input_events {
                if it.key == Key.F_BASE + 11 && it.state == .DOWN {
                    toggle_fullscreen();

                    // This will REORDER the input events. Do we want that?
                    remove it;
                }
            }


            changed_file_names: [..] string;

            BATCH_TIME :: 1;
            // @Investigate Reaper appears to be locking audio files for a 
            // really long time while generating them. We should figure out why.
            // We should also see if ReadDirectoryChangesW emits an event for
            // changes whether files are locked / unlocked. If so, we could add
            // proper failure cases for asset reloading, and then go back and
            // try again once the file is unlocked.

            for * changed_files {
                it.batch_interp += dt / BATCH_TIME;
                if it.batch_interp >= 1 {
                    append(*changed_file_names, *frame_arena).* = it.name;
                    remove it;
                }
            }


            hotloaded := false;

            for changed_file_names {
                for * it {
                    // Account for Windows path changing
                    if it.* == #char "\\" it.* = #char "/";
                }
                if it != GAME_DLL_NAME_FRESH continue;

                hotloaded = true;
                assert(FreeLibrary(game_dll) != 0);
                assert(CopyFileA(GAME_DLL_NAME_FRESH, GAME_DLL_NAME, .FALSE) != 0);
                // :MoveFileAFileWatcher
                // @Investivate For some reason, deleting the fresh dll fails when using
                // the file watcher! Maybe the thread the watcher is running on (I believe
                // that is what happens when you use ReadDirectoryChangesW) is locking the
                // file, but I have no idea why it would do that. The error message you get
                // from GetLastError() after MoveFileA fails is ERROR_FILE_NOT_FOUND. I
                // have no idea why.

                game_dll = LoadLibraryA(GAME_DLL_NAME);
                assert(game_dll != null);

                game_update = xx GetProcAddress(game_dll, "game_update");
                assert(game_update != null);
                game_get_audio_samples = xx GetProcAddress(game_dll, "game_get_audio_samples");
                assert(game_get_audio_samples != null);

                remove it;
                break;
            }

            //
            // Get the mouse position in Opengl-style coordinates
            //

            mouse_x, mouse_y: float;

            if !window_minimized {
                monitor_h := GetSystemMetrics(SM_CYSCREEN);
                
                // GetClientRect lies to us when the window is minimized
                client_rect: RECT;
                GetClientRect(window, *client_rect);

                window_top_left := POINT.{0, 0};
                ClientToScreen(window, *window_top_left);
                window_bottom_right := POINT.{x=client_rect.right, y=client_rect.bottom};
                ClientToScreen(window, *window_bottom_right);

                window_x := window_top_left.x;
                window_y := monitor_h - window_bottom_right.y - 1;

                mouse_pos: POINT;
                GetCursorPos(*mouse_pos);

                global_mouse_x := mouse_pos.x;
                global_mouse_y := monitor_h - mouse_pos.y - 1; // Flip so we're in the cartesian plane

                mouse_x = cast(float, global_mouse_x - window_x) / cast(float, window_w) * 2 - 1;
                mouse_y = cast(float, global_mouse_y - window_y) / cast(float, window_h) * 2 - 1;
            }

            input := Input.{
                events = input_events,
                mouse_x = mouse_x,
                mouse_y = mouse_y
            };


            game_update(*context.base, game_memory, input, dt, hotloaded, changed_file_names, window_w, window_h);
            memset(*input_events, 0, size_of(type_of(input_events)));
        }

        if changed_files.count == 0 {
            // Prevent too many reloaded asset names from piling up.
            changed_files.allocated = 0;
            clear(*changed_file_arena);
        }

        //
        // Do audio update
        //

        // I tested it, and the dsound latency is consistently (exactly) 30ms.
        // This might be useful information to have.

        // There is weird audio crackling that sometimes shows up. When I analyzed the audio data with OBS,
        // it just shows the pcm values dropping to zero and then cutting back in maybe 0.01sec later.
        // I have absolutely no idea what is going on. I need to fix this, but I have alreadk sinkholed
        // too much time on this. I am leaving it for now.

        //          -berk, 2025 - 5 - 20

        play_byte, write_byte: s32;
        assert(secondary_buffer.GetCurrentPosition(secondary_buffer, *play_byte, *write_byte) == 0);

        play_sample  := play_byte  / size_of(Sample);
        write_sample := write_byte / size_of(Sample);

        region_1_data: *Sample;
        region_1_size_bytes: s32;
        region_2_data: *Sample;
        region_2_size_bytes: s32;

        SAMPLES_TO_WRITE :: AUDIO_SAMPLES_PER_SECOND / 20;

        assert(secondary_buffer.Lock(
            secondary_buffer, write_byte, size_of(Sample) * SAMPLES_TO_WRITE,
            xx *region_1_data, *region_1_size_bytes,
            xx *region_2_data, *region_2_size_bytes,
            0
        ) == DS_OK);

        region_1_size := region_1_size_bytes / size_of(Sample);
        region_2_size := region_2_size_bytes / size_of(Sample);
        
        assert(region_1_size + region_2_size == SAMPLES_TO_WRITE);

        // 3 frames worth of audio data. This should be enough to prevent audio crackling.

        // Making a separate audio thread feels like a hackerman thing to do at this point.
        // As such, I will keep everything on one thread. However, I will keep the idea
        // that this may have to go on multiple threads in the back of my head for now.

        // I've heard that WASAPI uses a callback to request more samples. If we switch to 
        // WASAPI, we may have to make it multithreaded.

        //          -berk, 2025 - 4 - 18



        samples_played := (write_sample - previous_write_sample + AUDIO_BUFFER_SIZE) % AUDIO_BUFFER_SIZE;

        // if samples_played > SAMPLES_TO_WRITE {
        //     print("We played more samples than we wrote. This shouldn't happen.\n");
        // }

        region_1: [] Sample = .{region_1_size, region_1_data};
        region_2: [] Sample = .{region_2_size, region_2_data};

        game_get_audio_samples(game_memory, samples_played, region_1, region_2);

        assert(secondary_buffer.Unlock(secondary_buffer, region_1_data, region_1_size_bytes, region_2_data, region_2_size_bytes) == DS_OK);
        previous_write_sample = write_sample;

        if !audio_started {
            audio_started = true;
            assert(secondary_buffer.Play(secondary_buffer, 0, 0, DSBPLAY_LOOPING) == 0);
        }

        
        //
        // Done.
        //

        SwapBuffers(dc);
    }
}


utf16_to_ascii :: (utf16: [] u16, arena: *Memory_Arena) -> bool, string {
    mark := get_mark(arena);
    ascii: *u8 = xx alloc(arena, utf16.count);

    for utf16 {
        if it >= 128 {
            restore_mark(arena, mark);
            return false, .{};
        }
        ascii[it_index] = xx it;
    }

    return true, .{utf16.count, ascii};
}


// @Copypasta from windows_game.jai
print :: (s: string, args: ..Any) {
    scope_mark(*frame_arena);
    sb := make_string_builder(*frame_arena);

    print(*sb, s, ..args);
    
    str := get_string(*sb);

    stdout := GetStdHandle(STD_OUTPUT_HANDLE);
    assert(stdout != INVALID_HANDLE_VALUE);
    WriteConsoleA(stdout, str.data, cast(u32, str.count), null, null);
    FlushFileBuffers(stdout); 
    // This function is for debug output. We don't care about performance, so we flush every time we call this.
}
