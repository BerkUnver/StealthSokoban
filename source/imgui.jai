inside :: (position: Vector2, size: Vector2, point: Vector2) -> bool {
    return point.x >= position.x
        && point.y >= position.y
        && point.x <= position.x + size.x
        && point.y <= position.y + size.y;
}


Imgui_State :: struct {
    imgui_to_camera: Matrix4;
    camera_to_imgui: Matrix4;
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
   
    // Do not read from these directly. Use the functions below.

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


this_is_the_active_widget :: () -> bool {
    using context.game_context.imgui_state;
    assert(active_widget_exists);
    // @Speed we could store if the current branch of widgets we are in is one where the
    // active widget could exist and check only what we need to check.
    return current_widget_loc == active_widget_loc
        && current_widget_id_count == active_widget_id_count
        && memcmp(current_widget_id.data, active_widget_id.data, current_widget_id_count * size_of(type_of(current_widget_id.data.*))) == 0;
}


scope_widget :: (loc: Source_Code_Location, id: u64) -> Widget_State, *Active_Widget_Data #expand {
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

    `defer {
        current_widget_id_count -= 1;
        assert(old_count == current_widget_id_count);
    }

    if !active_widget_exists        return .NO_ONE, null;
    if !this_is_the_active_widget() return .NOT_ME, null;

    return .ACTIVE, *active_widget_data;
}


activate :: (data: Active_Widget_Data) {
    using context.game_context.imgui_state;
    assert(!active_widget_exists);
    active_widget_exists = true;
    active_widget_loc = current_widget_loc;
    active_widget_id_count = current_widget_id_count;
    memcpy(active_widget_id.data, current_widget_id.data, current_widget_id_count * size_of(type_of(current_widget_id.data.*)));
    active_widget_data = data;
}


deactivate :: () {
    using context.game_context.imgui_state;
    assert(active_widget_exists);
    assert(this_is_the_active_widget());
    active_widget_exists = false;
}


HIGHLIGHT_COLOR :: Vector4.{1, 1, 1, 1};
DULL_COLOR :: Vector4.{0.6, 0.6, 0.6, 1};
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
            mouse_offset: Vector2;
            hue: float;
            // When we're dragging the cursor around,
            // if we drag it such that s or v become
            // 0, the hue also becomes 0 because that's
            // how the conversion function works.
            // So we preserve it here.
        }
        slider: struct {
            mouse_offset_x: float;
        }
        string_entry: struct {
            // :DynamicArray
            str: [STRING_ENTRY_MAX_COUNT] u8;
            str_count: int;
        }
    }
}


imgui_init :: () -> Imgui_State {
    using imgui_state: Imgui_State;

    // We do the " / 2" because we actually need to zoom in twice as much to account
    // for the starting matrix ranging from [1, -1] on the x and y axis. We need the 
    // final matrix to range from [0, INNER_WINDOW_W] on the x and [0, INNER_WINDOW_H]
    // on the y.

    zoom_in_matrix := Matrix4_Identity;
    zoom_in_matrix._11 /= INNER_WINDOW_W / 2;
    zoom_in_matrix._22 /= -INNER_WINDOW_H / 2;
    imgui_to_camera = make_translation_matrix4(.{-1, 1, 0}) * zoom_in_matrix;

    zoom_out_matrix := Matrix4_Identity;
    zoom_out_matrix._11 *= INNER_WINDOW_W / 2;
    zoom_out_matrix._22 *= -INNER_WINDOW_H / 2;
    camera_to_imgui = zoom_out_matrix * make_translation_matrix4(.{1, -1, 0});

    return imgui_state;
}


imgui_draw_text :: (str: string, position: Vector2, font: *Font, color: Vector4) -> end_x: float {
    using context.game_context;

    glUseProgram(imm_text_shader);
    
    set_uniform_bitmap("bitmap", 0, font.bitmap);
    set_uniform("projection", imgui_state.imgui_to_camera);
    
    x := position.x;
    y := position.y;

    for str {
        if it == #char " " {
            x += font.space_advance;
        } else {
            assert(VALID_ASCII_START <= it && it <= VALID_ASCII_END);
            using glyph := *font.glyphs[it - VALID_ASCII_START];

            x0 := x + bearing.x;
            y0 := y - bearing.y;
            x1 := x0 + size.x;
            y1 := y0 + size.y;

            imm_vertex(.{x0, y0, 0}, .{uv_x0, uv_y0}, color);
            imm_vertex(.{x1, y0, 0}, .{uv_x1, uv_y0}, color);
            imm_vertex(.{x1, y1, 0}, .{uv_x1, uv_y1}, color);

            imm_vertex(.{x0, y0, 0}, .{uv_x0, uv_y0}, color);
            imm_vertex(.{x1, y1, 0}, .{uv_x1, uv_y1}, color);
            imm_vertex(.{x0, y1, 0}, .{uv_x0, uv_y1}, color);

            x += advance;
        }
    }

    imm_flush();

    return x;
}


toggle :: (val: *bool, position: Vector2, size: Vector2, loc := #caller_location, id: u64 = 0) {
    using context.game_context;
    using context.game_context.imgui_state;
    
    state := scope_widget(loc, id);

    font := *consolas;
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
    
    if state == .NO_ONE && inside(outline_outer_position, outline_outer_size, mouse) {
        for [] Input_Event.{event_count, events.data} {
            if it.key == .MOUSE_LEFT_BUTTON && it.down {
                val.* = !val.*;
            }
        }
    }

    glUseProgram(imm_color_shader);
    set_uniform("projection", imgui_to_camera);

    imm_quad(round(outline_outer_position), round(outline_outer_size), HIGHLIGHT_COLOR);
    imm_quad(round(outline_inner_position), round(outline_inner_size), BACKGROUND_COLOR);
    imm_flush();

    if val.* {
        selected_width := font.ascender * 0.9;
        selected_size := Vector2.{selected_width, selected_width};
        selected_position := toggle_center - selected_size / 2;
        imm_quad(round(selected_position), round(selected_size), HIGHLIGHT_COLOR);
    }

    imm_flush();
}


slider :: (value: *float, position: Vector2, size: Vector2, strictly_less_than_1 := true, loc := #caller_location, id: u64 = 0) {
    using context.game_context;
    using context.game_context.imgui_state;

    state, data := scope_widget(loc, id);

    cursor_x := position.x + size.x * value.*;

    if state == {
        case .ACTIVE;
            using data;
            assert(type == .SLIDER);

            end_x := position.x + size.x;

            epsilon := 0.0;
            if strictly_less_than_1 epsilon = 0.001;

            cursor_x = clamp(mouse.x + data.slider.mouse_offset_x, position.x, end_x - epsilon);
            value.* = (cursor_x - position.x) / (end_x - position.x);

            for [] Input_Event.{event_count, events.data} {
                if it.key == .MOUSE_LEFT_BUTTON && !it.down {
                    deactivate();
                    event_count = 0;
                    // We clear the input events because this widget consumed it.
                    // We don't want another widget acting on the input event that deactivated
                    // this widget.
                }
            }

        case .NO_ONE;
            cursor_width := size.x * 0.04;
            cursor_position := Vector2.{
                cursor_x - cursor_width / 2,
                position.y
            };
            cursor_size := Vector2.{
                cursor_width,
                size.y
            };

            if inside(cursor_position, cursor_size, mouse) {
                for [] Input_Event.{event_count, events.data} {
                    if it.key == .MOUSE_LEFT_BUTTON && it.down {
                        activate(.{
                            type = .SLIDER,
                            slider = .{mouse_offset_x = cursor_x - mouse.x}
                        });
                        break;
                    }
                }
            }
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

    glUseProgram(imm_color_shader);
    set_uniform("projection", imgui_to_camera);
    imm_quad(bar_position, bar_size, HIGHLIGHT_COLOR);
    imm_flush();
}


color_selector :: (color: *Vector4, position: Vector2, field_size: Vector2, loc := #caller_location, id: u64 = 0) -> height: float {
    using context.game_context;
    using context.game_context.imgui_state;

    state, data := scope_widget(loc, id);

    font := *consolas;
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




    // Store what we expect the values to be, then reassign them
    // when we check input if they change.
    hue, saturation, value := rgb_to_hsv(color.x, color.y, color.z);
    
    if state == .ACTIVE {
        assert(data.type == .SV);
        hue = data.sv.hue;
    }


    // :ReversedValue imgui is now drawn y-down, but we want saturation to go from 0 at the
    // bottom y value (greatest) and 1 at the top high value (least). So, we have to reverse
    // the y value.

    sv_cursor := Vector2.{
        lerp(sv_x0, sv_x1, saturation),
        lerp(sv_y0, sv_y1, 1 - value) // :ReversedValue
    };

    
    // @TODO: Draw a little alpha checkerboard texture underneath this.
    glUseProgram(imm_color_shader);
    set_uniform("projection", imgui_to_camera);
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

    glUseProgram(imm_hue_shader);
    set_uniform("projection", imgui_to_camera);
    imm_vertex(.{hue_x0, hue_y0, 0}, .{0, 0});
    imm_vertex(.{hue_x1, hue_y0, 0}, .{1, 0});
    imm_vertex(.{hue_x1, hue_y1, 0}, .{1, 1});
    imm_vertex(.{hue_x0, hue_y0, 0}, .{0, 0});
    imm_vertex(.{hue_x0, hue_y1, 0}, .{0, 1});
    imm_vertex(.{hue_x1, hue_y1, 0}, .{1, 1});
    imm_flush();

    slider(*hue, hue_position, hue_size, loc=loc, id=1);
    color.x, color.y, color.z = hsv_to_rgb(hue, saturation, value);

    if state == {
        case .ACTIVE;
            assert(data.type == .SV);
            sv_cursor = mouse + data.sv.mouse_offset;
            clamp(*sv_cursor.x, sv_x0, sv_x1);
            clamp(*sv_cursor.y, sv_y0, sv_y1);

            saturation = (sv_cursor.x - sv_x0) / (sv_x1 - sv_x0);
            value = 1.0 - (sv_cursor.y - sv_y0) / (sv_y1 - sv_y0); // :ReversedValue
            
            color.x, color.y, color.z = hsv_to_rgb(hue, saturation, value);

            for [] Input_Event.{event_count, events.data} {
                if it.key == .MOUSE_LEFT_BUTTON && !it.down {
                    deactivate();
                    event_count = 0;
                    break;
                }
            }

        case .NO_ONE;
            sv_cursor_size := bar_width * 0.045;
            sv_cursor_position := Vector2.{
                sv_cursor.x - sv_cursor_size,
                sv_cursor.y - sv_cursor_size
            };

            cursor_selection_size := Vector2.{
                sv_cursor_size * 2,
                sv_cursor_size * 2
            };
            
            if inside(sv_cursor_position, cursor_selection_size, mouse) {
                for [] Input_Event.{event_count, events.data} {
                    if it.key == .MOUSE_LEFT_BUTTON && it.down {
                        activate(.{
                            type = .SV,
                            sv = .{
                                mouse_offset = sv_cursor - mouse,
                                hue = hue
                            }
                        });
                        break;
                    }
                }
            }
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


    glUseProgram(imm_saturation_value_shader);
    set_uniform("projection", imgui_to_camera);
    set_uniform("hue", hue);
    imm_vertex(.{sv_x0, sv_y0, 0}, .{0, 1});
    imm_vertex(.{sv_x1, sv_y0, 0}, .{1, 1});
    imm_vertex(.{sv_x1, sv_y1, 0}, .{1, 0});
    imm_vertex(.{sv_x0, sv_y0, 0}, .{0, 1});
    imm_vertex(.{sv_x1, sv_y1, 0}, .{1, 0});
    imm_vertex(.{sv_x0, sv_y1, 0}, .{0, 0});
    imm_flush();

    glUseProgram(imm_color_shader);
    set_uniform("projection", imgui_to_camera);
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
    using context.game_context.imgui_state;

    scope_widget(loc, id);

    font := *consolas;
    
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

    if button(">", right_button_position, button_size, loc=loc, 1) {
        member_index = (member_index + 1) % info.values.count;
    }
    
    assign_int(info.internal_type, val, info.values[member_index]);


    member_text := info.names[member_index];
    
    text_x := left_button_position.x - margin - text_length(member_text, font);
    text_y := position.y + size.y / 2 + font.ascender / 2;

    imgui_draw_text(member_text, round(Vector2.{text_x, text_y}), font, DULL_COLOR);
}


button :: (label: string, position: Vector2, size: Vector2, loc := #caller_location, id: u64 = 0) -> bool {
    using context.game_context;
    using context.game_context.imgui_state;

    state, data := scope_widget(loc, id);

    clicked := false;
    color := HIGHLIGHT_COLOR;

    if state == {
        case .ACTIVE;
            assert(data.type == .BUTTON);
            for [] Input_Event.{event_count, events.data} {
                if it.key == .MOUSE_LEFT_BUTTON && !it.down {
                    deactivate();
                    event_count = 0;
                    break;
                }
            }
            color = DULL_COLOR;
        case .NO_ONE;
            if inside(position, size, mouse) {
                for [] Input_Event.{event_count, events.data} {
                    if it.key == .MOUSE_LEFT_BUTTON && it.down {
                        activate(.{
                            type = .BUTTON
                        });
                        clicked = true;
                        break;
                    }
                }
            }
    }
    

    font := *consolas;

    width := floor(font.ascender * 0.05);

    glUseProgram(imm_color_shader);
    set_uniform("projection", imgui_to_camera);
    imm_quad(position, size, color);
    
    inner_position := Vector2.{position.x + width, position.y + width};
    inner_size     := Vector2.{size.x - width * 2, size.y - width * 2};
    imm_quad(inner_position, inner_size, BACKGROUND_COLOR);
    imm_flush();

    text_x := position.x + size.x / 2 - text_length(label, font) / 2;
    text_y := position.y + size.y / 2 + font.ascender / 2;
    imgui_draw_text(label, round(Vector2.{text_x, text_y}), font, color);

    return clicked;
}


STRING_ENTRY_MAX_COUNT :: 128;
string_entry :: (
    position: Vector2,
    size: Vector2,
    str: *[STRING_ENTRY_MAX_COUNT] u8,
    str_count: *int,
    loc := #caller_location,
    id: u64 = 0
) -> entered: bool {
    using context.game_context;
    using context.game_context.imgui_state;
    assert(str_count.* <= str.count);

    state, data := scope_widget(loc, id);

    font := *consolas;
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

    color := DULL_COLOR;
    entered := false;
    string_to_draw: string;
    // @TODO: CHECK THE WIDGET STATE AGAIN AFTER WE HANDLE INPUTS TO DETERMINE WHAT THESE VARIABLES SHOULD BE.
    // If we are active and become inactive, we should assume we can't touch "data" anymore".

    if state == {
        case .ACTIVE;
            assert(data.type == .STRING_ENTRY);

            mouse_outside := !inside(outer_position, outer_size, mouse);
            for [] Input_Event.{event_count, events.data} {
                if !it.down continue;

                if it.key == .ENTER || (mouse_outside && it.key == .MOUSE_LEFT_BUTTON) {
                    memcpy(str.data, data.string_entry.str.data, data.string_entry.str_count);
                    str_count.* = data.string_entry.str_count;
                    deactivate();
                    event_count = 0;
                    entered = true;
                    break;
                }

                if (#char " " <= it.key && it.key <= #char "~") && data.string_entry.str_count < data.string_entry.str.count {
                    data.string_entry.str[data.string_entry.str_count] = xx it.key;
                    data.string_entry.str_count += 1;
                    continue;
                }

                if it.key == .DELETE || it.key == .BACKSPACE {
                    if data.string_entry.str_count > 0 data.string_entry.str_count -= 1;
                    continue;
                }
            }

            color = HIGHLIGHT_COLOR;
            string_to_draw = .{data.string_entry.str_count, data.string_entry.str.data};

        case .NO_ONE;
            string_to_draw = .{str_count.*, str.data};
            if inside(outer_position, outer_size, mouse) {
                for [] Input_Event.{event_count, events.data} {
                    if it.down && it.key == .MOUSE_LEFT_BUTTON {    
                        data: Active_Widget_Data;
                        data.type = .STRING_ENTRY;
                        memcpy(data.string_entry.str.data, str.data, str_count.*);
                        data.string_entry.str_count = str_count.*;
                        activate(data);
                        break;
                    }
                }
            }
    }


    glUseProgram(imm_color_shader);
    set_uniform("projection", imgui_to_camera);
    imm_quad(outer_position, outer_size, color);
    imm_quad(inner_position, inner_size, BACKGROUND_COLOR);
    imm_flush();
    
    // @TODO: Push a new scissor, or find some way to cut off the text we draw.
    imgui_draw_text(string_to_draw, text_position, font, color);
    

    return entered;
}



imgui_for_value :: (val: *$T, position: Vector2, field_size: Vector2, loc := #caller_location, id: u64 = 0) {
    imgui_for_value(val, type_info(T), position, field_size, loc, id);
}


imgui_for_value :: (val: *void, info: *Type_Info, position: Vector2, field_size: Vector2, loc := #caller_location, id: u64 = 0) -> end_y: float {
    using context.game_context;
    using context.game_context.imgui_state;
    scope_widget(loc, id);

    font := *consolas;
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
                if contains(it.notes, "NoEditor") continue; // @Speed!

                if it.type.type == {
                    case .INTEGER; #through;
                    case .FLOAT; #through;
                    case .STRING; #through;
                    case .ARRAY;
                        // @TODO: Implement editors for these
                        continue;
                }
                
                label_x := position.x + margin;
                label_y := y + field_size.y / 2 + font.ascender / 2;

                value_x := imgui_draw_text(it.name, round(Vector2.{label_x, label_y}), font, HIGHLIGHT_COLOR);
                value_y := y;
                
                value_position := Vector2.{value_x, value_y};
                value_size := Vector2.{
                    position.x + field_size.x - value_x,
                    field_size.y
                };



                if it.type.type == .STRUCT {
                    value_position.y += field_size.y;
                    value_position.x += indent;
                    value_size.x -= indent;
                }

                if it.type == type_info(Vector4) && contains(it.notes, "Color") {
                    y = color_selector(val + it.offset_in_bytes, value_position, value_size, loc, xx it_index);
                } else {
                    new_y := imgui_for_value(val + it.offset_in_bytes, it.type, value_position, value_size, loc, xx it_index);
                    if new_y < y + field_size.y y = field_size.y;
                    else y = new_y;
                }
            }
            return y;
        case .BOOL;
            toggle(val, position, field_size, loc);
            return position.y + field_size.y;
        case .ENUM;
            enum_info := cast(*Type_Info_Enum, info);
            enum_selector(val, enum_info, position, field_size, loc, 0);
            return position.y + field_size.y;
        case .INTEGER; #through;
        case .FLOAT; #through;
        case .STRING; #through;
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
    using context.game_context.imgui_state;
    glEnable(GL_SCISSOR_TEST);
}


vertical_scroll_end :: (scroll: *float, end_height: float) {
    glDisable(GL_SCISSOR_TEST);
}
*/
