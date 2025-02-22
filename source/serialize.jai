serialize :: (val: $T) {
    using context.game_context;
    
    buf: [4096] u8 = ---;
    sb := make_string_builder(buf);
    
    TYPE :: type_info(T);

    #if TYPE.type == .INTEGER || TYPE.type == .ARRAY {
        print(*sb, "%", val);

    } else #if TYPE.type == .ENUM {
       args := Any.[ dynamic_any(TYPE.internal_type, *val) ];
       print(*sb, "%", ..args);

    // Should we make the user pass a pointer to val instead of val if it's a struct?
    } else if TYPE.type == .STRUCT {
        print(*sb, "{\n");
        for * type.members {  
            if it.flags & .CONSTANT != 0 continue;
            value_pointer := cast(*u8, *val) + it.offset_in_bytes;
            args := Any.[ dynamic_any(it.type, value_pointer) ];
            print(*sb, "\t%\n", ..args);
        }
        print(*sb, "}\n");
    }

    str := get_string(*sb);
    write_file("test_serialize.txt", str);
}


Deserialize_Error :: struct {
    ok: bool;
    message: string;
}


deserialize :: (data: string, $T: Type) -> Deserialize_Error, T {
    lexer := Lexer.{str = data};
    TYPE :: type_info(T);

    OK :: Deserialize_Error.{ok=true};

    #if TYPE.type == .INTEGER {
        err, token := get_token(*lexer);
        if err.type == {
            case .OK;
                if token.type != .INT return .{false, "Expected an integer token when deserializing to an integer type."}, 0;
                next_err, next_token := get_token(*lexer);
                if next_err.type != .EOF return .{false, "Unexpected token after the integer token."}, 0;
                return OK, xx token.int_value;
                // @TODO: We should do our own bounds checking and have an appropriate failure
                // message, jai native bounds check failur just crashes the program.
            case .EOF;
                return .{false, "We need a token in order to deserialize something."}, 0;
            case .ERROR;
                return .{false, err.message}, 0;
        }
    } else #assert false;
    return .{false, "This is a programmer error, this error message should never show up."}, 0;
}


#scope_file

Token_Type :: enum {
    INT;
}


Token :: struct {
    type: Token_Type;
    union {
        int_value: s64;
    }
}


Lexer :: struct {
    str: string;
    index: int;
}


Token_Error :: struct {
    type: enum { OK; EOF; ERROR; };
    message: string; // Be careful here. Because of DLL hot-reloading, static strings cannot persist past the frame boundary.
}


get_token :: (using lexer: *Lexer) -> Token_Error, Token {
    OK :: Token_Error.{};
    EOF :: Token_Error.{type=.EOF};

    if index >= str.count return EOF, .{};
    
    while str[index] == #char " " || str[index] == #char "\n" || str[index] == #char "\r" || str[index] == #char "\t" {
        index += 1;
        if index == str.count return EOF, .{};
    }
    
    if str[index] == #char "-" {
        index += 1;
        err, token := get_token(lexer);
        if err.type == {
            case .OK;
                if #complete token.type == {
                    case .INT;
                        return OK, .{type = .INT, int_value = -token.int_value};
                    case;
                        return .{.ERROR, "Expected a number after a minus sign."}, .{};
                }
            case .EOF;
                return .{.ERROR, "Unexpected EOF after a minus sign."}, .{};
            case .ERROR;
                return err, .{};
        }
    }

    if #char "0" <= str[index] && str[index] <= #char "9" {
        value: s64 = str[index] - #char "0";
        index += 1;
        while true {
            if index >= str.count return OK, .{type = .INT, int_value = value};
            if #char "0" <= str[index] && str[index] <= #char "9" {
                value *= 10;
                value += str[index] - #char "0";
                index += 1;
            } else if str[index] == #char " " {
                return OK, .{type = .INT, int_value = value};
            } else {
                return .{.ERROR, "Encountered an unexpected character in a number."}, .{};
            }
        }
    }

    return .{.ERROR, "Not implemented yet."}, .{};
}
