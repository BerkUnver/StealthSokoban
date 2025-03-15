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
    selected: enum {
        SV;
        HUE;
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
        hue: struct {
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
    
    sv_position := head;
    sv_size := Vector2.{bar_width, bar_width};

    x0 := sv_position.x;
    y0 := sv_position.y;
    x1 := sv_position.x + sv_size.x;
    y1 := sv_position.y + sv_size.y;

    head.y += sv_size.y + margin;

    sample_position := head;
    sample_size := Vector2.{bar_width, bar_height};

    
    // Store what we expect the values to be, then reassign them
    // when we check input if they change.
    hue, saturation, value := rgb_to_hsv(color.x, color.y, color.z);
    sv_cursor: Vector2;
    hue_cursor_x := hue_position.x + hue_size.x * hue;
    sv_cursor = Vector2.{
        lerp(x0, x1, saturation),
        lerp(y0, y1, value)
    };
        

    if active_widget_exists && loc == active_widget_loc {
        if loc == active_widget_loc {
            if #complete active_widget_state.selected == {
                case .SV;
                    sv_cursor = mouse + active_widget_state.sv.mouse_offset;
                    clamp(*sv_cursor.x, x0, x1);
                    clamp(*sv_cursor.y, y0, y1);

                    saturation = (sv_cursor.x - x0) / (x1 - x0);
                    value = (sv_cursor.y - y0) / (y1 - y0);
                    hue = active_widget_state.sv.hue;
                    hue_cursor_x = hue_position.x + hue_size.x * hue;
                    
                    color.x, color.y, color.z = hsv_to_rgb(hue, saturation, value);

                    for [] Input_Event.{event_count, events.data} {
                        if it.key == .MOUSE_LEFT_BUTTON && !it.down {
                            active_widget_exists = false;
                            break;
                        }
                    }

                case .HUE;
                    hue_cursor_x = mouse.x + active_widget_state.hue.mouse_offset_x;
                    // Hue cannot be equal to 1 so we clamp the cursor slightly lower.
                    clamp(*hue_cursor_x, hue_position.x, hue_position.x + hue_size.x - 0.0001);
                    hue = (hue_cursor_x - hue_position.x) / hue_size.x;

                    color.x, color.y, color.z = hsv_to_rgb(hue, saturation, value);
                    
                    for [] Input_Event.{event_count, events.data} {
                        if it.key == .MOUSE_LEFT_BUTTON && !it.down {
                            active_widget_exists = false;
                            break;
                        }
                    }
            };
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
        } else {
            hue_cursor_width := bar_width * 0.03;
            hue_cursor_position := Vector2.{
                hue_cursor_x - hue_cursor_width / 2,
                hue_position.y
            };
            hue_cursor_size := Vector2.{
                hue_cursor_width,
                hue_size.y
            };
            
            if inside(hue_cursor_position, hue_cursor_size, mouse) {
                for [] Input_Event.{event_count, events.data} {
                    if it.key == .MOUSE_LEFT_BUTTON && it.down {
                        active_widget_exists = true;
                        active_widget_loc = loc;
                        active_widget_state = .{
                            selected = .HUE,
                            hue = .{mouse_offset_x = hue_cursor_x - mouse.x}
                        };
                        break;
                    }
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

    hue_cursor_bar_width := bar_width * 0.01;
    hue_cursor_bar_position := Vector2.{
        hue_cursor_x - hue_cursor_bar_width / 2,
        hue_position.y
    };

    hue_cursor_bar_size := Vector2.{
        hue_cursor_bar_width,
        hue_size.y
    };


    glUseProgram(imm_saturation_value_shader);
    set_uniform("projection", imgui_to_camera);
    set_uniform("hue", hue);
    imm_quad_with_uvs(sv_position, sv_size);
    imm_flush();

    glUseProgram(imm_hue_shader);
    set_uniform("projection", imgui_to_camera);
    imm_quad_with_uvs(hue_position, hue_size);
    imm_flush();

    glUseProgram(imm_color_shader);
    set_uniform("projection", imgui_to_camera);
    imm_quad(sample_position, sample_size, color.*);
    imm_quad(sv_cursor_hbar_position, sv_cursor_hbar_size, .{1, 1, 1, 1});
    imm_quad(sv_cursor_vbar_position, sv_cursor_vbar_size, .{1, 1, 1, 1});
    imm_quad(hue_cursor_bar_position, hue_cursor_bar_size, .{1, 1, 1, 1});
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

