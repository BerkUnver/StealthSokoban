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


Deserialization_Error :: struct {
    ok: bool;

    // These are only used if ok is false.
    message: string;
    loc: Deserialization_Location;
}


OK             :: Deserialization_Error.{ok=true};
UNEXPECTED_EOF :: Deserialization_Error.{false, "Unexpected end of file.", .{}};


Deserialization_Location :: struct {
    start: s64;
    count: s64;
}


deserialize :: (data: string, val: *$T, arena: *Memory_Arena = null) -> Deserialization_Error {
    lexer := Lexer.{str = data};
    INFO :: type_info(T);

    #if INFO.type == .INTEGER {
        i: int;
        err := deserialize_next(*lexer, INFO, *i, arena);
        if !err.ok return err;
        token := get_token(*lexer);
        if token.type != .EOF return .{false, "Expected no more tokens after the integer token.", token.loc};
        val.* = xx i;
        return OK;

    } else #if INFO.type == .ARRAY {
        token := get_token(*lexer);
        if token.type == .EOF return UNEXPECTED_EOF;
        if token.type == .ERROR return .{false, token.error, token.loc};
        if token.type != .INT return .{false, "Expected the first token of an array declaration to be an integer length.", token.loc};

        count := token.int_value;
        if #complete INFO.array_type == {
            case .FIXED;
                assert(false); // @Incomplete
            case .VIEW;
                if arena == null return .{false, "This array expected to dynamically allocate memory.", token.loc};
                mark := get_mark(arena);
                memory := alloc(arena, count * INFO.element_type.runtime_size, zero_init=false);
                for 0..count-1 {
                    err := deserialize_next(*lexer, INFO.element_type, memory + it * INFO.element_type.runtime_size, arena);
                    if !err.ok {
                        restore_mark(arena, mark);
                        return err;
                    }
                }
                val.* = .{count, memory};
                return OK;
            case .RESIZABLE;
                assert(false); // @Incomplete
                return .{};
        }
        assert(false);
        return .{};
    } else #assert false;
}


deserialize_next :: (lexer: *Lexer, info: *Type_Info, ptr: *void, arena: *Memory_Arena) -> Deserialization_Error {
    if info.type == {
        case .INTEGER; 
            int_info := cast(*Type_Info_Integer, info);
            token := get_token(lexer);
            if token.type == .EOF return UNEXPECTED_EOF;
            if token.type == .ERROR return .{false, token.error, token.loc};
            if token.type != .INT {
                return .{false, "Expected an integer token when deserializing to an integer type.", token.loc};
            }

            value := token.int_value;
            
            // @Incomplete: We should do our own bounds checking and have an appropriate failure
            // message, jai native bounds check failure just crashes the program.
            if int_info.runtime_size == {
                case 1;
                    if int_info.signed cast(*s8, ptr).* = xx value;
                    else               cast(*u8, ptr).* = xx value;
                case 2;
                    if int_info.signed cast(*s16, ptr).* = xx value;
                    else               cast(*u16, ptr).* = xx value;
                case 4;
                    if int_info.signed cast(*s32, ptr).* = xx value;
                    else               cast(*u32, ptr).* = xx value;
                case 8;
                    if int_info.signed cast(*s64, ptr).* = xx value;
                    else               cast(*u64, ptr).* = xx value;
                case; assert(false);
            }

            return OK;
        case; assert(false);
    }

    assert(false);
    return .{};
}


#scope_file

Token_Type :: enum {
    INT;
    ERROR;
    EOF;
}


Token :: struct {
    type: Token_Type;
    loc: Deserialization_Location; // Valid as long as this isn't an EOF
    union {
        int_value: s64;
        error: string;
    }
}


Lexer :: struct {
    str: string;
    index: int;
}


get_token :: (using lexer: *Lexer) -> Token {
    EOF :: Token.{type=.EOF};

    err :: inline (error: string, loc: Deserialization_Location) -> Token {
        return .{type=.ERROR, error=error, loc=loc};
    }

    if index >= str.count return EOF;
    
    while str[index] == #char " " || str[index] == #char "\n" || str[index] == #char "\r" || str[index] == #char "\t" {
        index += 1;
        if index == str.count return EOF;
    }
    
    if str[index] == #char "-" {
        minus_index := index;
        index += 1;
        token := get_token(lexer);
        if token.type == {
            case .EOF; return err("Expected a number after the minus sign", .{minus_index, 1});
            case .ERROR; return token;
            case .INT; return .{type=.INT, int_value = -token.int_value, loc = .{token.loc.start - 1, token.loc.count + 1}};
            case; return err("Expected a number after a minus sign.", token.loc);
        }
    }

    if #char "0" <= str[index] && str[index] <= #char "9" {
        start_index := index;
        value: s64 = str[index] - #char "0";
        index += 1;
        while true {
            if index >= str.count return .{type = .INT, int_value = value, loc = .{start_index, str.count - start_index}};
            if #char "0" <= str[index] && str[index] <= #char "9" {
                value *= 10;
                value += str[index] - #char "0";
                index += 1;
            } else if str[index] == #char " " {
                return .{type=.INT, int_value=value, loc=.{start_index, index - start_index}};
            } else {
                return err("Encountered an unexpected character in a number.", .{index, 1});
            }
        }
    }

    assert(false);
    return .{};
}
