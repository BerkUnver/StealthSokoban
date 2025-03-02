// @TODO: :SpecialSerialization Do we want to serialize commonly-used structs
// (Vector2, Vector3, Vector4, Vector3i to some more convenient form?
// Like "(% % % %)" where each % is a member of Vector4?

// @TODO: Elegantly fail when the buffer is too small.

serialize :: (buf: [] u8, val: *$T) -> string {
    using context.game_context;
    
    sb := make_string_builder(buf);

    INFO :: type_info(T);
    
    default: *void;
    #if INFO.type == .STRUCT {
        default_buffer: [1024] u8 = ---;
        assert(INFO.runtime_size <= default_buffer.count);
        default = default_buffer.data;
        init_from_info(INFO, default);
    }
    serialize_next(*sb, INFO, val, default, 0); 

    return get_string(*sb);
}

serialize_next :: (sb: *String_Builder, info: *Type_Info, val: *void, struct_default: *void, indent: int) {
    if info.type == {
        case .FLOAT; #through;
        case .INTEGER;
            args := Any.[ dynamic_any(info, val) ];
            print(sb, "%", ..args);

        case .BOOL;
            if cast(*bool, val).* {
                print_string(sb, "1");
            } else {
                print_string(sb, "0");
            }
        case .ENUM;
            args := Any.[ dynamic_any(cast(*Type_Info_Enum, info).internal_type, val) ];
            print(sb, "%", ..args);

        case .ARRAY;
            array_info := cast(*Type_Info_Array, info);

            count: s64;
            data: *void;

            if array_info.array_type == {
                case .FIXED; assert(false);
                case .VIEW;
                    view := cast(*Array_View_64, val);
                    count = view.count;
                    data = view.data;
                case .RESIZABLE;
                    array := cast(*Resizable_Array, val);
                    count = array.count;
                    data = array.data;
            };


            size := array_info.element_type.runtime_size;
            
            separator: string;
            default: *void;

            if array_info.element_type.type == .STRUCT {
                separator = "\n";
                struct_info := cast(*Type_Info_Struct, array_info.element_type);

                default_buffer: [1024] u8;
                default = default_buffer.data;
                assert(struct_info.runtime_size <= default_buffer.count);

                init_from_info(struct_info, default);
            } else {
                separator = " ";
            }

            print(sb, "%[%", count, separator);

            for 0..count-1 {
                serialize_next(sb, array_info.element_type, data + it * size, default, indent + 1);
                print_string(sb, separator);
            }

            if array_info.element_type.type == .STRUCT {
                for 0..indent-1 print_string(sb, "\t");
            }

            print_string(sb, "]");

        case .STRUCT;
            struct_info := cast(*Type_Info_Struct, info);

            if struct_info.textual_flags & .UNION assert(false);
            // Don't allow serializing unions for now.

            greatest_offset := -1;
            for * struct_info.members {
                if !can_serialize_member(it, greatest_offset) continue;
                greatest_offset = it.offset_in_bytes;

                member_val := val + it.offset_in_bytes;
                member_default := struct_default + it.offset_in_bytes;
                
                // We don't want to serialize empty arrays that have a count of zero but might not have a data
                // pointer of zero.
                if it.type.type == .ARRAY {
                    array_info := cast(*Type_Info_Array, it.type);
                    if #complete array_info.array_type == {
                        case .FIXED;
                            assert(false);
                        case .VIEW;
                            member_val_view := cast(*Array_View_64, member_val);
                            member_default_view := cast(*Array_View_64, member_default);
                            
                            assert(member_default_view.count == 0);
                            // If you're trying to serialize a view as anything other than a zeroed-out view,
                            // don't! You are assigning something to a static pointer, which you shouldn't do.
                            // All serialized struct members of unknown size are expected to be heap-allocated.

                            if member_val_view.count == 0 continue;

                        case .RESIZABLE;
                            member_val_array := cast(*Resizable_Array, member_val);
                            member_default_array := cast(*Resizable_Array, member_default);

                            assert(member_default_array.count == 0);
                            // I don't even know if you can assign to a dynamically-resizing array in a struct
                            // initializer

                            if member_val_array.count == 0 continue;
                    }
                }

                if memcmp(member_val, member_default, it.type.runtime_size) == 0 {
                    continue; // The member has its default value. Don't serialize it.
                }

                for 0..indent-1 print_string(sb, "\t");

                print_string(sb, it.name);

                separator: string;
                new_indent: int;
                if it.type.type == .STRUCT {
                    separator = "\n";
                    new_indent = indent + 1;
                } else {
                    separator = " ";
                    new_indent = indent;
                }

                print_string(sb, separator); 
                serialize_next(sb, it.type, member_val, member_default, new_indent);
                print_string(sb, "\n");
            }

            for 0..indent-1 print_string(sb, "\t");
            print_string(sb, ";");
        case;
            assert(false);
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

can_serialize_member :: (member: *Type_Info_Struct_Member, greatest_offset_before_this_member: int) -> bool {
    if member.flags & .CONSTANT != 0 return false;
    if member.offset_in_bytes <= greatest_offset_before_this_member return false; // This is how we detect #place members.
    // Maybe a better idea would be to have :SpecialSerialization code for stuff that uses #place
    // (Vector3, etc) and just assert that this is never true in normal structs.
    if contains(member.notes, "Ignore") return false;
    return true;
}

deserialize :: (data: string, val: *$T, arena: *Memory_Arena = null) -> Deserialization_Error {
    lexer := Lexer.{str = data};
    INFO :: type_info(T);
    
    mark: s64;
    if arena != null mark = get_mark(arena);

    err_return :: (e: Deserialization_Error) #expand {
        if arena restore_mark(arena, mark);
        `return e;
    }

    err := deserialize_next(*lexer, type_info(T), val, arena);
    if !err.ok err_return(err);

    token := get_token(*lexer);
    if token.type == .ERROR err_return(.{false, token.error, token.loc});
    if token.type != .EOF   err_return(.{false, "Expected no more tokens after the end of what we just deserialized.", token.loc});

    return OK;
}


deserialize_next :: (lexer: *Lexer, info: *Type_Info, ptr: *void, arena: *Memory_Arena) -> Deserialization_Error {
    assign_int :: (info: *Type_Info_Integer, ptr: *void, value: s64) {
        // @Incomplete: We should do our own bounds checking and have an appropriate failure
        // message, jai native bounds check failure just crashes the program.
        if info.runtime_size == {
            case 1;
                if info.signed cast(*s8, ptr).* = xx value;
                else           cast(*u8, ptr).* = xx value;
            case 2;
                if info.signed cast(*s16, ptr).* = xx value;
                else           cast(*u16, ptr).* = xx value;
            case 4;
                if info.signed cast(*s32, ptr).* = xx value;
                else           cast(*u32, ptr).* = xx value;
            case 8;
                if info.signed cast(*s64, ptr).* = xx value;
                else           cast(*u64, ptr).* = xx value;
            case; assert(false);
        }
    }

    if info.type == {
        case .BOOL;
            token := get_token(lexer);
            return_if_invalid(token);
            
            if token.type != .INT {
                return .{false, "Expected an integer token for the value of a bool", token.loc};
            }

            if token.int_value != 0 && token.int_value != 1 {
                return .{false, "Expected the value of a boolean to be zero or one.", token.loc};
            }

            cast(*bool, ptr).* = xx token.int_value;
            return OK;
        
        case .ENUM;
            enum_info := cast(*Type_Info_Enum, info);
            token := get_token(lexer);
            return_if_invalid(token);

            if token.type != .INT {
                return .{false, "Expected an integer token when deserializing to an enum type.", token.loc};
            }

            assign_int(enum_info.internal_type, ptr, token.int_value);

            return OK;

        case .INTEGER; 
            int_info := cast(*Type_Info_Integer, info);
            token := get_token(lexer);
            return_if_invalid(token);

            if token.type != .INT {
                return .{false, "Expected an integer token when deserializing to an integer type.", token.loc};
            }

            assign_int(int_info, ptr, token.int_value);

            return OK;

        case .FLOAT;
            token := get_token(lexer);
            return_if_invalid(token);

            value: float64;
            if token.type == .INT {
                value = xx token.int_value;
            } else if token.type == .FLOAT {
                value = token.float_value;
            } else {
                return .{false, "Expected a numeric token for a numeric type.", token.loc};
            }

            if info.runtime_size == 4 {
                cast(*float32, ptr).* = xx value;
            } else {
                cast(*float64, ptr).* = value;
            }

            return OK;

        case .STRUCT;
            struct_info := cast(*Type_Info_Struct, info);
            if struct_info.textual_flags & .UNION assert(false);
            // Don't allow serializing unions for now.

            init_from_info(struct_info, ptr);
            // Make sure the default values for everything we didn't explicitly serialized
            // are properly set.

            member_index := 0;
            greatest_offset := -1;

            while true {
                token := get_token(lexer);
                return_if_invalid(token);
                if token.type == #char ";" return OK;

                if member_index >= struct_info.members.count {
                    return .{false, "Expected a semicolon after all the members of a struct.", token.loc};
                }

                if token.type != .IDENTIFIER return .{false, "Expected an identifier before a member of a struct.", token.loc};
                
                while true {
                    member := *struct_info.members[member_index];
                    if can_serialize_member(member, greatest_offset) {
                        greatest_offset = member.offset_in_bytes;
                        if member.name == token.identifier break;
                    }

                    member_index += 1;
                    if member_index >= struct_info.members.count {
                        return .{false, "This member name isn't in the rest of the struct.", token.loc};
                    }
                }

                member := *struct_info.members[member_index];
                err := deserialize_next(lexer, member.type, ptr + member.offset_in_bytes, arena);
                if !err.ok return err;

                member_index += 1;
            }
        case .ARRAY;
            token := get_token(lexer);
            return_if_invalid(token);
            if token.type != .INT return .{false, "Expected the first token of an array declaration to be an integer length.", token.loc};

            count := token.int_value;
            array_info := cast(*Type_Info_Array, info);

            token = get_token(lexer);
            return_if_invalid(token);
            if token.type != #char "[" return .{false, "Expected a '[' at the start of an array declaration.", token.loc};
            
            populate_memory :: () -> *void #expand {
                if arena == null `return .{false, "This array expected to dynamically allocate memory.", token.loc};
                memory := alloc(arena, count * array_info.element_type.runtime_size, zero_init=false);
                for 0..count-1 {
                    item := memory + it * array_info.element_type.runtime_size;
                    err := deserialize_next(lexer, array_info.element_type, item, arena);
                    if !err.ok `return err;
                }
                return memory;
            }

            if #complete array_info.array_type == {
                case .FIXED;
                    assert(false); // @Incomplete
                case .VIEW;
                    memory := populate_memory();
                    cast(*Array_View_64, ptr).* = .{count, memory};
                case .RESIZABLE;
                    memory := populate_memory();
                    cast(*Resizable_Array, ptr).* = .{
                        count=count,
                        data=memory,
                        allocated=count,
                        allocator.data=arena
                    };
            }

            token = get_token(lexer);
            return_if_invalid(token);
            if token.type != #char "]" return .{false, "Expected a ']' at the end of an array.", token.loc};
            return OK;
        case; assert(false);
    }

    assert(false);
    return .{};
}


#scope_file

Token_Type :: enum {
    ERROR :: 0;
    // ';'
    // '['
    // ']'
    EOF :: 256;
    INT;
    FLOAT;
    IDENTIFIER;
}


Token :: struct {
    type: Token_Type;
    loc: Deserialization_Location; // Valid as long as this isn't an EOF
    union {
        int_value: s64;
        float_value: float64;
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

    if str[index] == #char ";" || str[index] == #char "[" || str[index] == #char "]" {
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
            case .EOF;
                return err("Expected a number after the minus sign", .{minus_index, 1});
            case .ERROR;
                return token;
            case .INT; 
                return .{
                    type=.INT, 
                    int_value = -token.int_value, 
                    loc = .{token.loc.start - 1, token.loc.count + 1}
                };
            case .FLOAT;
                return .{
                    type=.FLOAT,
                    float_value = -token.float_value,
                    loc = .{token.loc.start - 1, token.loc.count + 1}
                };
            case;
                return err("Expected a number after a minus sign.", token.loc);
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
            } else if str[index] == #char "." {
                index += 1;
                fractional_value: float64 = 0;
                current_place := 0.1;
                while true {
                    if index >= str.count {
                        return .{
                            type = .FLOAT,
                            float_value = cast(float64, value) + fractional_value,
                            loc = .{start_index, str.count - start_index},
                        };
                    }

                    if str[index] < #char "0" || #char "9" < str[index] {
                        return .{
                            type = .FLOAT,
                            float_value = cast(float64, value) + fractional_value,
                            loc = .{start_index, index - start_index}};
                    }

                    fractional_value += current_place * cast(float64, str[index] - #char "0");
                    index += 1;
                    current_place /= 10;
                }
            } else {
                return .{type=.INT, int_value=value, loc=.{start_index, index - start_index}};
            }
        }
    }
    
    return err("Illegal character.", .{index, 1});
}
