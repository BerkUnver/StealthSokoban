inside :: (position: Vector2, size: Vector2, point: Vector2) -> bool {
    return point.x >= position.x
        && point.y >= position.y
        && point.x <= position.x + size.x
        && point.y <= position.y + size.y;
}


Imgui_State :: struct {
    test_toggle: bool;
    test_color := Vector4.{0.8, 0.5, 0.2, 1};
    test_enum: enum { ZERO; ONE; TWO; }
    test_struct: struct {a: struct {a_a: bool; a_b: bool;} b: struct {b_a: bool; b_b: bool;}}
    test_string: [STRING_ENTRY_MAX_COUNT] u8;
    test_string[0] = #char "T";
    test_string[1] = #char "E";
    test_string[2] = #char "S";
    test_string[3] = #char "T";
    test_string_count := 4;
    events: [MAX_INPUT_EVENTS_PER_TICK] Input_Event; // :DynamicArray
    event_count: int;
    mouse: Vector2;
   
    
    // This is kind of confusing so I will attempt to explain it.
    // We need a way to uniquely identify widgets so we can store
    // what widget is active. Using just #caller_location is not 
    // enough because some widgets want to draw sub-widgets, and
    // those sub-widgets need unique identifiers.
    
    // We pass a unique id along with the loc so if multiple widgets
    // need to be drawn from the same loc, you can use the id to
    // differentiate them. We need to store the ids of all widgets
    // higher up in the stack so we can uniquely identify a widget
    // at whatever depth in the callstack.

    //          -berk, 2025 - 3 - 17

    current_widget_loc: Source_Code_Location;
    current_widget_id: [64] u64; // :DynamicArray
    current_widget_id_count: int;

    current_widget_state: Widget_State;

    active_widget_exists: bool;
    active_widget_loc: Source_Code_Location;
    active_widget_id: [64] u64; // :DynamicArray
    active_widget_id_count: int;
    active_widget_data: Active_Widget_Data;
}


Widget_State :: enum {
    NO_ONE;
    NOT_ME;
    ACTIVE;
}


operator == :: (a: Source_Code_Location, b: Source_Code_Location) -> bool {
    return a.fully_pathed_filename == b.fully_pathed_filename
        && a.line_number           == b.line_number
        && a.character_number      == b.character_number;
}


scope_widget :: (loc: Source_Code_Location, id: u64) #expand {
    using context.game_context.imgui_state;

    assert(current_widget_id_count < current_widget_id.count);
    
    if current_widget_id_count != 0 {
        assert(loc == current_widget_loc);
    } else {
        current_widget_loc = loc;
    }


    current_widget_id[current_widget_id_count] = id;
    old_count := current_widget_id_count;
    current_widget_id_count += 1;

    old_current_widget_state := current_widget_state;

    if !active_widget_exists {
        current_widget_state = .NO_ONE;
    } else {
        // @Speed we could figure out if we're in the same branch of the stack as the currently active widget, and if so, then set a flag.
        // Then, if the flag is set, we can just check the most recent id to determine if this is the active widget. If the flag is not set,
        // then we know for sure that this is not the active widget.
        if current_widget_loc == active_widget_loc
        && current_widget_id_count == active_widget_id_count
        && memcmp(current_widget_id.data, active_widget_id.data, current_widget_id_count * size_of(type_of(current_widget_id.data.*))) == 0 {
            current_widget_state = .ACTIVE;
        } else {
            current_widget_state = .NOT_ME;
        }
    }

    `defer {
        current_widget_id_count -= 1;
        assert(old_count == current_widget_id_count);
        
        // A subwidget was activated. Steal focus from this widget.
        if old_current_widget_state == .NO_ONE && active_widget_exists {
            current_widget_state = .NOT_ME;
        } else {
            current_widget_state = old_current_widget_state;
        }
    }
}


activate :: (data: Active_Widget_Data) {
    using context.game_context.imgui_state;
    assert(!active_widget_exists && current_widget_state == .NO_ONE);
    active_widget_exists = true;
    active_widget_loc = current_widget_loc;
    active_widget_id_count = current_widget_id_count;
    memcpy(active_widget_id.data, current_widget_id.data, current_widget_id_count * size_of(type_of(current_widget_id.data.*)));
    active_widget_data = data;
    current_widget_state = .ACTIVE;
}


deactivate :: () {
    using context.game_context.imgui_state;
    assert(active_widget_exists && current_widget_state == .ACTIVE);
    active_widget_exists = false;
    current_widget_state = .NO_ONE;
}


HIGHLIGHT_COLOR :: Vector4.{1, 1, 1, 1};
DULL_COLOR :: Vector4.{0.5, 0.5, 0.5, 1};
READ_ONLY_COLOR :: Vector4.{0.3, 0.3, 0.3, 1};
BACKGROUND_COLOR :: Vector4.{0, 0, 0, 1};


Active_Widget_Data :: struct {
    type: enum {
        SV;
        SLIDER;
        BUTTON;
        STRING_ENTRY;
    }
    union {
        sv: struct {
            hue: float;
            // When we're dragging the cursor around,
            // if we drag it such that s or v become
            // 0, the hue also becomes 0 because that's
            // how the conversion function works.
            // So we preserve it here.
        }
        string_entry: struct {
            // :DynamicArray
            cursor: int;
            str: [STRING_ENTRY_MAX_COUNT] u8;
            str_count: int;
        }
    }
}


label :: (text: string, position: Vector2, size: Vector2) -> used_length: float {
    using context.game_context;

    font := *consolas_small;

    margin := font.ascender * 0.2;
    text_position := Vector2.{
        position.x + margin,
        position.y + size.y / 2 + font.ascender / 2
    };

    
    draw_text(text, text_position, font, HIGHLIGHT_COLOR);

    return text_length(text, font) + margin * 2;
}


toggle :: (val: *bool, position: Vector2, size: Vector2, read_only := false, loc := #caller_location, id: u64 = 0) {
    using context.game_context;
    using context.game_context.imgui_state;
    
    scope_widget(loc, id);

    font := *consolas_small;
    margin := font.ascender * 0.2;
    
    outline_outer_width := font.ascender * 1.5;
    outline_outer_size := Vector2.{outline_outer_width, outline_outer_width};

    outline_inner_width := font.ascender * 1.3;
    outline_inner_size := Vector2.{outline_inner_width, outline_inner_width};

    toggle_center := Vector2.{
        position.x + size.x - margin - outline_outer_size.x / 2,
        position.y + size.y / 2
    };
    
    outline_outer_position := toggle_center - outline_outer_size / 2;
    outline_inner_position := toggle_center - outline_inner_size / 2;

    color: Vector4;

    if read_only {
        color = READ_ONLY_COLOR;
    } else {
        color = HIGHLIGHT_COLOR;
        if current_widget_state == .NO_ONE && inside(outline_outer_position, outline_outer_size, mouse) {
            for [] Input_Event.{event_count, events.data} {
                if it.key == .MOUSE_LEFT_BUTTON && it.state == .DOWN {
                    val.* = !val.*;
                }
            }
        }
    }
    
    
    set_shader(imm_color_shader, .{});
    set_uniform("projection", ui_to_camera);

    imm_quad(outline_outer_position, outline_outer_size, color);
    imm_quad(outline_inner_position, outline_inner_size, BACKGROUND_COLOR);
    imm_flush();

    if val.* {
        selected_width := font.ascender * 0.9;
        selected_size := Vector2.{selected_width, selected_width};
        selected_position := toggle_center - selected_size / 2;
        imm_quad(selected_position, selected_size, color);
    }

    imm_flush();
}


slider :: (value: *float, position: Vector2, size: Vector2, strictly_less_than_1 := true, loc := #caller_location, id: u64 = 0) {
    using context.game_context;
    using context.game_context.imgui_state;

    scope_widget(loc, id);

    if current_widget_state == {
        case .ACTIVE;
            for [] Input_Event.{event_count, events.data} {
                if it.key == .MOUSE_LEFT_BUTTON && it.state == .UP {
                    deactivate();
                    event_count = 0;
                    // We clear the input events because this widget consumed it.
                    // We don't want another widget acting on the input event that deactivated
                    // this widget.
                }
            }

        case .NO_ONE;
            if inside(position, size, mouse) {
                for [] Input_Event.{event_count, events.data} {
                    if it.key == .MOUSE_LEFT_BUTTON && it.state == .DOWN {
                        activate(.{type = .SLIDER});
                        break;
                    }
                }
            }
    }

    cursor_x: float;
    if #complete current_widget_state == {
        case .ACTIVE;
            assert(active_widget_data.type == .SLIDER);

            end_x := position.x + size.x;

            epsilon := 0.0;
            if strictly_less_than_1 epsilon = 0.001;

            cursor_x = clamp(mouse.x, position.x, end_x - epsilon);
            value.* = (cursor_x - position.x) / (end_x - position.x);
        case .NOT_ME; #through;
        case .NO_ONE;
            cursor_x = position.x + size.x * value.*;
    }

    bar_width := size.y * 0.1;
    bar_position := Vector2.{
        cursor_x - bar_width / 2,
        position.y
    };

    bar_size := Vector2.{
        bar_width,
        size.y
    };
    
    set_shader(imm_color_shader, .{});
    set_uniform("projection", ui_to_camera);
    imm_quad(bar_position, bar_size, HIGHLIGHT_COLOR);
    imm_flush();
}


color_selector :: (color: *Vector4, position: Vector2, field_size: Vector2, loc := #caller_location, id: u64 = 0) -> height: float {
    using context.game_context;
    using context.game_context.imgui_state;

    scope_widget(loc, id);

    font := *consolas_small;
    margin := font.ascender * 0.2;

    head := position;
    head.x += margin;

    bar_width := field_size.x - 2 * margin;
   



    sample_position := head;
    sample_size := Vector2.{bar_width, field_size.y};

    head.y += field_size.y + margin;

    sv_position := head;
    sv_size := Vector2.{bar_width, bar_width};

    sv_x0 := sv_position.x;
    sv_y0 := sv_position.y;
    sv_x1 := sv_position.x + sv_size.x;
    sv_y1 := sv_position.y + sv_size.y;

    head.y += sv_size.y + margin;

    hue_position := head;
    hue_size := Vector2.{bar_width, field_size.y};
    hue_x0 := hue_position.x;
    hue_y0 := hue_position.y;
    hue_x1 := hue_position.x + hue_size.x;
    hue_y1 := hue_position.y + hue_size.y;

    head.y += field_size.y + margin;

    alpha_position := head;
    alpha_size := Vector2.{bar_width, field_size.y};

    head.y += field_size.y + margin;



    // :ReversedValue imgui is now drawn y-down, but we want saturation to go from 0 at the
    // bottom y value (greatest) and 1 at the top high value (least). So, we have to reverse
    // the y value.

    // @TODO: Draw a little alpha checkerboard texture underneath this.
    set_shader(imm_color_shader, .{});
    set_uniform("projection", ui_to_camera);
    alpha_x0 := alpha_position.x;
    alpha_y0 := alpha_position.y;
    alpha_x1 := alpha_x0 + alpha_size.x;
    alpha_y1 := alpha_y0 + alpha_size.y;
    imm_vertex(.{alpha_x0, alpha_y0, 0}, .{1, 1, 1, 1});
    imm_vertex(.{alpha_x1, alpha_y0, 0}, .{0, 0, 0, 1});
    imm_vertex(.{alpha_x1, alpha_y1, 0}, .{0, 0, 0, 1});
    imm_vertex(.{alpha_x0, alpha_y0, 0}, .{1, 1, 1, 1});
    imm_vertex(.{alpha_x1, alpha_y1, 0}, .{0, 0, 0, 1});
    imm_vertex(.{alpha_x0, alpha_y1, 0}, .{1, 1, 1, 1});
    imm_flush();

    slider(*color.w, alpha_position, alpha_size, loc=loc, id=0);
    
    set_shader(imm_hue_shader, .{});
    set_uniform("projection", ui_to_camera);
    imm_vertex(.{hue_x0, hue_y0, 0}, .{0, 0});
    imm_vertex(.{hue_x1, hue_y0, 0}, .{1, 0});
    imm_vertex(.{hue_x1, hue_y1, 0}, .{1, 1});
    imm_vertex(.{hue_x0, hue_y0, 0}, .{0, 0});
    imm_vertex(.{hue_x0, hue_y1, 0}, .{0, 1});
    imm_vertex(.{hue_x1, hue_y1, 0}, .{1, 1});
    imm_flush();

    hue, saturation, value := rgb_to_hsv(color.x, color.y, color.z);
    
    if current_widget_state == .ACTIVE {
        assert(active_widget_data.type == .SV);
        hue = active_widget_data.sv.hue;
    }


    slider(*hue, hue_position, hue_size, loc=loc, id=1);
    color.x, color.y, color.z = hsv_to_rgb(hue, saturation, value);

    if current_widget_state == {
        case .ACTIVE;
            for [] Input_Event.{event_count, events.data} {
                if it.key == .MOUSE_LEFT_BUTTON && it.state == .UP {
                    deactivate();
                    event_count = 0;
                    break;
                }
            }

        case .NO_ONE;
            if inside(sv_position, sv_size, mouse) {
                for [] Input_Event.{event_count, events.data} {
                    if it.key == .MOUSE_LEFT_BUTTON && it.state == .DOWN {
                        activate(.{
                            type = .SV,
                            sv = .{hue = hue}
                        });
                    }
                }
            }
    }

    sv_cursor: Vector2;

    if #complete current_widget_state == {
        case .ACTIVE;
            assert(active_widget_data.type == .SV);
            sv_cursor = mouse;
            clamp(*sv_cursor.x, sv_x0, sv_x1);
            clamp(*sv_cursor.y, sv_y0, sv_y1);

            saturation = (sv_cursor.x - sv_x0) / (sv_x1 - sv_x0);
            value = 1.0 - (sv_cursor.y - sv_y0) / (sv_y1 - sv_y0); // :ReversedValue
            
            color.x, color.y, color.z = hsv_to_rgb(hue, saturation, value);
        case .NOT_ME; #through;
        case .NO_ONE;
            sv_cursor = Vector2.{
                lerp(sv_x0, sv_x1, saturation),
                lerp(sv_y0, sv_y1, 1 - value) // :ReversedValue
            };
    }

    sv_cursor_offset_big := bar_width * 0.02;
    sv_cursor_offset_small := bar_width * 0.005;

    sv_cursor_hbar_position := Vector2.{
        sv_cursor.x - sv_cursor_offset_small,
        sv_cursor.y - sv_cursor_offset_big,
    };

    sv_cursor_hbar_size := Vector2.{
        sv_cursor_offset_small * 2,
        sv_cursor_offset_big * 2,
    };

    
    sv_cursor_vbar_position := Vector2.{
        sv_cursor.x - sv_cursor_offset_big,
        sv_cursor.y - sv_cursor_offset_small,
    };

    sv_cursor_vbar_size := Vector2.{
        sv_cursor_offset_big * 2,
        sv_cursor_offset_small * 2,
    };

    
    set_shader(imm_saturation_value_shader, .{});
    set_uniform("projection", ui_to_camera);
    set_uniform("hue", hue);
    imm_vertex(.{sv_x0, sv_y0, 0}, .{0, 1});
    imm_vertex(.{sv_x1, sv_y0, 0}, .{1, 1});
    imm_vertex(.{sv_x1, sv_y1, 0}, .{1, 0});
    imm_vertex(.{sv_x0, sv_y0, 0}, .{0, 1});
    imm_vertex(.{sv_x1, sv_y1, 0}, .{1, 0});
    imm_vertex(.{sv_x0, sv_y1, 0}, .{0, 0});
    imm_flush();
    
    set_shader(imm_color_shader, .{});
    set_uniform("projection", ui_to_camera);
    imm_quad(sample_position, sample_size, color.*);
    imm_quad(sv_cursor_hbar_position, sv_cursor_hbar_size, HIGHLIGHT_COLOR);
    imm_quad(sv_cursor_vbar_position, sv_cursor_vbar_size, HIGHLIGHT_COLOR);
    imm_flush();

    return head.y;
}


enum_selector :: (
    val: *$T,
    position: Vector2,
    size: Vector2,
    loc := #caller_location,
    id: u64 = 0
) {
    INFO :: type_info(T);
    #assert type_of(INFO) == *Type_Info_Enum;
    enum_selector(val, INFO, position, size, alignment, loc, id);
}


enum_selector :: (
    val: *void,
    info: *Type_Info_Enum,
    position: Vector2,
    size: Vector2,
    loc: Source_Code_Location,
    id: u64
) {
    using context.game_context;

    scope_widget(loc, id);

    font := *consolas_small;
    
    margin := font.ascender * 0.2;
    button_height := size.y - margin * 2;
    
    right_button_position := Vector2.{
        position.x + size.x - margin - button_height,
        position.y + margin
    };

    left_button_position := Vector2.{
        right_button_position.x - margin - button_height,
        right_button_position.y
    };

    button_size := Vector2.{button_height, button_height};

    val_s64 := expand_to_s64(val, info.internal_type);

    member_index := -1;
    for info.values {
        if it == val_s64 {
            member_index = it_index;
            break;
        }
    }
    if member_index == -1 member_index = 0;
    // Default to the first value if for some reason the enum got set to some other value.

    if button("<",  left_button_position, button_size, loc=loc, id=0) {
        member_index = (member_index - 1 + info.values.count) % info.values.count;
    }

    if button(">", right_button_position, button_size, loc=loc, id=1) {
        member_index = (member_index + 1) % info.values.count;
    }
    
    assign_int(info.internal_type, val, info.values[member_index]);


    member_text := info.names[member_index];
    
    text_x := left_button_position.x - margin - text_length(member_text, font);
    text_y := position.y + size.y / 2 + font.ascender / 2;

    draw_text(member_text, .{text_x, text_y}, font, DULL_COLOR);
}


button :: (label: string, position: Vector2, size: Vector2, loc := #caller_location, id: u64 = 0) -> bool {
    using context.game_context;
    using context.game_context.imgui_state;

    scope_widget(loc, id);

    clicked := false;

    if current_widget_state == {
        case .ACTIVE;
            for [] Input_Event.{event_count, events.data} {
                if it.key == .MOUSE_LEFT_BUTTON && it.state == .UP {
                    deactivate();
                    event_count = 0;
                    break;
                }
            }
        case .NO_ONE;
            if inside(position, size, mouse) {
                for [] Input_Event.{event_count, events.data} {
                    if it.key == .MOUSE_LEFT_BUTTON && it.state == .DOWN {
                        activate(.{
                            type = .BUTTON
                        });
                        clicked = true;
                        break;
                    }
                }
            }
    }

    color: Vector4;
    if #complete current_widget_state == {
        case .ACTIVE;
            assert(active_widget_data.type == .BUTTON);
            color = DULL_COLOR;
        case .NO_ONE; #through;
        case .NOT_ME;
            color = HIGHLIGHT_COLOR;
    }
    

    font := *consolas_small;

    width := floor(font.ascender * 0.05);
    
    set_shader(imm_color_shader, .{});
    set_uniform("projection", ui_to_camera);
    imm_quad(position, size, color);
    
    inner_position := Vector2.{position.x + width, position.y + width};
    inner_size     := Vector2.{size.x - width * 2, size.y - width * 2};
    imm_quad(inner_position, inner_size, BACKGROUND_COLOR);
    imm_flush();

    text_x := position.x + size.x / 2 - text_length(label, font) / 2;
    text_y := position.y + size.y / 2 + font.ascender / 2;
    draw_text(label, .{text_x, text_y}, font, color);

    return clicked;
}


STRING_ENTRY_MAX_COUNT :: 128;
string_entry :: (
    position: Vector2,
    size: Vector2,
    str: *[STRING_ENTRY_MAX_COUNT] u8,
    str_count: *int,
    read_only := false,
    loc := #caller_location,
    id: u64 = 0
) -> entered: bool {
    using context.game_context;
    using context.game_context.imgui_state;

    assert(str_count.* <= str.count);

    scope_widget(loc, id);

    font := *consolas_small;
    margin := font.ascender * 0.2;

    inner_height := font.ascender * 1.5;

    outer_size := Vector2.{
        size.x,
        inner_height + margin * 2
    };

    outer_position := Vector2.{
        position.x,
        position.y + size.y / 2 - outer_size.y / 2
    };

    inner_size := Vector2.{
        size.x - margin * 2,
        inner_height
    };

    inner_position := Vector2.{
        outer_position.x + margin,
        outer_position.y + margin
    };

    text_position := Vector2.{
        position.x + margin,
        position.y + size.y / 2 + font.ascender / 2
    };

    entered: bool;

    if current_widget_state == {
        case .ACTIVE;
            using active_widget_data;
            assert(type == .STRING_ENTRY);

            if read_only { // If we became read-only for some reason, deactivate this.
                deactivate();
                event_count = 0;
            } else {
                // @TODO: Add a selection mode like the standard computer text entry field has

                mouse_outside := !inside(outer_position, outer_size, mouse);
                for [] Input_Event.{event_count, events.data} {

                    if (it.key == .ENTER || (mouse_outside && it.key == .MOUSE_LEFT_BUTTON)) && it.state == .DOWN {
                        memcpy(str.data, string_entry.str.data, string_entry.str_count);
                        str_count.* = string_entry.str_count;
                        deactivate();
                        event_count = 0;
                        entered = it.key == .ENTER;
                        break;
                    }
                    
                    // @TODO: Handle all non-alphabetic keys that are modified by the SHIFT key
                    if (#char " " <= it.key && it.key <= #char "~") && it.state != .UP && string_entry.str_count < string_entry.str.count {
                        key := it.key;

                        if keys_down[Key.SHIFT] {   
                            // @TODO: Number keys
                            if key == {
                                case #char "["; key = #char "{";
                                case #char "]"; key = #char "}";
                                case #char ";"; key = #char ":";
                                case #char "/"; key = #char "?";
                                case #char "."; key = #char ">";
                                case #char ","; key = #char "<";
                                // case #char "'"; key = #char "\"";
                                // :SerializeStrings I'm turning this off for now until we can serialize it.
                                case #char"\\"; key = #char "|";
                                case #char "-"; key = #char "_";
                                case #char "="; key = #char "+";
                            }
                        } else {
                            // The capital letter being the keycode is a windows convention.
                            // Should we just change them to being lowercase?
                            if #char "A" <= key && key <= #char "Z" {
                                key = #char "a" + key - #char "A";
                            } else if key == #char "\\" {
                                key = #char "|";
                                // :SerializeStrings
                            }
                        }

                        for #v2 < string_entry.cursor..string_entry.str_count-1 {
                            string_entry.str[it + 1] = string_entry.str[it];
                        }
                        string_entry.str[string_entry.cursor] = xx key;
                        string_entry.str_count += 1;
                        string_entry.cursor += 1;

                        continue;
                    }

                    if (it.key == .DELETE || it.key == .BACKSPACE) && it.state != .UP {
                        delete_all := keys_down[Key.SHIFT];

                        if delete_all {
                            string_entry.str_count = 0;
                            string_entry.cursor = 0;
                            continue;
                        }

                        if string_entry.str_count > 0 {
                            start := ifx string_entry.cursor > 0 then string_entry.cursor else 1;
                            for start..string_entry.str_count-1 {
                                string_entry.str[it - 1] = string_entry.str[it];
                            }
                            string_entry.str_count -= 1;
                            if string_entry.cursor > 0 string_entry.cursor -= 1;
                        }
                        continue;
                    }

                    if it.key == .LEFT_ARROW && it.state != .UP {
                        if string_entry.cursor > 0 string_entry.cursor -= 1;
                        continue;
                    }

                    if it.key == .RIGHT_ARROW && it.state != .UP {
                        if string_entry.cursor < string_entry.str_count string_entry.cursor += 1;
                        continue;
                    }

                    if it.key == .HOME && it.state != .UP {
                        string_entry.cursor = 0;
                        continue;
                    }

                    if it.key == .END && it.state != .UP {
                        string_entry.cursor = string_entry.str_count;
                        continue;
                    }
                }
            }

        case .NO_ONE;
            if !read_only && inside(outer_position, outer_size, mouse) {
                for [] Input_Event.{event_count, events.data} {
                    if it.state == .DOWN && it.key == .MOUSE_LEFT_BUTTON {    
                        data: Active_Widget_Data;
                        data.type = .STRING_ENTRY;
                        memcpy(data.string_entry.str.data, str.data, str_count.*);
                        data.string_entry.str_count = str_count.*;
                        data.string_entry.cursor = str_count.*;
                        activate(data);
                        break;
                    }
                }
            }
    }

    
    color: Vector4;
    string_to_draw: string;
    
    if #complete current_widget_state == {
        case .ACTIVE;
            assert(!read_only);
            color = HIGHLIGHT_COLOR;
            string_to_draw = .{active_widget_data.string_entry.str_count, active_widget_data.string_entry.str.data};
        case .NOT_ME; #through;
        case .NO_ONE;
            color = ifx read_only then READ_ONLY_COLOR else DULL_COLOR;
            string_to_draw = .{str_count.*, str.data};
    }

    
    set_shader(imm_color_shader, .{});
    set_uniform("projection", ui_to_camera);
    imm_quad(outer_position, outer_size, color);
    imm_quad(inner_position, inner_size, BACKGROUND_COLOR);

    if current_widget_state == .ACTIVE {
        using active_widget_data;

        cursor_width := margin;
        cursor_position := Vector2.{
            text_position.x + text_length(.{string_entry.cursor, string_entry.str.data}, font) - cursor_width / 2,
            text_position.y - font.ascender * 1.1
        };
        cursor_size := Vector2.{
            cursor_width,
            font.ascender * 1.2
        };

        imm_quad(cursor_position, cursor_size, color);
    }

    imm_flush();
    
    // @TODO: Push a new scissor, or find some way to cut off the text we draw.
    draw_text(string_to_draw, text_position, font, color);

    return entered;
}


number_entry :: (
    position: Vector2,
    size: Vector2,
    val: *$T,
    loc := #caller_location,
    id: u64 = 0
) -> entered: bool {
    return number_entry(position, size, val, type_info(T), loc=loc, id=id);
}


number_entry :: (
    position: Vector2,
    size: Vector2,
    val: *void,
    info: *Type_Info,
    read_only := false,
    loc := #caller_location,
    id: u64 = 0
) -> entered: bool {
    using context.game_context;
    assert(info.type == .INTEGER || info.type == .FLOAT);
    
    // @Speed Make the String_Builder print directly into here.
    str: [STRING_ENTRY_MAX_COUNT] u8;
    str_count: int;
    {
        scope_mark(frame_arena);
        sb := make_string_builder(frame_arena);
        print(*sb, "%", dynamic_any(info, val));
        val_str := get_string(*sb);
        
        str_count = val_str.count;
        memcpy(str.data, val_str.data, str_count);
    }

    
    
    entered := string_entry(position, size, *str, *str_count, read_only=read_only, loc=loc, id=id);
    if !entered return false;
    assert(!read_only);

    success, end_index, is_float, int_value, float_value := parse_number(.{str_count, str.data}, 0);
    if !success return true;
    if end_index != str_count return true;

    if is_float {
        if info.type == .FLOAT {
            assign_float(xx info, val, float_value);
        } else {
            assign_int(xx info, val, xx float_value);
        }
    } else {
        if info.type == .INTEGER {
            assign_int(xx info, val, int_value);
        } else {
            assign_float(xx info, val, xx int_value);
        }
    }

    return true;
}



imgui_for_value :: (val: *$T, position: Vector2, field_size: Vector2, arena: *Memory_Arena, loc := #caller_location, id: u64 = 0) {
    imgui_for_value(val, type_info(T), position, field_size, arena, loc=loc, id=id);
}


imgui_for_value :: (val: *void, info: *Type_Info, position: Vector2, field_size: Vector2, arena: *Memory_Arena, read_only := false, loc := #caller_location, id: u64 = 0) -> end_y: float {
    using context.game_context;
    scope_widget(loc, id);

    font := *consolas_small;
    margin := font.ascender * 0.2;
    indent := font.ascender * 2;

    if info.type == {
        case .STRUCT;
            struct_info := cast(*Type_Info_Struct, info);
            greatest_offset := -1;
            y := position.y;
            for * struct_info.members {
                // The members visible in the editor are strictly a subset of what we can 
                // serialize... for now.
                if !can_serialize_member(it, greatest_offset) continue;
                greatest_offset = it.offset_in_bytes;
                
                if it.type.type == .ARRAY { 
                    // @TODO: Implement an actual editor for these
                    continue;
                }

                member_read_only := read_only || contains(it.notes, "ReadOnly");
                text_color := ifx member_read_only then READ_ONLY_COLOR else HIGHLIGHT_COLOR;
               

                label_position := Vector2.{
                    position.x + margin,
                    y + field_size.y / 2 + font.ascender / 2
                };

                text_end := draw_text(it.name, label_position, font, text_color);

                value_position: Vector2;
                if it.type.type == .STRUCT {
                    value_position = Vector2.{
                        position.x + indent,
                        y + field_size.y
                    };
                } else {
                    value_position = Vector2.{
                        text_end + margin,
                        y
                    };
                }
                
                value_size := Vector2.{
                    position.x + field_size.x - value_position.x,
                    field_size.y
                };


                if it.type == type_info(Vector4) && contains(it.notes, "Color") {
                    y = color_selector(val + it.offset_in_bytes, value_position, value_size, loc, xx it_index);
                    // @TODO: Implement a ReadOnly color selector
                } else {
                    new_y := imgui_for_value(val + it.offset_in_bytes, it.type, value_position, value_size, arena, read_only=member_read_only, loc=loc, id=xx it_index);
                    if new_y < y + field_size.y y = field_size.y;
                    else y = new_y;
                }
            }
            return y;
        case .BOOL;
            toggle(val, position, field_size, read_only=read_only, loc=loc);
            return position.y + field_size.y;
        case .ENUM;
            enum_info := cast(*Type_Info_Enum, info);
            enum_selector(val, enum_info, position, field_size, loc, 0);
            return position.y + field_size.y;
        case .INTEGER; #through;
        case .FLOAT;
            number_entry(position, field_size, val, info, read_only=read_only, loc=loc);
            return position.y + field_size.y;
        case .VARIANT;
            variant_info := cast(*Type_Info_Variant, info);
            return imgui_for_value(val, variant_info.variant_of, position, field_size, arena, read_only=read_only, loc=loc);
        case .STRING;
            str := cast(*string, val);
            input_field: [STRING_ENTRY_MAX_COUNT] u8;
            input_field_count := str.count;
            memcpy(input_field.data, str.data, min(str.count, input_field.count));
            entered := string_entry(position, field_size, *input_field, *input_field_count, read_only=read_only, loc=loc);

            if entered {
                str.* = copy_string(arena, .{input_field_count, input_field.data});
            }
            return position.y + field_size.y;
        case .ARRAY;
            // @TODO: Implement editors for these
            assert(false);
            return 0;

        case;
            // These should never be exposed to the editor.
            assert(false);
            return 0;
    }
}

/*
vertical_scroll_begin :: (scroll: *float, position: Vector2, size: Vector2) -> start_y: float {
    using context.game_context;
    glEnable(GL_SCISSOR_TEST);
}


vertical_scroll_end :: (scroll: *float, end_height: float) {
    glDisable(GL_SCISSOR_TEST);
}
*/
