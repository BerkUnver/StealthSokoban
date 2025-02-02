Editor_Mode :: enum {
    DRAG_X;
}

Editor_Selection_Mode :: enum {
    IDLE; // The user isn't doing anything. We can select new entities, rotate the camera, etc.
    CAMERA; // The camera is moving.
    LOCKED; // The user is using the current mode.
    // DON'T ALLOW CHANGING CAMERA ANGLE / CURRENTLY SELECTED BLOCK.
    // It could mess up what they're working on.
}

Editor :: struct {
    mode: Editor_Mode;
    selection_mode: Editor_Selection_Mode;
    selection: union {
        camera: struct {
            rotating: bool;
            rotating_previous_mouse_position: Vector2;
            moving_direction: Vector3;
        }
    }
    
    selected_block: *Block; // DO NOT MODIFY THIS IF selection_mode != .IDLE.
    
    union {
        drag_x: struct {
            mouse_start: Vector2;
            block_start_x: s32;
        }
    }
}


editor_handle_input :: (using l: *Level, level_arena: *Memory_Arena, editor: *Editor, mouse_x: float, mouse_y: float, event: Input_Event) {
    camera_to_world := inverse(get_camera_matrix(l));

    if editor.selection_mode == {
        case .IDLE;
            if event.key == .MOUSE_RIGHT_BUTTON && event.down {
                editor.selection_mode = .CAMERA;
                editor.selection.camera = .{
                    rotating = true,
                    rotating_previous_mouse_position = .{mouse_x, mouse_y}
                };
                return;
            }
            
            // Check to see if the camera is moving
            {
                moving_direction: Vector3;
                if event.key == {
                    case xx #char "W";
                        moving_direction.z = ifx event.down then 1.0;
                    case xx #char "A";
                        moving_direction.x = ifx event.down then -1.0;
                    case xx #char "S";
                        moving_direction.z = ifx event.down then -1.0;
                    case xx #char "D";
                        moving_direction.x = ifx event.down then 1.0;
                    case xx #char "Q";
                        moving_direction.y = ifx event.down then 1.0;
                    case xx #char "E";
                        moving_direction.y = ifx event.down then -1.0;
                }

                if moving_direction != Vector3.{} {
                    editor.selection_mode = .CAMERA;
                    editor.selection.camera = .{
                        moving_direction = moving_direction
                    };
                    return;
                }
            }


            if event.key == .MOUSE_LEFT_BUTTON && event.down {
                Raycast_Data :: struct {
                    block: *Block;
                    col: *Collision;
                }
                data := Raycast_Data.{col=*collision};
                raycast_visitor :: (position: Vector3, using data: *Raycast_Data) -> bool {
                    success, index := get_3d_index(to_vector3i(position), col.position, col.size);
                    if !success return false;
                    filled := col.filled[index];
                    if !filled return false;
                    block = filled;
                    return true;
                }

                ray_end := multiply_homogeneous(camera_to_world, .{mouse_x, mouse_y, 1});
                raycast(camera_position, ray_end, raycast_visitor, *data);

                editor.selected_block = data.block;
                return;
            }


            if event.key == xx #char "X" && event.down {
                Raycast_Data :: struct {
                    previous_coord_exists: bool;
                    previous_coord: Vector3i;
                    collided_block: *Block;
                    col: *Collision;
                }

                raycast_visitor :: (position: Vector3, using data: *Raycast_Data) -> bool {
                    coord := to_vector3i(position);
                    success, index := get_3d_index(coord, col.position, col.size);
                    if !success return false;
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
                    block_success, block_index := get_3d_index(data.previous_coord, block.position, block.size);
                    if block_success {
                        block.filled[block_index] = true;
                        
                        collision_success, collision_index := get_3d_index(data.previous_coord, collision.position, collision.size);
                        assert(collision_success); // Any block that's part of the level should _ALWAYS_ be within the bounds of the collision grid.

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

                        new_filled := arena_alloc_array(level_arena, new_size.x * new_size.y * new_size.z, bool);
                        
                        block_y_chunk := block.size.x * block.size.z;
                        
                        // @Speed we could rip the x-rows in with one memcpy
                        for :iterate_vector3i block.size {
                            filled := block.filled[it_index];
                            success, new_index := get_3d_index(it + block.position, new_position, new_size);
                            assert(success);
                            new_filled[new_index] = block.filled[it_index];
                        }

                        {
                            success, index := get_3d_index(data.previous_coord, new_position, new_size);
                            assert(success);
                            new_filled[index] = true;
                        }

                        block.position = new_position;
                        block.size = new_size;
                        block.filled = new_filled;

                        assert(add_block_to_collision(*collision, block));
                    }
                }
                return;
            }

            if event.key == xx #char "1" && event.down && editor.selected_block {
                editor.selection_mode = .LOCKED;
                editor.drag_x = .{
                    mouse_start = .{mouse_x, mouse_y},
                    block_start_x = editor.selected_block.position.x
                };
                return;
            }

        case .CAMERA;
            using editor.selection.camera; if event.key == {
                case .MOUSE_RIGHT_BUTTON;
                    if rotating && !event.down {
                        rotating = false;
                    }

                    if !rotating && event.down {
                        rotating = true;
                        rotating_previous_mouse_position = .{mouse_x, mouse_y};
                    }
                case xx #char "W";
                    moving_direction.z += ifx event.down then 1.0 else -1.0;
                case xx #char "A";
                    moving_direction.x += ifx event.down then -1.0 else 1.0;
                case xx #char "S";
                    moving_direction.z += ifx event.down then -1.0 else 1.0;
                case xx #char "D";
                    moving_direction.x += ifx event.down then 1.0 else -1.0;
                case xx #char "Q";
                    moving_direction.y += ifx event.down then 1.0 else -1.0;
                case xx #char "E";
                    moving_direction.y += ifx event.down then -1.0 else 1.0;
            }
            
            // The user has released all keys.
            // :AltTab this might not be true on Windows.
            if !rotating && moving_direction == .{} {
                editor.selection_mode = .IDLE;
            }

        case .LOCKED;
            if #complete editor.mode == {
                case .DRAG_X;
                    if event.key == xx #char "1" && !event.down {
                        editor.selection_mode = .IDLE;
                    }
            }
    }
}


editor_update :: (l: *Level, editor: *Editor, mouse_x: float, mouse_y: float, dt: float) {
    if editor.selection_mode == {
        case .CAMERA;
            using editor.selection.camera;
            if rotating {
                PITCH_SPEED :: 50;
                YAW_SPEED :: 100;
                mouse := Vector2.{mouse_x, mouse_y};
                mouse_movement := rotating_previous_mouse_position - mouse;
                rotating_previous_mouse_position = mouse;
                
                l.camera_yaw += mouse_movement.x * dt * YAW_SPEED;
                l.camera_yaw = fmod_cycling(l.camera_yaw, TAU);

                l.camera_pitch -= mouse_movement.y * dt * PITCH_SPEED; 
                clamp(*l.camera_pitch, -PI/2, PI/2);
            }

            CAMERA_SPEED :: 240.0 / 60.0;
            camera_movement := get_camera_to_world_rotation_matrix(l) * moving_direction * (dt * CAMERA_SPEED);
            l.camera_position += camera_movement;

        case .LOCKED;
            if editor.mode == {
                case .DRAG_X; 
                    using editor.drag_x;

                    camera_to_world_rotation_matrix := get_camera_to_world_rotation_matrix(l);
                    camera_to_world := inverse(get_camera_matrix(l));
                    initial_mouse_position := multiply_homogeneous(camera_to_world, .{mouse_start.x, mouse_start.y, 0});
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
                        editor.selected_block.position.x = block_start_x;
                    } else {
                        imm_state.shader = color_shader;
                        imm_cuboid(intersection - Vector3.{0.1, 0.1, 0.1}, intersection + Vector3.{0.1, 0.1, 0.1}, .{1, 1, 1, 1});
                        imm_cuboid(initial_intersection - Vector3.{0.1, 0.1, 0.1}, initial_intersection + Vector3.{0.1, 0.1, 0.1}, .{1, 1, 1, 1});
                        imm_flush();

                        x_movement := intersection.x - initial_intersection.x;
                        new_x := round(cast(float, block_start_x) + x_movement);
                        editor.selected_block.position.x = xx new_x;
                    }

                    // :EditorCollision @TODO: UPDATE THE COLLISION GRID TO REFLECT THIS!
            }
    }
}
