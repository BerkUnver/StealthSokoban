Rect :: struct {
    x, y, w, h: float;
    #place x;
    position: Vector2;
    #place w;
    size: Vector2;
}


make_rect :: inline (position: Vector2, size: Vector2) -> Rect {
    return .{position=position, size=size};
}


inside :: (rect: Rect, point: Vector2) -> bool {
    return point.x >= rect.x
        && point.y >= rect.y
        && point.x <= rect.x + rect.w
        && point.y <= rect.y + rect.h;
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

    imm_quad(button_rect, SELECTED_COLOR);
    imm_quad(make_rect(center - INNER_SIZE / 2, INNER_SIZE), UNSELECTED_COLOR);

    if selected.* {
        imm_quad(make_rect(center - INMOST_SIZE / 2, INMOST_SIZE), SELECTED_COLOR);
    }
}
