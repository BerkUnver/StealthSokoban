inside :: (position: Vector2, size: Vector2, point: Vector2) -> bool {
    return point.x >= position.x
        && point.y >= position.y
        && point.x <= position.x + size.x
        && point.y <= position.y + size.y;
}


Imgui_State :: struct {
    imgui_to_camera: Matrix4;
    camera_to_imgui: Matrix4;
    test_selected: bool;
    test_color := Vector4.{0.8, 0.5, 0.2, 1};
    events: [MAX_INPUT_EVENTS_PER_TICK] Input_Event;
    event_count: int;
    mouse: Vector2;
    
    active_widget_exists: bool; 
    active_widget_loc: Source_Code_Location;
    active_widget_state: Active_Widget_State;
}


Active_Widget_State :: struct {
    mouse_offset: Vector2;
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


button :: (label: string, selected: *bool, font: *Font, position: Vector2, size: Vector2) {
    using context.game_context;
    using context.game_context.imgui_state;

    glUseProgram(imm_text_shader);

    OUTLINE_COLOR :: Vector4.{1, 1, 1, 1};
    SELECTED_COLOR :: Vector4.{1, 1, 1, 1};
    UNSELECTED_COLOR :: Vector4.{0, 0, 0, 1};

    font := *consolas;

    text_x: float = round(position.x + font.ascender / 2);
    text_y: float = round(position.y + size.y / 2 - font.ascender / 2);
    draw_text(label, .{text_x, text_y}, font);

    outline_outer_width := round(font.ascender * 1.5);
    outline_outer_size := Vector2.{outline_outer_width, outline_outer_width};

    outline_inner_width := round(font.ascender * 1.2);
    outline_inner_size := Vector2.{outline_inner_width, outline_inner_width};

    button_center_x := position.x + size.x - size.y / 2 - font.ascender / 2;
    button_center_y := position.y + size.y / 2;
    button_center := Vector2.{button_center_x, button_center_y};

    outline_outer_position := round(button_center - outline_outer_size / 2);
    outline_inner_position := round(button_center - outline_inner_size / 2);

    glUseProgram(imm_color_shader);
    set_uniform("projection", imgui_to_camera);

    imm_quad(outline_outer_position, outline_outer_size, OUTLINE_COLOR);
    imm_quad(outline_inner_position, outline_inner_size, UNSELECTED_COLOR);


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
        selected_position := round(button_center - selected_size / 2);
        imm_quad(selected_position, selected_size, SELECTED_COLOR);
    }
    imm_flush();
}


color_selector :: (color: *Vector4, position: Vector2, size: Vector2, bar_height: float, loc := #caller_location) {
    using context.game_context;
    using context.game_context.imgui_state;


    margin := bar_height * 0.2;

    head := position;
    head.x += margin;

    bar_width := size.x - 2 * margin;
    
    hue_position := head;
    hue_size := Vector2.{bar_width, bar_height};

    head.y += bar_height + margin;
     
    // sv: saturation and value

    sv_size := Vector2.{bar_width, bar_width};

    x0 := head.x;
    y0 := head.y;
    x1 := head.x + sv_size.x;
    y1 := head.y + sv_size.y;

    head.y += sv_size.y + margin;

    sample_position := head;
    sample_size := Vector2.{bar_width, bar_height};

    
    cursor: Vector2;
    hue: float;

    if active_widget_exists && loc == active_widget_loc {
        if loc == active_widget_loc {
            cursor = mouse + active_widget_state.mouse_offset;
            clamp(*cursor.x, x0, x1);
            clamp(*cursor.y, y0, y1);

            saturation := (cursor.x - x0) / (x1 - x0);
            value := (cursor.y - y0) / (y1 - y0);
            
            hue = rgb_to_hsv(color.x, color.y, color.z);
            r, g, b := hsv_to_rgb(hue, saturation, value);

            color.x = r;
            color.y = g;
            color.z = b;

            for [] Input_Event.{event_count, events.data} {
                if it.key == .MOUSE_LEFT_BUTTON && !it.down {
                    active_widget_exists = false;
                    break;
                }
            }
        }
    } else {
        saturation, value: float;
        hue, saturation, value = rgb_to_hsv(color.x, color.y, color.z);

        cursor_x := lerp(x0, x1, saturation);
        cursor_y := lerp(y0, y1, value);
        cursor = Vector2.{cursor_x, cursor_y};
        
        cursor_selection_radius := bar_width * 0.045;
        cursor_selection_position := Vector2.{
            cursor.x - cursor_selection_radius,
            cursor.y - cursor_selection_radius
        };
        cursor_selection_size := Vector2.{
            cursor_selection_radius * 2,
            cursor_selection_radius * 2
        };

        if inside(cursor_selection_position, cursor_selection_size, mouse) {
            for [] Input_Event.{event_count, events.data} {
                if it.key == .MOUSE_LEFT_BUTTON && it.down {
                    active_widget_exists = true;
                    active_widget_loc = loc;
                    active_widget_state = .{
                        mouse_offset = cursor - mouse
                    };
                    break;
                }
            }
        }
    }


    cursor_offset_big := bar_width * 0.02;
    cursor_offset_small := bar_width * 0.005;

    cursor_hbar_position := Vector2.{
        cursor.x - cursor_offset_small,
        cursor.y - cursor_offset_big,
    };

    cursor_hbar_size := Vector2.{
        cursor_offset_small * 2,
        cursor_offset_big * 2,
    };

    
    cursor_vbar_position := Vector2.{
        cursor.x - cursor_offset_big,
        cursor.y - cursor_offset_small,
    };

    cursor_vbar_size := Vector2.{
        cursor_offset_big * 2,
        cursor_offset_small * 2,
    };



    glUseProgram(imm_saturation_value_shader);
    set_uniform("projection", imgui_to_camera);
    set_uniform("hue", hue);
    imm_vertex(.{x0, y0, 0}, .{0, 0});
    imm_vertex(.{x1, y0, 0}, .{1, 0});
    imm_vertex(.{x1, y1, 0}, .{1, 1});
    imm_vertex(.{x0, y0, 0}, .{0, 0});
    imm_vertex(.{x0, y1, 0}, .{0, 1});
    imm_vertex(.{x1, y1, 0}, .{1, 1});
    imm_flush();


    glUseProgram(imm_color_shader);
    set_uniform("projection", imgui_to_camera);
    imm_quad(hue_position, hue_size, color.*);
    imm_quad(sample_position, sample_size, color.*);
    imm_quad(cursor_hbar_position, cursor_hbar_size, .{1, 1, 1, 1});
    imm_quad(cursor_vbar_position, cursor_vbar_size, .{1, 1, 1, 1});
    imm_flush();
}


get_color_selector_height :: (width: float, bar_height: float) -> float {
    margin := bar_height * 0.2;

    saturation_value_selector_height := width - margin * 2;
    return margin + bar_height + margin + saturation_value_selector_height + margin + bar_height + margin + bar_height + margin;
}


draw_text :: (str: string, position: Vector2, font: *Font) {
    using context.game_context;

    glUseProgram(imm_text_shader);

    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, font.bitmap);
    
    set_uniform("projection", imgui_state.imgui_to_camera);
    set_uniform("bitmap", cast(s32, 0));
    
    x := position.x;
    y := position.y;

    COLOR :: Vector4.{1,1,1,1};

    for str {
        if it == #char " " { // ASCII 32
            x += font.space_advance;
        } else {
            assert(VALID_ASCII_START <= it && it <= VALID_ASCII_END);
            using glyph := font.glyphs[it - VALID_ASCII_START];
            x0 := x + bearing.x;
            y0 := y + bearing.y;
            x1 := x0 + size.x;
            y1 := y0 + size.y;

            imm_vertex(.{x0, y0, 0}, .{uv_x0, uv_y0}, COLOR);
            imm_vertex(.{x1, y0, 0}, .{uv_x1, uv_y0}, COLOR);
            imm_vertex(.{x1, y1, 0}, .{uv_x1, uv_y1}, COLOR);

            imm_vertex(.{x0, y0, 0}, .{uv_x0, uv_y0}, COLOR);
            imm_vertex(.{x1, y1, 0}, .{uv_x1, uv_y1}, COLOR);
            imm_vertex(.{x0, y1, 0}, .{uv_x0, uv_y1}, COLOR);

            x += advance;
        }
    }

    imm_flush();
}

