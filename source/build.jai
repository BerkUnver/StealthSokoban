#import "Compiler";

#run {
    set_build_options_dc(.{do_output=false}); 

    options := get_build_options();
    
    // Compile the platform executable
    {
        w := compiler_create_workspace("w");
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
        w := compiler_create_workspace("w");
        o := get_build_options(w);
        copy_commonly_propagated_fields(options, *o);

        o.output_type = .DYNAMIC_LIBRARY;
        o.output_executable_name = "stealth_sokoban_game";
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
