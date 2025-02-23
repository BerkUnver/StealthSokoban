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
        print("%:% failure (Deserialization): Byte %,% %\n",
            loc.fully_pathed_filename,
            loc.line_number, 
            err.loc.start,
            err.loc.count,
            err.message
        );
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
    
    {
        mark := get_mark(*frame_arena);
        defer restore_mark(*frame_arena, mark);

        expected := int.[1, 2, 3];
        view: [] int;
        err := deserialize("3 1 2 3", *view, *frame_arena);
        expect(err);
        expect(view.count == expected.count);
        expect(memcmp(view.data, expected.data, size_of(type_of(expected))) == 0);
    }
    
    {
        Struct :: struct {
            a: s64;
            b: u8;
        }
        
        expected := Struct.{a=-7051, b=33};
        result: Struct;
        input := #string
END
a -7051
b 33
END
        err := deserialize(input, *result);
        expect(err);
        expect(expected.a == result.a);
        expect(expected.b == result.b);
    }

    {
        Member :: struct {
            a: s64;
            b: u32;
        }

        Struct :: struct {
            a: s32;
            b: Member;
            c: s8;
        }

        expected := Struct.{a=2000, b=.{-53, 47}, c=-3};
        result: Struct;
        input := #string
END
a 2000
b {
    a -53
    b 47
}
c -3
END
        err := deserialize(input, *result);
        expect(err);
        expect(memcmp(*result, *expected, size_of(Struct)) == 0);
    }

    {
        Struct :: struct {
            a: int;
            b: u32 = 1;
            c: s16;
        }

        expected := Struct.{a=-100, c=2040};
        result: Struct;
        input := #string
END
a -100
c 2040
END
        
        err := deserialize(input, *result);
        expect(err);
        expect(memcmp(*result, *expected, size_of(Struct)) == 0);
    }
}
