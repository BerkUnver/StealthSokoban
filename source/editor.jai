Editor_Mode :: enum {
    SELECTION;
    EXTRUSION;
}

Editor :: struct {
    mode: Editor_Mode;
    selected_block: *Block; // This should be valid even if we are not in the selection mode.
}


editor_update :: (using level: *Level, editor: *Editor, mouse_x: float, mouse_y: float, event: Input_Event) {
    
    // You hold down keys to enter different modes. Your default mode is selection.
    if event.key == xx #char "E" {
        if event.down editor.mode = .EXTRUSION;
        else if editor.mode == .EXTRUSION editor.mode = .SELECTION;
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
                    collision_coord := to_vector3i(position) - col.position;
                    if !inside_positive_bounding_box(collision_coord, col.size) return false;

                    index := convert_3d_coordinate_to_index(collision_coord, col.size);

                    filled := col.filled[index];
                    if !filled return false;
                    block = filled;
                    return true;
                }

                ray_end := multiply_homogeneous(inverse(camera_matrix), .{mouse_x, mouse_y, 1});
                raycast(camera_position, ray_end, raycast_visitor, *data);

                editor.selected_block = data.block;

            case .EXTRUSION;
                if event.key != .MOUSE_LEFT_BUTTON || !event.down return;

                Raycast_Data :: struct {
                    previous_coord_exists: bool;
                    previous_coord: Vector3i;
                    collided_block: *Block;
                    col: *Collision;
                }

                raycast_visitor :: (position: Vector3, using data: *Raycast_Data) -> bool {
                    coord := to_vector3i(position);
                    collision_coord := coord - col.position;

                    if !inside_positive_bounding_box(collision_coord, col.size) return false;

                    index := convert_3d_coordinate_to_index(collision_coord, col.size);
                    filled := col.filled[index];
                    if !filled {
                        previous_coord_exists = true;
                        previous_coord = coord;
                        return false;
                    } else {
                        collided_block = filled;
                        return true;
                    }
                }
                
                data := Raycast_Data.{col=*collision};
                ray_end := multiply_homogeneous(inverse(camera_matrix), .{mouse_x, mouse_y, 1});
                raycast(camera_position, ray_end, raycast_visitor, *data);
                
                block := data.collided_block;
                if block && data.previous_coord_exists {
                    block_coord := data.previous_coord - block.position;

                    if inside_positive_bounding_box(block_coord, block.size) {
                        block_index := convert_3d_coordinate_to_index(block_coord, block.size);
                        block.filled[block_index] = true;

                        collision_coord := data.previous_coord - collision.position;
                        assert(inside_positive_bounding_box(collision_coord, collision.size));

                        collision_index := convert_3d_coordinate_to_index(collision_coord, collision.size);
                        assert(!collision.filled[collision_index]);
                        collision.filled[collision_index] = block;
                    } else {
                        // @TODO: Fill in what to do if we need to resize the array.
                    }
                }
        }
    }
}

