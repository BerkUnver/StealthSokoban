#import "Compiler";

#run {
    set_build_options_dc(.{do_output=false}); 

    options := get_build_options();
    
    args := options.compile_time_command_line;

    build_exe := false;
    if args.count == 1 && args[0] == "all" {
        build_exe = true;
    }

    // Compile the platform executable
    if build_exe {
        w := compiler_create_workspace("Platform Workspace");
        o := get_build_options(w);
        copy_commonly_propagated_fields(options, *o);

        o.output_executable_name = "stealth_sokoban";
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
        w := compiler_create_workspace("Compiler Workspace");
        o := get_build_options(w);
        copy_commonly_propagated_fields(options, *o);

        o.output_type = .DYNAMIC_LIBRARY;
        o.output_executable_name = "stealth_sokoban_game_fresh";
        set_build_options(o, w);
        compiler_begin_intercept(w);
        add_build_file("game.jai", w);
        while true {
            message := compiler_wait_for_message();
            if message.kind == .COMPLETE break;
        }
        compiler_end_intercept(w);
    }
}
