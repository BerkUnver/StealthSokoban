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
    events: [MAX_INPUT_EVENTS_PER_TICK] Input_Event;
    event_count: int;
    mouse: Vector2;
    
    active_widget_exists: bool; 
    active_widget_loc: Source_Code_Location;
    active_widget_id: u64;
    active_widget_state: Active_Widget_State;

    // Here is how widget ids work for now.
    // We treat the id as 8 u8s. Whenever you recurse into a widget, pass the id
    // as (old_id << 8) + new_id. That way, you can recurse up to 8 times on
    // imgui widget code while still maintaining unique ids for each widget. 
    // This, of course, has the limitation that you can only can recurse 8 times,
    // and each widget can only have 256 sub-widgets at most.

    // We also have to make sure the first old_id was not zero because the top of
    // the "stack" is represented by zeroed-out bits. This is kind of unintitive.
    // i.e 0x_00_01_00_09_af_c6_04_12
    //           ^ Top of the stack, 7 widgets have been pushed so far.

    // The correct thing to do in the long term would just to be to have a stack of
    // ints, and whenever you start drawing a widget, you push new ints to the stack.
    // I am doing this because it is simpler for now.

    //          -berk, 2025 - 3 - 14
}

sub_id :: (id: u64, new_id: u64) -> u64 {
    assert((cast(u64, 1) << (63 - 8)) > id);
    assert((cast(u64, 1) << 8) > new_id);
    return (id << 8) + new_id;
}


HIGHLIGHT_COLOR :: Vector4.{1, 1, 1, 1};
DULL_COLOR :: Vector4.{0.6, 0.6, 0.6, 1};
BACKGROUND_COLOR :: Vector4.{0, 0, 0, 1};

is_active :: (loc: Source_Code_Location, id: u64) -> bool {
    using context.game_context.imgui_state;
    assert(active_widget_exists);
    return active_widget_loc.fully_pathed_filename == loc.fully_pathed_filename
        && active_widget_loc.line_number           == loc.line_number
        && active_widget_loc.character_number      == loc.character_number
        && active_widget_id                        == id;
}


Active_Widget_State :: struct {
    selected: enum {
        SV;
        SLIDER;
        BUTTON;
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
    zoom_in_matrix._22 /= INNER_WINDOW_H / 2;
    imgui_to_camera = make_translation_matrix4(.{-1, -1, 0}) * zoom_in_matrix;

    zoom_out_matrix := Matrix4_Identity;
    zoom_out_matrix._11 *= INNER_WINDOW_W / 2;
    zoom_out_matrix._22 *= INNER_WINDOW_H / 2;
    camera_to_imgui = zoom_out_matrix * make_translation_matrix4(.{1, 1, 0});

    return imgui_state;
}


/*
toggle :: (label: string, selected: *bool, position: Vector2, size: Vector2) {
    using context.game_context;
    using context.game_context.imgui_state;
    
    font := *consolas;

    text_x: float = round(position.x + font.ascender / 2);
    text_y: float = round(position.y + size.y / 2 - font.ascender / 2);
    draw_text(label, .{text_x, text_y}, font, HIGHLIGHT_COLOR);

    outline_outer_width := round(font.ascender * 1.5);
    outline_outer_size := Vector2.{outline_outer_width, outline_outer_width};

    outline_inner_width := round(font.ascender * 1.3);
    outline_inner_size := Vector2.{outline_inner_width, outline_inner_width};

    toggle_center_x := position.x + size.x - size.y / 2 - font.ascender / 2;
    toggle_center_y := position.y + size.y / 2;
    toggle_center := Vector2.{toggle_center_x, toggle_center_y};

    outline_outer_position := round(toggle_center - outline_outer_size / 2);
    outline_inner_position := round(toggle_center - outline_inner_size / 2);

    glUseProgram(imm_color_shader);
    set_uniform("projection", imgui_to_camera);

    imm_quad(outline_outer_position, outline_outer_size, HIGHLIGHT_COLOR);
    imm_quad(outline_inner_position, outline_inner_size, BACKGROUND_COLOR);


    if !active_widget_exists && inside(outline_outer_position, outline_outer_size, mouse) {
        for [] Input_Event.{event_count, events.data} {
            if it.key == .MOUSE_LEFT_BUTTON && it.down {
                selected.* = !selected.*;
            }
        }
    }

    if selected.* {
        selected_width := round(font.ascender * 0.9);
        selected_size := Vector2.{selected_width, selected_width};
        selected_position := round(toggle_center - selected_size / 2);
        imm_quad(selected_position, selected_size, HIGHLIGHT_COLOR);
    }

    imm_flush();
} */


toggle :: (val: *bool, position: Vector2, size: Vector2) {
    using context.game_context;
    using context.game_context.imgui_state;

    font := *consolas;
    
    outline_outer_width := round(font.ascender * 1.5);
    outline_outer_size := Vector2.{outline_outer_width, outline_outer_width};

    outline_inner_width := round(font.ascender * 1.3);
    outline_inner_size := Vector2.{outline_inner_width, outline_inner_width};
    
    toggle_center := position + size / 2;

    outline_outer_position := round(toggle_center - outline_outer_size / 2);
    outline_inner_position := round(toggle_center - outline_inner_size / 2);

    if !active_widget_exists && inside(outline_outer_position, outline_outer_size, mouse) {
        for [] Input_Event.{event_count, events.data} {
            if it.key == .MOUSE_LEFT_BUTTON && it.down {
                val.* = !val.*;
            }
        }
    }

    glUseProgram(imm_color_shader);
    set_uniform("projection", imgui_to_camera);

    imm_quad(outline_outer_position, outline_outer_size, HIGHLIGHT_COLOR);
    imm_quad(outline_inner_position, outline_inner_size, BACKGROUND_COLOR);
    imm_flush();

    if val.* {
        selected_width := round(font.ascender * 0.9);
        selected_size := Vector2.{selected_width, selected_width};
        selected_position := round(toggle_center - selected_size / 2);
        imm_quad(selected_position, selected_size, HIGHLIGHT_COLOR);
    }

    imm_flush();
}


slider :: (value: *float, position: Vector2, size: Vector2, strictly_less_than_1 := true, loc := #caller_location, id: u64 = 1) {
    using context.game_context;
    using context.game_context.imgui_state;

    cursor_x := position.x + size.x * value.*;
    if active_widget_exists {
        if is_active(loc, id) {
            using active_widget_state;
            assert(selected == .SLIDER);

            end_x := position.x + size.x;

            epsilon := 0.0;
            if strictly_less_than_1 epsilon = 0.001;

            cursor_x = clamp(mouse.x + active_widget_state.slider.mouse_offset_x, position.x, end_x - epsilon);
            value.* = (cursor_x - position.x) / (end_x - position.x);

            for [] Input_Event.{event_count, events.data} {
                if it.key == .MOUSE_LEFT_BUTTON && !it.down {
                    active_widget_exists = false;
                    event_count = 0;
                    // We clear the input events because this widget consumed it.
                    // We don't want another widget acting on the input event that deactivated
                    // this widget.
                }
            }
        }
    } else {
        cursor_width := size.x * 0.01;
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
                    active_widget_exists = true;
                    active_widget_loc = loc;
                    active_widget_id = id;
                    active_widget_state = .{
                        selected = .SLIDER,
                        slider = .{mouse_offset_x = cursor_x - mouse.x}
                    };
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


color_selector :: (color: *Vector4, position: Vector2, size: Vector2, bar_height: float, loc := #caller_location, id: u64 = 1) {
    using context.game_context;
    using context.game_context.imgui_state;


    margin := bar_height * 0.2;

    head := position;
    head.x += margin;

    bar_width := size.x - 2 * margin;
    
    alpha_position := head;
    alpha_size := Vector2.{bar_width, bar_height};
    
    head.y += bar_height + margin;

    hue_position := head;
    hue_size := Vector2.{bar_width, bar_height};

    head.y += bar_height + margin;
     
    // sv: saturation and value
    
    sv_position := head;
    sv_size := Vector2.{bar_width, bar_width};

    sv_x0 := sv_position.x;
    sv_y0 := sv_position.y;
    sv_x1 := sv_position.x + sv_size.x;
    sv_y1 := sv_position.y + sv_size.y;

    head.y += sv_size.y + margin;

    sample_position := head;
    sample_size := Vector2.{bar_width, bar_height};

    
    // Store what we expect the values to be, then reassign them
    // when we check input if they change.
    hue, saturation, value := rgb_to_hsv(color.x, color.y, color.z);
    if active_widget_exists && is_active(loc, id) {
        // @Hack make sure we use the backed-up hue if the
        // saturation-value box is selected.
        assert(active_widget_state.selected == .SV);
        hue = active_widget_state.sv.hue;
    }

    sv_cursor := Vector2.{
        lerp(sv_x0, sv_x1, saturation),
        lerp(sv_y0, sv_y1, value)
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


    slider(*color.w, alpha_position, alpha_size, loc=loc, id=sub_id(id, 0));

    glUseProgram(imm_hue_shader);
    set_uniform("projection", imgui_to_camera);
    imm_quad_with_uvs(hue_position, hue_size);
    imm_flush();

    slider(*hue, hue_position, hue_size, loc=loc, id=sub_id(id, 1));
    color.x, color.y, color.z = hsv_to_rgb(hue, saturation, value);

    if active_widget_exists {
        if is_active(loc, id) {
            assert(active_widget_state.selected == .SV);
            sv_cursor = mouse + active_widget_state.sv.mouse_offset;
            clamp(*sv_cursor.x, sv_x0, sv_x1);
            clamp(*sv_cursor.y, sv_y0, sv_y1);

            saturation = (sv_cursor.x - sv_x0) / (sv_x1 - sv_x0);
            value = (sv_cursor.y - sv_y0) / (sv_y1 - sv_y0);
            
            color.x, color.y, color.z = hsv_to_rgb(hue, saturation, value);

            for [] Input_Event.{event_count, events.data} {
                if it.key == .MOUSE_LEFT_BUTTON && !it.down {
                    active_widget_exists = false;
                    event_count = 0;
                    break;
                }
            }
        }
    } else {
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
                    active_widget_exists = true;
                    active_widget_id = id;
                    active_widget_loc = loc;
                    active_widget_state = .{
                        selected = .SV,
                        sv = .{
                            mouse_offset = sv_cursor - mouse,
                            hue = hue
                        }
                    };
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
    imm_quad_with_uvs(sv_position, sv_size);
    imm_flush();

    glUseProgram(imm_color_shader);
    set_uniform("projection", imgui_to_camera);
    imm_quad(sample_position, sample_size, color.*);
    imm_quad(sv_cursor_hbar_position, sv_cursor_hbar_size, HIGHLIGHT_COLOR);
    imm_quad(sv_cursor_vbar_position, sv_cursor_vbar_size, HIGHLIGHT_COLOR);
    imm_flush();
}


/*
// Does this need to be a polymorph?
enum_selector :: (label: string, val: *$T, position: Vector2, size: Vector2, loc := #caller_location) {
    INFO :: type_info(T);
    #run {
        assert(type_of(INFO) == *Type_Info_Enum);
        assert(INFO.values.count != 0);
    }

    using context.game_context;
    using context.game_context.imgui_state;
    
    // @Copypaste from toggle
    font := *consolas;
    label_x: float = round(position.x + font.ascender / 2);
    label_y: float = round(position.y + size.y / 2 - font.ascender / 2);
    label_end_x := draw_text(label, .{label_x, label_y}, font, HIGHLIGHT_COLOR);
    
    margin := font.ascender * 0.3;
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

    member_index := -1;
    for INFO.values {
        if it == xx val.* {
            member_index = it_index;
            break;
        }
    }
    if member_index == -1 member_index = 0;
    // Default to the first value if for some reason the enum got set to some other value.

    if button("<",  left_button_position, button_size, loc=loc, id=0) {
        member_index = (member_index - 1 + INFO.values.count) % INFO.values.count;
    }

    if button(">", right_button_position, button_size, loc=loc, id=1) {
        member_index = (member_index + 1) % INFO.values.count;
    }

    val.* = xx INFO.values[member_index];

    member_text := INFO.names[member_index];

    member_center_x := (label_end_x + left_button_position.x) / 2;
    text_x: float = round(member_center_x - text_length(member_text, font) / 2);
    text_y: float = round(position.y + size.y / 2 - font.ascender / 2);

    draw_text(member_text, .{text_x, text_y}, font, DULL_COLOR);
}
*/



// Does this need to be a polymorph?
enum_selector :: (val: *$T, position: Vector2, size: Vector2, loc := #caller_location, id: u64 = 1) {
    INFO :: type_info(T);
    #run {
        assert(type_of(INFO) == *Type_Info_Enum);
        assert(INFO.values.count != 0);
    }

    using context.game_context;
    using context.game_context.imgui_state;

    font := *consolas;
    
    margin := font.ascender * 0.3;
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

    member_index := -1;
    for INFO.values {
        if it == xx val.* {
            member_index = it_index;
            break;
        }
    }
    if member_index == -1 member_index = 0;
    // Default to the first value if for some reason the enum got set to some other value.

    if button("<",  left_button_position, button_size, loc=loc, id=sub_id(id, 0)) {
        member_index = (member_index - 1 + INFO.values.count) % INFO.values.count;
    }

    if button(">", right_button_position, button_size, loc=loc, id=sub_id(id, 1)) {
        member_index = (member_index + 1) % INFO.values.count;
    }

    val.* = xx INFO.values[member_index];

    member_text := INFO.names[member_index];

    member_center_x := (position.x + left_button_position.x) / 2;
    text_x: float = round(member_center_x - text_length(member_text, font) / 2);
    text_y: float = round(position.y + size.y / 2 - font.ascender / 2);

    draw_text(member_text, .{text_x, text_y}, font, DULL_COLOR);
}


button :: (label: string, position: Vector2, size: Vector2, loc := #caller_location, id: u64 = 1) -> bool {
    using context.game_context;
    using context.game_context.imgui_state;
    
    clicked := false;
    color := HIGHLIGHT_COLOR;

    if active_widget_exists {
        if is_active(loc, id) {
            for [] Input_Event.{event_count, events.data} {
                if it.key == .MOUSE_LEFT_BUTTON && !it.down {
                    active_widget_exists = false;
                    event_count = 0;
                    break;
                }
            }
            color = DULL_COLOR;
        }
    } else {
        if inside(position, size, mouse) {
            for [] Input_Event.{event_count, events.data} {
                if it.key == .MOUSE_LEFT_BUTTON && it.down {
                    active_widget_exists = true;
                    active_widget_loc = loc;
                    active_widget_id = id;
                    active_widget_state = .{
                        selected = .BUTTON
                    };
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

    text_x: float = round(position.x + size.x / 2 - text_length(label, font) / 2);
    text_y: float = round(position.y + size.y / 2 - font.ascender / 2);
    draw_text(label, .{text_x, text_y}, font, color);

    return clicked;
}


get_color_selector_height :: (width: float, bar_height: float) -> float {
    margin := bar_height * 0.2;

    saturation_value_selector_height := width - margin * 2;
    return margin + bar_height + margin + saturation_value_selector_height + margin + bar_height + margin + bar_height + margin;
}


imgui_for_value :: (val: *$T, position: Vector2, size: Vector2, loc := #caller_location, id: u64 = 1) {
    INFO :: type_info(T);
    #if INFO.type == {
        case .STRUCT;
            greatest_offset := -1;
            for * info.members {
                // The members visible in the editor are strictly a subset of what we can 
                // serialize... for now.
                if !can_serialize_member(it, greatest_offset) continue;
                if contains(it.notes, "NoEditor") continue;
            }
        case .BOOL;
            toggle(val, position, size);
        case .ENUM;
            enum_selector(val, position, size, loc, id);

        case .INTEGER;
        case .FLOAT;
        case .STRING;
        case .ARRAY;
            // @TODO: Implement editors for these
            #assert false;

        case;
            // These should never be exposed to the editor.
            #assert false;
    }
}
