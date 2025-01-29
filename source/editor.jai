Editor_Mode :: enum {
    SELECTION;
    EXTRUSION;
}

Editor :: struct {
    mode: Editor_Mode;
    selected_block: *Block; // This should be valid even if we are not in the selection mode.

    camera_direction: Vector3i;
}


editor_handle_input :: (using level: *Level, level_arena: *Memory_Arena, editor: *Editor, mouse_x: float, mouse_y: float, event: Input_Event) {
    camera_to_world := inverse(get_camera_matrix(level));
    
    move_camera_sign := ifx event.down then cast(s32, 1) else cast(s32, -1);
    if event.key == {
        case xx #char "W";
            editor.camera_direction.z += move_camera_sign;
        case xx #char "A";
            editor.camera_direction.x -= move_camera_sign;
        case xx #char "S";
            editor.camera_direction.z -= move_camera_sign;
        case xx #char "D";
            editor.camera_direction.x += move_camera_sign;
        case xx #char "Q";
            editor.camera_direction.y += move_camera_sign;
        case xx #char "E";
            editor.camera_direction.y -= move_camera_sign;
    }

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

                ray_end := multiply_homogeneous(camera_to_world, .{mouse_x, mouse_y, 1});
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
                ray_end := multiply_homogeneous(camera_to_world, .{mouse_x, mouse_y, 1});
                raycast(camera_position, ray_end, raycast_visitor, *data);
                
                block := data.collided_block;
                if block && data.previous_coord_exists {
                    block_coord := data.previous_coord - block.position;

                    if inside_positive_bounding_box(block_coord, block.size) {
                        block_index := convert_3d_coordinate_to_index(block_coord, block.size);
                        block.filled[block_index] = true;

                        collision_coord := data.previous_coord - collision.position;
                        assert(inside_positive_bounding_box(collision_coord, collision.size)); // Any block that's part of the level should _ALWAYS_ be within the bounds of the collision grid.

                        collision_index := convert_3d_coordinate_to_index(collision_coord, collision.size);
                        assert(!collision.filled[collision_index]);
                        collision.filled[collision_index] = block;
                    } else if inside_positive_bounding_box(data.previous_coord - collision.position, collision.size) {
                        // @TODO: :EditorCollision figure out how collision in the editor is going to work.

                        // @Speed We could do it without removing the block.
                        remove_block_from_collision(*collision, block);
                        old := block.filled;
                    
                        new_position := Vector3i.{
                            min(data.previous_coord.x, block.position.x),
                            min(data.previous_coord.y, block.position.y),
                            min(data.previous_coord.z, block.position.z)
                        };
                        
                        new_end := Vector3i.{
                            max(data.previous_coord.x + 1, block.position.x + block.size.x),
                            max(data.previous_coord.y + 1, block.position.y + block.size.y),
                            max(data.previous_coord.z + 1, block.position.z + block.size.z)
                        };

                        new_size := new_end - new_position;

                        success, new_filled := arena_alloc_array(level_arena, new_size.x * new_size.y * new_size.z, bool);
                        assert(success);
                        
                        block_y_chunk := block.size.x * block.size.z;
                        
                        // @Speed we could rip the x-rows in with one memcpy
                        for :iterate_vector3i block.size {
                            filled := block.filled[it_index];
                            new_filled_coord := it + block.position - new_position;
                            assert(inside_positive_bounding_box(new_filled_coord, new_size));
                            new_index := convert_3d_coordinate_to_index(new_filled_coord, new_size);
                            new_filled[new_index] = block.filled[it_index];
                        }

                        {
                            coord := data.previous_coord - new_position;
                            assert(inside_positive_bounding_box(coord, new_size));
                            index := convert_3d_coordinate_to_index(coord, new_size);
                            new_filled[index] = true;
                        }

                        block.position = new_position;
                        block.size = new_size;
                        block.filled = new_filled;

                        assert(add_block_to_collision(*collision, block));
                    }
                }
        }
    }
}

editor_update :: (level: *Level, editor: *Editor, dt: float) {
    CAMERA_SPEED :: 120.0 / 60.0;
    camera_movement := rotate(to_vector3(editor.camera_direction), inverse(level.camera_rotation)) * dt * CAMERA_SPEED;
    level.camera_position += camera_movement;
}
