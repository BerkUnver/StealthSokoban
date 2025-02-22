expect :: (b: bool, loc := #caller_location) {
    using context.game_context;
    if b {
        set_console_text_color(.GREEN);
        print("%:% success\n", loc.fully_pathed_filename, loc.line_number);
        set_console_text_color(.WHITE);
    } else {
        set_console_text_color(.RED);
        print("%:% failure\n", loc.fully_pathed_filename, loc.line_number);
        set_console_text_color(.WHITE);
    }
}


test :: () {
    err, i := deserialize("0", int);
    expect(err.ok && i == 0);

    err, i = deserialize("2847388", int);
    expect(err.ok && i == 2847388);
    
    err, i = deserialize("-10923", int);
    expect(err.ok && i == -10923);
}
