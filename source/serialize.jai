serialize :: (buf: [] u8, val: *$T) -> string {
    using context.game_context;
    
    sb := make_string_builder(buf);

    INFO :: type_info(T);

    #if INFO.type == .STRUCT {
        default_buffer: [1024] u8 = ---;
        default := default_buffer.data;
        assert(INFO.runtime_size <= default_buffer.count);

        init_from_info(INFO, default);

        serialize_struct(*sb, INFO, val, default, 0); 
    } else {
        serialize_primitive(*sb, INFO, val);
    }

   return get_string(*sb);
}


serialize_struct :: (sb: *String_Builder, info: *Type_Info_Struct, val: *void, default: *void, indent: int) {
    for * info.members {
        if it.flags & .CONSTANT continue;

        member_val := val + it.offset_in_bytes;
        member_default := default + it.offset_in_bytes;

        if memcmp(member_val, member_default, it.type.runtime_size) == 0 {
            continue; // The member has its default value. Don't serialize it.
        }

        for 0..indent-1 print_string(sb, "\t");
        print(sb, "% ", it.name);
        
        if it.type.type == .STRUCT {
            print_string(sb, "{\n");
            serialize_struct(sb, xx it.type, member_val, member_default, indent + 1);
            for 0..indent-1 print_string(sb, "\t");
            print_string(sb, "}\n");
        } else {
            serialize_primitive(sb, it.type, member_val);
        }
    }
}


serialize_primitive :: (sb: *String_Builder, info: *Type_Info, val: *void) {
    if info.type == .ENUM {
        args := Any.[ dynamic_any(cast(*Type_Info_Enum, info).internal_type, *val) ];
        print(sb, "%\n", ..args);
    } else {
        args := Any.[ dynamic_any(info, val) ];
        print(sb, "%\n", ..args);
    }
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


return_if_invalid :: (token: Token) #expand {
    if token.type == .ERROR `return Deserialization_Error.{false, token.error, token.loc};
    if token.type == .EOF   `return UNEXPECTED_EOF;
}


deserialize :: (data: string, val: *$T, arena: *Memory_Arena = null) -> Deserialization_Error {
    lexer := Lexer.{str = data};
    INFO :: type_info(T);

    #if INFO.type == .INTEGER {
        i: int;
        err := deserialize_next(*lexer, INFO, *i, arena);
        if !err.ok return err;
        token := get_token(*lexer);
        if token.type == .ERROR return.{false, token.error, token.loc};
        if token.type != .EOF return .{false, "Expected no more tokens after the integer token.", token.loc};
        val.* = xx i;
        return OK;

    } else #if INFO.type == .ARRAY {
        token := get_token(*lexer);
        return_if_invalid(token);
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
    } else #if INFO.type == .STRUCT {
        // @Incomplete
        return deserialize_next(*lexer, INFO, val, arena);
    } else #assert false;
}


deserialize_next :: (lexer: *Lexer, info: *Type_Info, ptr: *void, arena: *Memory_Arena) -> Deserialization_Error {
    if info.type == {
        case .INTEGER; 
            int_info := cast(*Type_Info_Integer, info);
            token := get_token(lexer);
            return_if_invalid(token);

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

        case .STRUCT;
            struct_info := cast(*Type_Info_Struct, info);
            member_index := 0;
            while true {
                // I don't know if this introduces bugs.
                // There could be extra members after this that are wrong.
                // Struct member checking code will check for a curly brace, so that's fine.
                // Global code will check for the EOF, so that's fine.
                // As far as I can tell, it works. It just feels weird.
                if member_index >= struct_info.members.count return OK;

                if struct_info.members[member_index].flags & .CONSTANT != 0 continue;

                token := get_token(lexer);
                return_if_invalid(token);
                if token.type != .IDENTIFIER return .{false, "Expected an identifier before a member of a struct.", token.loc};

                while token.identifier != struct_info.members[member_index].name { // @Speed This might be what kills this routine
                    member_index += 1;
                    if member_index >= struct_info.members.count return .{false, "This member name isn't in the rest of the struct.", token.loc};
                }

                member := *struct_info.members[member_index];

                if member.type.type == .STRUCT {
                    token := get_token(lexer);
                    return_if_invalid(token);
                    if token.type != #char "{" return .{false, "Expected a '{' at the beginning of a nested struct member.", token.loc};
                }

                // @Incomplete Handle #place members
                if member.flags & .CONSTANT != 0 continue;
                err := deserialize_next(lexer, member.type, ptr + member.offset_in_bytes, arena);
                if !err.ok return err;

                if member.type.type == .STRUCT {
                    token := get_token(lexer);
                    return_if_invalid(token);
                    if token.type != #char "}" return .{false, "Expected a '}' at the end of a nested struct member.", token.loc};
                }

                member_index += 1;
            }
            return OK;
        case; assert(false);
    }

    assert(false);
    return .{};
}


#scope_file

Token_Type :: enum {
    ERROR :: 0;
    // Open curly brace
    // Close curly brace
    EOF :: 256;
    INT;
    IDENTIFIER;
}


Token :: struct {
    type: Token_Type;
    loc: Deserialization_Location; // Valid as long as this isn't an EOF
    union {
        int_value: s64;
        error: string;
        identifier: string;
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

    if str[index] == #char "{" || str[index] == #char "}" {
        token := Token.{type=xx str[index], loc=.{index, 1}};
        index += 1;
        return token;
    }

    if (#char "a" <= str[index] && str[index] <= #char "z")
    || (#char "A" <= str[index] && str[index] <= #char "Z")
    || str[index] == #char "_" {
        start_index := index;
        index += 1;
        while true {
            if index >= str.count {
                return .{
                    type=.IDENTIFIER,
                    identifier=.{str.count - start_index, str.data + start_index},
                    loc=.{start_index, str.count - start_index}
                };
            }

            if (#char "a" <= str[index] && str[index] <= #char "z")
            || (#char "A" <= str[index] && str[index] <= #char "Z")
            || (#char "0" <= str[index] && str[index] <= #char "9")
            || str[index] == #char "_" {
                index += 1;
                continue;
            }

            return .{
                type=.IDENTIFIER,
                identifier=.{index - start_index, str.data + start_index},
                loc=.{start_index, index - start_index},
            };
        }
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
            } else {
                return .{type=.INT, int_value=value, loc=.{start_index, index - start_index}};
            }
        }
    }

    assert(false);
    return .{};
}
