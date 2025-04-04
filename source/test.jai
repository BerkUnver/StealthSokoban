expect :: (b: bool, loc := #caller_location) {
    using context.game_context;
    if b {
        set_console_text_color(.GREEN);
        print("%(%) success\n", loc.fully_pathed_filename, loc.line_number);
        set_console_text_color(.WHITE);
    } else {
        set_console_text_color(.RED);
        print("%(%) failure\n", loc.fully_pathed_filename, loc.line_number);
        set_console_text_color(.WHITE);
    }
}


expect :: (expected: string, result: string, loc := #caller_location) {
    success := expected == result;
    expect(success, loc);
    if !success {
        print("Expected string:\n\n%\n\nReceived string:\n\n%\n", expected, result);
    }
}


expect :: (err: Deserialization_Error, loc := #caller_location) {
    using context.game_context;
    if err.ok {
        set_console_text_color(.GREEN);
        print("%(%) success (Deserialization)\n", loc.fully_pathed_filename, loc.line_number);
        set_console_text_color(.WHITE);
    } else {
        set_console_text_color(.RED);
        print("%(%) failure (Deserialization): Byte %,% %\n",
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
    
    //
    // Deserialization
    //
    
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
        err := deserialize("3[1 2 3]", *view, *frame_allocator);
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
;
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
b
    a -53
    b 47
    ;
c -3
;
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
;
END
        err := deserialize(input, *result);
        expect(err);
        expect(memcmp(*result, *expected, size_of(Struct)) == 0);
    }

    {
        mark := get_mark(*frame_arena);
        defer restore_mark(*frame_arena, mark);

        output: [..] int;
        err := deserialize("3[1 2 3]", *output, *frame_allocator);
        expect(err);
        expect(output.count == 3);
        expect(output.allocated == 3);
        expect(output.allocator.proc == frame_allocator.proc && output.allocator.data == frame_allocator.data);
        expect(memcmp(output.data, int.[1,2,3].data, 3 * size_of(int)) == 0);
    }

    {
        Struct :: struct {
            a: int;
            #place a;
            b: int;
            c: int;
        }
        
        expected := Struct.{a = 10, c = -20};
        input := #string
END
a 10
c -20
;
END
        result: Struct;
        err := deserialize(input, *result);
        expect(err);
        expect(memcmp(*result, *expected, size_of(Struct)) == 0);
    }


    //
    // Serialization
    //
    
    buf: [4096] u8 = ---;

    {
        input := 1;
        str := serialize(buf, *input);
        expect("1", str);
    }
    
    {
        Struct :: struct { a: s64; b: u32; }
        input := Struct.{10, 20};
        expected := #string
END
a 10
b 20
;
END
        expected.count -= 1; // @Hack for the extra newline at the end.
        str := serialize(buf, *input);
        expect(expected, str);
    }

    {
        Struct :: struct { a: u8 = 32; b: u64; }
        input := Struct.{b=100};
        expected := #string
END
b 100
;
END
        expected.count -= 1;
        str := serialize(buf, *input);
        expect(expected, str);
    }

    {
        Member :: struct { a: u8; b: s32; }
        Struct :: struct { a: u8; b: Member; c: s64; }
        input := Struct.{
            a=10,
            b=.{32, -400},
        };
        expected := #string
END
a 10
b
	a 32
	b -400
	;
;
END
        expected.count -= 1;
        str := serialize(buf, *input);
        expect(expected, str);
    }

    {
        Member :: struct { a := 1; b: u16; }
        Struct :: struct { a: Member; b: Member; c: s32; }
        input := Struct.{
            b = .{b = 3},
            c = -44
        };
        expected := #string
END
b
	b 3
	;
c -44
;
END 
        expected.count -= 1;
        str := serialize(buf, *input);
        expect(expected, str);
    }


    {
        input_backing := int.[1, 2, 3, 4];
        input: [] int = input_backing;
        expected := "4[ 1 2 3 4 ]";
        str := serialize(buf, *input);
        expect(expected, str);
    }

    {
        input_backing := int.[0, 0, 0];
        input: [] int = input_backing;
        expected := "3[ 0 0 0 ]";
        str := serialize(buf, *input);
        expect(expected, str);
    }

    {
        Struct :: struct { a: int; b: u32; }
        input_backing := Struct.[
            .{1, 2},
            .{0, 0},
            .{-10, 300},
        ];
        input: [] Struct = input_backing;
        expected := #string
END
3[
	a 1
	b 2
	;
	;
	a -10
	b 300
	;
]
END
        expected.count -= 1;
        str := serialize(buf, *input);
        expect(expected, str);
    }


    {
        input := 0.0625;
        expect("0.0625", serialize(buf, *input));
    }

    {
        // The #place member should be skipped
        Struct :: struct {
            a := 1;
            #place a;
            b: int;
            c: int;
        }

        input := Struct.{a = 2, c = 3};
        expected := #string
END
a 2
c 3
;
END
        expected.count -= 1;
        str := serialize(buf, *input);
        expect(expected, str);
    }

    {   
        // The default vector has a lot of #place.
        // This will be a good test.

        input := Vector3.{1.5, 4.5, 2};
        expected := #string 
END
x 1.5
y 4.5
z 2
;
END
        expected.count -= 1;
        str := serialize(buf, *input);
        expect(expected, str);
    }

    //
    // String_Builder
    //

    {
        sb := make_string_builder(buf);
        print(*sb, "%", 0.0);
        expect(get_string(*sb) == "0");
    }

    {
        sb := make_string_builder(buf);
        print(*sb, "%", -0.0);
        expect(get_string(*sb) == "-0");
    }

    {
        sb := make_string_builder(buf);
        print(*sb, "%", 37.0);
        expect("37", get_string(*sb));
    }

    {
        sb := make_string_builder(buf);
        print(*sb, "%", 4.5);
        expect("4.5", get_string(*sb));
    }

    {
        sb := make_string_builder(buf);
        print(*sb, "%", -2.0625);
        expect("-2.0625", get_string(*sb));
    }

    {
        sb := make_string_builder(buf);
        // Upon casting to float64, this will become 2 ^ 60 because there are
        // only 52 bits of precision in the mantissa, and the 1 can't fit there.
        print(*sb, "%", cast(float64, 1 << 60 + 1));
        expect("1152921504606846976", get_string(*sb)); // This is 2 ^ 60
    }

    {
        sb := make_string_builder(buf);
        print(*sb, "%", 0.0625);
        expect("0.0625", get_string(*sb));
    }


    {
        sb := make_string_builder(buf);
        print(*sb, "%", 0.125 + 0.0625);
        expect("0.1875", get_string(*sb));
    }
}
