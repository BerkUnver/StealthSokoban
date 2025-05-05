#import "Compiler";

#run {
    set_build_options_dc(.{do_output=false}); 

    options := get_build_options();
    
    args := options.compile_time_command_line;
    
    build_exe := false;
    build_developer := false;

    for args {
        if it == "all"       build_exe = true;
        if it == "developer" build_developer = true;
    }

    if args.count == 1 && args[0] == "exe" {
        build_exe = true;
    }

    // Compile the platform executable
    if build_exe {
        w := compiler_create_workspace("Platform Workspace");
        o := get_build_options(w);
        copy_commonly_propagated_fields(options, *o);

        o.output_executable_name = "stealth_sokoban";
        o.output_path = "../assets";
        set_build_options(o, w);
        compiler_begin_intercept(w);
        add_build_file("windows_main.jai", w);
        while true {
            message := compiler_wait_for_message();
            if message.kind == .COMPLETE break;
        }
        compiler_end_intercept(w);
    }

    // Compile the game dynamic link library
    {
        w := compiler_create_workspace("Game Workspace");
        o := get_build_options(w);
        copy_commonly_propagated_fields(options, *o);

        o.output_type = .DYNAMIC_LIBRARY;
        o.output_executable_name = "stealth_sokoban_game_fresh";
        o.output_path = "../assets";
        set_build_options(o, w);
        compiler_begin_intercept(w);

        if build_developer {
            add_build_string("DEVELOPER :: true;\n", w);
        } else {
            add_build_string("DEVELOPER :: false;\n", w);
        }
        add_build_file("game.jai", w);
        
        while true {
            message := compiler_wait_for_message();
            if message.kind == {
                case .COMPLETE;
                    break;
            }
        }
        compiler_end_intercept(w);
    }
}
