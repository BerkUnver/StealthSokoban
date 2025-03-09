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
    events: [MAX_INPUT_EVENTS_PER_TICK] Key;
    event_count: int;
    mouse: Vector2;
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
    set_uniform("projection", imgui_state.imgui_to_camera);

    imm_quad(outline_outer_position, outline_outer_size, OUTLINE_COLOR);
    imm_quad(outline_inner_position, outline_inner_size, UNSELECTED_COLOR);


    if inside(outline_outer_position, outline_outer_size, mouse) {
        for 0..event_count-1 {    
            event := events[it];
            if event == .MOUSE_LEFT_BUTTON {
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


/*
imm_button :: (selected: *bool, rect: Rect) {
    using context.game_context.imgui_state;

    SIZE :: Vector2.{20, 20};
    INNER_SIZE :: Vector2.{16, 16};

    INMOST_SIZE :: Vector2.{12, 12};
    
    UNSELECTED_COLOR :: Vector4.{0, 0, 0, 1};
    SELECTED_COLOR :: Vector4.{1, 1, 1, 1};
    
    center := rect.position + rect.size / 2;
    button_rect := make_rect(center - SIZE / 2, SIZE);
    
    if inside(button_rect, mouse) {
        for 0..event_count-1 {    
            event := events[it];
            if event == .MOUSE_LEFT_BUTTON {
                selected.* = !selected.*;
            }
        }
    }

    imm_quad(button_rect.position, button_rect.size, SELECTED_COLOR);
    imm_quad(center - INNER_SIZE / 2, INNER_SIZE, UNSELECTED_COLOR);

    if selected.* {
        imm_quad(center - INMOST_SIZE / 2, INMOST_SIZE, SELECTED_COLOR);
    }
}
*/


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

