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

expect :: (err: Deserialization_Error, loc := #caller_location) {
    using context.game_context;
    if err.ok {
        set_console_text_color(.GREEN);
        print("%:% success (Deserialization)\n", loc.fully_pathed_filename, loc.line_number);
        set_console_text_color(.WHITE);
    } else {
        set_console_text_color(.RED);
        print("%:% failure (Deserialization): %\n", loc.fully_pathed_filename, loc.line_number, err.message);
        set_console_text_color(.WHITE);
    }
}


test :: () {
    using context.game_context;
    
    i: int;
    
    err := deserialize("0", *i);
    expect(err);
    expect(i == 0);

    err = deserialize("2847388", *i);
    expect(err);
    expect(i == 2847388);
    
    err = deserialize("-10923", *i);
    expect(err);
    expect(i == -10923);
    
    mark := get_mark(*frame_arena);
    defer restore_mark(*frame_arena, mark);

    expected := int.[1, 2, 3];
    view: [] int;
    err = deserialize("3 1 2 3", *view, *frame_arena);
    expect(err);
    expect(view.count == expected.count);
    expect(memcmp(view.data, expected.data, size_of(type_of(expected))) == 0);
}
