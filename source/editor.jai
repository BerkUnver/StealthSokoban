Editor_Mode :: enum {
    DRAG;
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
    
    selected_index: int; // DO NOT MODIFY THIS IF selection_mode != .IDLE.
    selected_timer: float;
    
    union {
        drag: struct {
            mouse_start: Vector2;
            selectable_start: Vector3i;
            index: u8;
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


            // @TODO: Get rid of this raycast stuff
            // @TODO: Make it so "collision" is not used in the editor.
            
            /*
            if event.key == .MOUSE_LEFT_BUTTON && event.down {
                Raycast_Data :: struct {
                    block: *Block;
                    col: *Collision;
                }
                data := Raycast_Data.{col=*collision};
                raycast_visitor :: (position: Vector3i, using data: *Raycast_Data) -> bool {
                    success, index := get_3d_index(position, col.position, col.size);
                    if !success return false;
                    filled := col.filled[index];
                    if !filled return false;
                    block = filled;
                    return true;
                }

                ray_end := multiply_homogeneous(camera_to_world, .{mouse_x, mouse_y, 1});
                raycast(camera_position, ray_end, raycast_visitor, *data);
                
                if data.block && editor.selected_block != data.block {
                    editor.selected_timer = 0;
                }

                editor.selected_block = data.block;
                return;
            }
            */
            
            if event.key == .LEFT_ARROW && event.down {
                editor.selected_index = (editor.selected_index - 1 + selectables.count) % selectables.count;
                editor.selected_timer = 0;
                return;
            }

            if event.key == .RIGHT_ARROW && event.down {
                editor.selected_index = (editor.selected_index + 1) % selectables.count;
                editor.selected_timer = 0;
                return;
            }

            if event.key == xx #char "X" && event.down {
                Raycast_Data :: struct {
                    previous_coord_exists: bool;
                    previous_coord: Vector3i;
                    collided_block: *Block;
                    col: *Collision;
                }

                raycast_visitor :: (position: Vector3i, using data: *Raycast_Data) -> bool {
                    success, index := get_3d_index(position, col.position, col.size);
                    if !success || !col.filled[index] {
                        previous_coord_exists = true;
                        previous_coord = position;
                        return false;
                    } else {
                        collided_block = col.filled[index];
                        return true;
                    }
                }
                
                data := Raycast_Data.{col=*collision};
                ray_end := multiply_homogeneous(camera_to_world, .{mouse_x, mouse_y, 1});
                raycast(camera_position, ray_end, raycast_visitor, *data);
                
                block := data.collided_block;

                if block && data.previous_coord_exists {
                    block.position, block.size, block.filled = realloc_3d_array_to_fit_subarea(block.position, block.size, block.filled, data.previous_coord, Vector3i.{1, 1, 1}, level_arena);
                   

                    // @Speed do both of these at once
                    _:, _:, collision.filled = realloc_3d_array_to_fit_subarea(collision.position, collision.size, collision.filled, block.position, block.size, level_arena);

                    collision.position, collision.size, collision.viewed = realloc_3d_array_to_fit_subarea(collision.position, collision.size, collision.viewed, block.position, block.size, level_arena);


                    block_success, block_index := get_3d_index(data.previous_coord, block.position, block.size);
                    assert(block_success);
                    block.filled[block_index] = true;
                    update_block_mesh(*block.mesh, block.size, block.filled);

                    
                    collision_success, collision_index := get_3d_index(data.previous_coord, collision.position, collision.size);
                    assert(collision_success);
                    collision.filled[collision_index] = block;
                }
                return;
            }
            
            enable_drag :: (index: u8) #expand {
                `editor.selection_mode = .LOCKED;
                `editor.drag = .{
                    mouse_start = .{`mouse_x, `mouse_y},
                    selectable_start = `selectables[editor.selected_index].position,
                    index = index
                };
            }

            if event.key == xx #char "1" && event.down {
                enable_drag(0);
                return;
            }

            if event.key == xx #char "2" && event.down {
                enable_drag(1);
                return;
            }

            if event.key == xx #char "3" && event.down {
                enable_drag(2);
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
                case .DRAG;
                    using editor.drag;
                    if !event.down && ((index == 0 && event.key == xx #char "1")
                                    || (index == 1 && event.key == xx #char "2")
                                    || (index == 2 && event.key == xx #char "3")) {
                        editor.selection_mode = .IDLE;
                    }
            }
    }
}


editor_update :: (using l: *Level, editor: *Editor, mouse_x: float, mouse_y: float, dt: float) {
    if editor.selection_mode == {
        case .CAMERA;
            using editor.selection.camera;
            if rotating {
                PITCH_SPEED :: 50;
                YAW_SPEED :: 100;
                mouse := Vector2.{mouse_x, mouse_y};
                mouse_movement := rotating_previous_mouse_position - mouse;
                rotating_previous_mouse_position = mouse;
                
                camera_yaw += mouse_movement.x * dt * YAW_SPEED;
                camera_yaw = fmod_cycling(camera_yaw, TAU);

                camera_pitch -= mouse_movement.y * dt * PITCH_SPEED; 
                clamp(*camera_pitch, -PI/2, PI/2);
            }

            CAMERA_SPEED :: 240.0 / 60.0;
            camera_movement := get_camera_to_world_rotation_matrix(l) * moving_direction * (dt * CAMERA_SPEED);
            camera_position += camera_movement;

        case .LOCKED;
            if editor.mode == {
                case .DRAG; 
                    using editor.drag;

                    camera_to_world_rotation_matrix := get_camera_to_world_rotation_matrix(l);
                    camera_to_world := inverse(get_camera_matrix(l));
                    initial_mouse_position := multiply_homogeneous(camera_to_world, .{mouse_start.x, mouse_start.y, 0});
                    mouse_position := multiply_homogeneous(camera_to_world, .{mouse_x, mouse_y, 0});
                    
                    selectable_position := to_vector3(selectables[editor.selected_index].position);

                    axis: Vector3;
                    axis.component[index] = 1;


                    camera_normal := camera_to_world_rotation_matrix * Vector3.{0, 0, 1};
                    
                    // When we do cross(camera_normal, axis) we get a vector that runs parallel to the camera plane
                    // We cross that with the axis to get the normal of the plane formed by the axis and that parallel vector.
                    normal := cross(normalize(cross(camera_normal, axis)), axis);
                    // We don't need to normalize again because the parallel vector and the axis are already perpendicular.
                    // @TODO: Establish defined behavior for when the axis and the camera_normal are parallel.
                    // We should still be able to drag, and it looks like that is working right now, but I'm not sure why.


                    intersection_parallel, intersection := get_intersection_between_line_and_plane(
                        line_point = camera_position,
                        line_direction = mouse_position - camera_position,
                        plane_point = selectable_position,
                        plane_normal = normal);

                    initial_intersection_parallel, initial_intersection := get_intersection_between_line_and_plane(
                        line_point = camera_position,
                        line_direction = initial_mouse_position - camera_position,
                        plane_point = selectable_position,
                        plane_normal = normal);
                    
                    using context.game_context;

                    if initial_intersection_parallel
                    || intersection_parallel
                    || abs(intersection.component[index] - initial_intersection.component[index]) > 1000
                    // Prevent the selection from flying to infinity when the camera is almost parallel and close to the axis
                    || dot(intersection - camera_position, camera_normal - camera_position) <= 0 { // Prevent the selection from going behind the camera when the intersection point is behind the camera
                        selectables[editor.selected_index].position.component[index] = selectable_start.component[index];
                    } else {
                        movement := intersection.component[index] - initial_intersection.component[index];
                        new_position_component := cast(s32, round(cast(float, selectable_start.component[index]) + movement));
                        selectables[editor.selected_index].position.component[index] = new_position_component;
                    }
                    // :EditorCollision @TODO: UPDATE THE COLLISION GRID TO REFLECT THIS!
            }
    }
    
    FLASH_TIME :: 1;
    editor.selected_timer = fmod_cycling(editor.selected_timer + dt / FLASH_TIME, 1);
}
