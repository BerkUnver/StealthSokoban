Editor_Mode :: enum {
    SELECTION;
    DRAG_X;
    DRAG_Y;
    DRAG_Z;
    EXTRUSION;
    CAMERA_ROTATION;
}

Editor :: struct {
    mode: Editor_Mode;
    selected_block: *Block; // This should be valid even if we are not in the selection mode.
    
    union {
        camera_rotation: struct {
            previous_mouse_position: Vector2;
        }
        drag_x: struct {
            dragging: bool;
            drag_mouse_start: Vector2;
            drag_block_start: s32;
        }
    }
    camera_direction: Vector3;
}


editor_handle_input :: (using l: *Level, level_arena: *Memory_Arena, editor: *Editor, mouse_x: float, mouse_y: float, event: Input_Event) {
    camera_to_world := inverse(get_camera_matrix(l));
    
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
    if event.key == xx #char "1" {
        if event.down editor.mode = .DRAG_X;
        else if editor.mode == .DRAG_X editor.mode = .SELECTION;
    } else if event.key == xx #char "2" {
        if event.down editor.mode = .DRAG_Y;
        else if editor.mode == .DRAG_Y editor.mode = .SELECTION;
    } else if event.key == xx #char "3" {
        if event.down editor.mode = .DRAG_Z;
        else if editor.mode == .DRAG_Z editor.mode = .SELECTION;
    } else if event.key == xx #char "X" {
        if event.down editor.mode = .EXTRUSION;
        else if editor.mode == .EXTRUSION editor.mode = .SELECTION;
    } else if event.key == .MOUSE_RIGHT_BUTTON {
        if event.down {
            editor.mode = .CAMERA_ROTATION;
            editor.camera_rotation.previous_mouse_position = .{mouse_x, mouse_y};
        } else if editor.mode == .CAMERA_ROTATION {
            editor.mode = .SELECTION;
        }
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

            case .DRAG_X;
                if event.key == .MOUSE_LEFT_BUTTON && editor.selected_block {
                    using editor.drag_x;

                    if event.down {
                        dragging = true;
                        drag_mouse_start = .{mouse_x, mouse_y};
                        drag_block_start = editor.selected_block.position.x;
                    } else {
                        dragging = false;
                    }
                }

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
                        assert(inside_positive_bounding_box(collision_coord, collision.size)); // Any block that's part of the l should _ALWAYS_ be within the bounds of the collision grid.

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


editor_update :: (l: *Level, editor: *Editor, mouse_x: float, mouse_y: float, dt: float) {
    CAMERA_SPEED :: 240.0 / 60.0;
    camera_to_world_rotation_matrix := get_camera_to_world_rotation_matrix(l);
    camera_movement := camera_to_world_rotation_matrix * editor.camera_direction * (dt * CAMERA_SPEED);
    l.camera_position += camera_movement;

    if editor.mode == {
        case .SELECTION;
            b := editor.selected_block;
            // @BUG If the camera moves, the outline won't be drawn in the right place!
            if b {
                imm_cuboid_outline(to_vector3(b.position), to_vector3(b.position + b.size), 0.03, .{0, 1, 0, 1});
                imm_flush();
            }
            
        case .DRAG_X;
            using editor.drag_x;

            if dragging {
                camera_to_world := inverse(get_camera_matrix(l));
                initial_mouse_position := multiply_homogeneous(camera_to_world, .{drag_mouse_start.x, drag_mouse_start.y, 0});
                mouse_position := multiply_homogeneous(camera_to_world, .{mouse_x, mouse_y, 0});
                
                block_position := to_vector3(editor.selected_block.position);

                camera_up := camera_to_world_rotation_matrix * Vector3.{0, 1, 0};
                draw_arrow(block_position, block_position + camera_up, .{0, 0, 1, 1});
                draw_arrow(block_position, block_position + Vector3.{1, 0, 0}, .{0, 0, 1, 1});
                normal := cross(camera_up, .{1, 0, 0});

                intersection_parallel, intersection := get_intersection_between_line_and_plane(
                    line_point = l.camera_position,
                    line_direction = mouse_position - l.camera_position,
                    plane_point = block_position,
                    plane_normal = normal);

                initial_intersection_parallel, initial_intersection := get_intersection_between_line_and_plane(
                    line_point = l.camera_position,
                    line_direction = initial_mouse_position - l.camera_position,
                    plane_point = block_position,
                    plane_normal = normal);
                
                using context.game_context;

                // If the difference between either of the intersections and the initial positions are this high,
                // then that means the x-axis is almost parallel to the normal vector of the camera.
                // (Perhaps we could do a dot product instead?)
                // In this case, don't do anything to we don't get polluted with infinities.
                
                camera_normal := camera_to_world_rotation_matrix * Vector3.{0, 0, 1};
                if initial_intersection_parallel
                || intersection_parallel
                || abs(dot(camera_normal, Vector3.{1, 0, 0})) > 0.99 { // They are almost parallel.
                    editor.selected_block.position.x = drag_block_start;
                } else {
                    imm_state.shader = color_shader;
                    imm_cuboid(intersection - Vector3.{0.1, 0.1, 0.1}, intersection + Vector3.{0.1, 0.1, 0.1}, .{1, 1, 1, 1});
                    imm_cuboid(initial_intersection - Vector3.{0.1, 0.1, 0.1}, initial_intersection + Vector3.{0.1, 0.1, 0.1}, .{1, 1, 1, 1});
                    imm_flush();

                    x_movement := intersection.x - initial_intersection.x;
                    new_x := round(cast(float, drag_block_start) + x_movement);
                    editor.selected_block.position.x = xx new_x;

                    print("new_x: %\n", new_x);
                }

                // @TODO: UPDATE THE COLLISION GRID TO REFLECT THIS!
            }

        case .CAMERA_ROTATION;
            using editor.camera_rotation;
            
            PITCH_SPEED :: 50;
            YAW_SPEED :: 100;
            mouse := Vector2.{mouse_x, mouse_y};
            mouse_movement := previous_mouse_position - mouse;
            previous_mouse_position = mouse;
            
            l.camera_yaw += mouse_movement.x * dt * YAW_SPEED;
            l.camera_yaw = fmod_cycling(l.camera_yaw, TAU);

            l.camera_pitch -= mouse_movement.y * dt * PITCH_SPEED; 
            clamp(*l.camera_pitch, -PI/2, PI/2);
    }
}
