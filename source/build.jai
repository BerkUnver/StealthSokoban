#import "Compiler";

#run {
    set_build_options_dc(.{do_output=false});

    w := compiler_create_workspace("Windows workspace");
    options := get_build_options(w);
    copy_commonly_propagated_fields(get_build_options(), *options);

    options.output_executable_name = "stealth_sokoban.exe";

    set_build_options(options, w);

    compiler_begin_intercept(w);
    add_build_file("main.jai", w);
    while true {
        message := compiler_wait_for_message();
        if message.kind == .COMPLETE break;
    }
    compiler_end_intercept(w);
}
