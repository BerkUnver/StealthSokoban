Editor_Mode :: enum {
    SELECTION;
    EXTRUSION;
}

Editor :: struct {
    mode: Editor_Mode;
    selected_block: *Block;
}


editor_update :: (using level: *Level, editor: *Editor, mouse_x: float, mouse_y: float, event: Input_Event) {
    
    if event.down && event.key == xx #char "E" {
        editor.mode = .EXTRUSION; 
    } else if event.down && event.key == xx #char "S" {
        editor.mode = .SELECTION;
    } else {
        if editor.mode == {
            case .SELECTION;
                if event.key != .MOUSE_LEFT_BUTTON || !event.down return;
                
                Raycast_Data :: struct {
                    block: *Block;
                    col: *Collision;
                }
                data := Raycast_Data.{col=*collision};
                raycast_visitor :: (position: Vector3, using data: *Raycast_Data) -> bool {
                    coord := to_vector3i(position) - col.position;
                    if !inside_positive_bounding_box(coord, col.size) return false;

                    index := convert_3d_coordinate_to_index(coord, col.size);

                    filled := col.filled[index];
                    if !filled return false;
                    block = filled;
                    return true;
                }

                camera_to_world := inverse(camera_matrix);
                camera_ray_end := Vector4.{mouse_x, mouse_y, 1, 1}; // 1 for the OpenGL far plane
                ray_end_4 := (inverse(camera_matrix) * camera_ray_end);
                ray_end := ray_end_4.xyz / ray_end_4.w;
                
                raycast(camera_position, ray_end, raycast_visitor, *data);

                editor.selected_block = data.block;
        }
    }
}

