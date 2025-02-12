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
            rotating_key: Key;
            rotating_previous_mouse_position: Vector2;
            moving_direction: Vector3;
        }
    }
    
    // Do not access these directly, use the get_selected function.
    // Unless you're the code that modifies this, of course.
    selected: Eid;
    selected_timer: float;
    
    union {
        drag: struct {
            mouse_start: Vector2;
            selectable_start: Vector3i;
            index: u8;
        }
    }

    camera_position := Vector3.{0, 8, -4};
    camera_pitch: float;
    camera_yaw: float;
}


get_editor_camera_matrix :: (ed: *Editor) -> Matrix4 {
    position_matrix := make_translation_matrix4(-ed.camera_position);
    pitch_matrix := make_x_rotation_matrix(Matrix4, -ed.camera_pitch);
    yaw_matrix := make_y_rotation_matrix(Matrix4, -ed.camera_yaw);

    return multiply(FRUSTUM, multiply(pitch_matrix, multiply(yaw_matrix, position_matrix)));
}


get_editor_camera_to_world_rotation_matrix :: (ed: *Editor) -> Matrix3 {
    yaw_matrix := make_y_rotation_matrix(Matrix3, ed.camera_yaw);
    pitch_matrix := make_x_rotation_matrix(Matrix3, ed.camera_pitch);
    return multiply(yaw_matrix, pitch_matrix);
}


editor_handle_input :: (using level: *Level, level_arena: *Memory_Arena, editor: *Editor, mouse_x: float, mouse_y: float, event: Input_Event) {
    using context.game_context;

    camera_to_world := inverse(get_editor_camera_matrix(editor));

    if editor.selection_mode == {
        case .IDLE;
            if (event.key == .MOUSE_RIGHT_BUTTON || event.key == xx #char " ") && event.down {
                editor.selection_mode = .CAMERA;
                editor.selection.camera = .{
                    rotating = true,
                    rotating_key = event.key,
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


            if event.key == xx #char "X" && event.down {
                // @TODO When we add multi-extrude, check to see if intersections between blocks
                // which aren't legal in gameplay actually happen in the editor, if so, add UI 
                // that warns about these.

                Raycast_Data :: struct {
                    blocks: [] Block;
                    previous_coord_exists: bool;
                    previous_coord: Vector3i;
                    collided_block: *Block;
                }

                raycast_visitor :: (position: Vector3i, using data: *Raycast_Data) -> bool {
                    // @Speed
                    for * blocks {
                        success, index := get_3d_index(position, it.position, it.size);
                        if success && it.filled[index] {
                            collided_block = it;
                            return true;
                        }
                    }

                    previous_coord_exists = true;
                    previous_coord = position;
                    return false;
                }
                
                data := Raycast_Data.{
                    blocks = to_array(blocks)
                };
                ray_end := multiply_homogeneous(camera_to_world, .{mouse_x, mouse_y, 1});
                raycast(editor.camera_position, ray_end, raycast_visitor, *data);
                
                block := data.collided_block;

                if block && data.previous_coord_exists {
                    block_success, block_index := get_3d_index(data.previous_coord, block.position, block.size);
                    assert(block_success);
                    block.filled[block_index] = true;
                    update_block_mesh(*block.mesh, block.size, block.filled, level_arena);
                }
                return;
            }


            if event.key == .MOUSE_LEFT_BUTTON && event.down {
                mouse_direction := multiply_homogeneous(inverse(get_editor_camera_matrix(editor)), .{mouse_x, mouse_y, 0}) - editor.camera_position;
                mouse_position := editor.camera_position;
                
                smallest_t := FLOAT32_INFINITY;
                selected: Eid;

                for selectables {
                    position := to_vector3(eid_position(it).*);
                    mesh := eid_mesh(it);

                    assert(mesh.vertex_positions.count % 3 == 0);
                    tri_count := mesh.vertex_positions.count / 3;

                    for i: 0..tri_count-1 {
                        start := i * 3;
                        v0 := mesh.vertex_positions[start]   + position;
                        v1 := mesh.vertex_positions[start+1] + position;
                        v2 := mesh.vertex_positions[start+2] + position;

                        normal := cross(v1-v0, v2-v0);

                        parallel, intersection, t := get_intersection_between_line_and_plane(
                            line_point = mouse_position,
                            line_direction = mouse_direction,
                            plane_point = v0,
                            plane_normal = normal
                        );

                        if parallel continue;
                      
                        if t > smallest_t continue;

                        if dot(normal, cross(v1-v0, intersection-v0)) <= 0 continue;
                        if dot(normal, cross(v2-v1, intersection-v1)) <= 0 continue;
                        if dot(normal, cross(v0-v2, intersection-v2)) <= 0 continue;
                        
                        smallest_t = t;
                        selected = it;
                    }
                }

                editor.selected = selected;
                if !is_null(selected) editor.selected_timer = 0;
                return;
            }
            
            enable_drag :: (index: u8) #expand {
                if !is_null(editor.selected) {
                    editor.selection_mode = .LOCKED;
                    editor.drag = .{
                        mouse_start = .{mouse_x, mouse_y},
                        selectable_start = eid_position(editor.selected).*,
                        index = index
                    };
                }
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
                case .MOUSE_RIGHT_BUTTON; #through;
                case xx #char " "; // There's no easy way to right-click and hold on a trackpad.
                    if rotating {
                        if event.key == rotating_key && !event.down rotating = false;
                    } else {
                        if event.down {
                            rotating = true;
                            rotating_key = event.key;
                            rotating_previous_mouse_position = .{mouse_x, mouse_y};
                        }
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


editor_update :: (using level: *Level, editor: *Editor, mouse_x: float, mouse_y: float, dt: float) {
    if editor.selection_mode == {
        case .CAMERA;
            using editor.selection.camera;
            if rotating {
                PITCH_SPEED :: 50;
                YAW_SPEED :: 100;
                mouse := Vector2.{mouse_x, mouse_y};
                mouse_movement := rotating_previous_mouse_position - mouse;
                rotating_previous_mouse_position = mouse;
                
                editor.camera_yaw += mouse_movement.x * dt * YAW_SPEED;
                editor.camera_yaw = fmod_cycling(editor.camera_yaw, TAU);

                editor.camera_pitch -= mouse_movement.y * dt * PITCH_SPEED; 
                clamp(*editor.camera_pitch, -PI/2, PI/2);
            }

            CAMERA_SPEED :: 240.0 / 60.0;
            camera_movement := get_editor_camera_to_world_rotation_matrix(editor) * moving_direction * (dt * CAMERA_SPEED);
            editor.camera_position += camera_movement;

        case .LOCKED;
            if editor.mode == {
                case .DRAG; 
                    using editor.drag;


                    
                    if !is_null(editor.selected) {
                        camera_to_world_rotation_matrix := get_editor_camera_to_world_rotation_matrix(editor);
                        camera_to_world := inverse(get_editor_camera_matrix(editor));
                        initial_mouse_position := multiply_homogeneous(camera_to_world, .{mouse_start.x, mouse_start.y, 0});
                        mouse_position := multiply_homogeneous(camera_to_world, .{mouse_x, mouse_y, 0});
                        
                        selected_position := to_vector3(eid_position(editor.selected).*);

                        axis: Vector3;
                        axis.component[index] = 1;


                        camera_normal := camera_to_world_rotation_matrix * Vector3.{0, 0, 1};
                        
                        // When we do cross(camera_normal, axis) we get a vector that runs parallel to the camera plane
                        // We cross that with the axis to get the normal of the plane formed by the axis and that parallel vector.
                        normal := cross(normalize(cross(camera_normal, axis)), axis);
                        // We don't need to normalize again because the parallel vector and the axis are already perpendicular.
                        // @TODO: Establish defined behavior for when the axis and the camera_normal are parallel.
                        // We should still be able to drag, and it looks like that is working right now, but I'm not sure why.


                        intersection_parallel, intersection, intersection_t := get_intersection_between_line_and_plane(
                            line_point = editor.camera_position,
                            line_direction = mouse_position - editor.camera_position,
                            plane_point = selected_position,
                            plane_normal = normal);

                        initial_intersection_parallel, initial_intersection := get_intersection_between_line_and_plane(
                            line_point = editor.camera_position,
                            line_direction = initial_mouse_position - editor.camera_position,
                            plane_point = selected_position,
                            plane_normal = normal);
                        
                        using context.game_context;

                        if initial_intersection_parallel
                        || intersection_parallel
                        || intersection_t <= 0 // Prevent the selection from going behind the camera when the intersection point is behind the camera
                        || abs(intersection.component[index] - initial_intersection.component[index]) > 1000 {
                        // Prevent the selection from flying to infinity when the camera is almost parallel and close to the axis
                            eid_position(editor.selected).component[index] = selectable_start.component[index];
                        } else {
                            movement := intersection.component[index] - initial_intersection.component[index];
                            new_position_component := cast(s32, round(cast(float, selectable_start.component[index]) + movement));
                            eid_position(editor.selected).component[index] = new_position_component;
                        }
                    }
            }
    }
    
    FLASH_TIME :: 1;
    if !is_null(editor.selected) {
        editor.selected_timer = fmod_cycling(editor.selected_timer + dt / FLASH_TIME, 1);
    }
}
