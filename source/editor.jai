Editor_Mode :: enum {
    IDLE;
    // We can change the selection in this mode. Other modes expect the selection
    // (and camera angle) to be fixed.

    CAMERA; // The camera is moving. DO NOT CHANGE THE SELECTION.

    // Do not allow changing the camera angle or selection in any of the below modes,
    // or else it could mess up what the user is working on.
    EXTRUDE; // We're extruding a block we clicked on
    DRAG;
}


Editor :: struct {
    mode: Editor_Mode;

    union {
        camera: struct {
            rotating: bool;
            rotating_key: Key;
            rotating_previous_mouse_position: Vector2;
            moving_direction: Vector3;
        }

        extrude: struct {
            block: Eid;
            start_position: Vector3;
            end_position: Vector3;
        }

        drag: struct {
            mouse_start: Vector2;
            selectable_start: Vector3i;
            index: u8;
        }
    }
    
    selected: Eid;
    selected_timer: float;
    
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


editor_handle_input :: (using level: *Level, level_arena: *Memory_Arena, editor: *Editor, mouse: Vector2, event: Input_Event) {
    using context.game_context;

    camera_to_world := inverse(get_editor_camera_matrix(editor));

    if editor.mode == {
        case .IDLE;
            if (event.key == .MOUSE_RIGHT_BUTTON || event.key == xx #char " ") && event.down {
                editor.mode = .CAMERA;
                editor.camera = .{
                    rotating = true,
                    rotating_key = event.key,
                    rotating_previous_mouse_position = mouse
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
                    editor.mode = .CAMERA;
                    editor.camera = .{
                        moving_direction = moving_direction
                    };
                    return;
                }
            }

            
            // @TODO Merge this with "X", this is a better version of "X".
            if event.key == xx #char "Z" && event.down {
                mouse_direction := multiply_homogeneous(camera_to_world, .{mouse.x, mouse.y, 1}) - editor.camera_position;

                // @TODO: Use a raycast selection instead of this, because due to floating-point error the 
                // points of each mesh might not be within the same integer range as the filled part of the
                // block.
                
                success, eid, intersection := get_intersection_with_selectable_meshes(level, editor, editor.camera_position, mouse_direction);

                if !success return;
                block := as(eid, Block);
                if !block return;

                editor.mode = .EXTRUDE;
                editor.extrude = .{
                    start_position = intersection,
                    end_position = intersection,
                    block = eid
                };

                return;
            }


            if event.key == xx #char "X" && event.down {
                // @TODO When we add multi-extrude, check to see if intersections between blocks
                // which aren't legal in gameplay actually happen in the editor, if so, add UI 
                // that warns about these.

                ray_end := multiply_homogeneous(camera_to_world, .{mouse.x, mouse.y, 1});
                block, _, previous_position_exists, previous_position := editor_raycast_to_block(level, editor.camera_position, ray_end);
                
                if block {    
                    // There won't be a previous position if we started the raycast
                    // while the camera was inside of a block. We shouldn't do 
                    // anything in that case.
                    if previous_position_exists {
                        block.position, block.size, block.filled = realloc_3d_array_to_fit_subarea(block.position, block.size, block.filled, previous_position, Vector3i.{1, 1, 1}, level_arena);
                       
                        block_success, block_index := get_3d_index(previous_position, block.position, block.size);
                        assert(block_success);
                        block.filled[block_index] = true;
                        update_block_mesh(*block.mesh, block.size, block.filled, level_arena);
                    }
                } else {
                    parallel, point, t := get_intersection_between_line_and_plane(
                        line_point = editor.camera_position,
                        line_direction = ray_end - editor.camera_position,
                        plane_point = .{0, 0, 0},
                        plane_normal = .{0, 1, 0}
                    );

                    if !parallel && t > 0 {
                        block := Temporary_Block.{
                            position = .{xx floor(point.x), xx floor(point.y), xx floor(point.z)},
                            size = .{1, 1, 1},
                            filled = .[true],
                            color = .{1, 1, 1, 1},
                            moveable = false
                        };
                        add_temporary_block_to_level(*block, level, level_arena);
                    }
                }
                return;
            }


            if event.key == .MOUSE_LEFT_BUTTON && event.down {
                mouse_direction := multiply_homogeneous(inverse(get_editor_camera_matrix(editor)), .{mouse.x, mouse.y, 0}) - editor.camera_position;
                mouse_position := editor.camera_position;

                success, selected, intersection := get_intersection_with_selectable_meshes(level, editor, mouse_position, mouse_direction);
                
                if success {
                    editor.selected = selected;
                    editor.selected_timer = 0;
                } else {
                    editor.selected = .{};
                }

                return;
            }

            if (event.key == .BACKSPACE || event.key == .DELETE) && event.down {
                if is_null(editor.selected) return;
                block := as(editor.selected, Block);
                if !block return;
                
                // @TODO: Figure out an ACTUALLY GOOD WAY TO DELETE ENTITIES
                // that doesn't risk leaving dangling entity references.

                for * blocks {
                    if it == block {
                        remove it;
                        break;
                    }
                }

                for selectables {
                    if eq(it, editor.selected) {
                        remove it;
                        break;
                    }
                }

                editor.selected = .{};
            }
            
            enable_drag :: (index: u8) #expand {
                if !is_null(editor.selected) {
                    editor.mode = .DRAG;
                    editor.drag = .{
                        mouse_start = mouse,
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
            using editor.camera;
            if event.key == {
                case .MOUSE_RIGHT_BUTTON; #through;
                case xx #char " "; // There's no easy way to right-click and hold on a trackpad.
                    if rotating {
                        if event.key == rotating_key && !event.down rotating = false;
                    } else {
                        if event.down {
                            rotating = true;
                            rotating_key = event.key;
                            rotating_previous_mouse_position = mouse;
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
                editor.mode = .IDLE;
            }

        case .EXTRUDE;
            if event.key == #char "Z" && !event.down {
                start := floor(editor.extrude.start_position);
                end := floor(editor.extrude.end_position);

                position_x, end_x := min_max(cast(s32, start.x), cast(s32, end.x));
                position_z, end_z := min_max(cast(s32, start.z), cast(s32, end.z));

                size_x := end_x - position_x + 1;
                size_z := end_z - position_z + 1;

                position := Vector3i.{position_x, xx start.y, position_z};
                size := Vector3i.{size_x, 1, size_z};
                
                block := as(editor.extrude.block, Block);
                assert(block != null);
                
                block.position, block.size, block.filled = realloc_3d_array_to_fit_subarea(block.position, block.size, block.filled, position, size, level_arena);
                
                offset := position - block.position;

                for :iterate_vector3i size {
                    block_position := it + offset;
                    success, index := get_3d_index(block_position, block.size);
                    assert(success);
                    block.filled[index] = true;
                }
                update_block_mesh(*block.mesh, block.size, block.filled, level_arena);

                editor.mode = .IDLE;
            }
        
        case .DRAG;
            using editor.drag;
            if !event.down && ((index == 0 && event.key == xx #char "1")
                            || (index == 1 && event.key == xx #char "2")
                            || (index == 2 && event.key == xx #char "3")) {
                editor.mode = .IDLE;
            }
    }
}


get_intersection_with_selectable_meshes :: (using level: *Level, editor: *Editor, line_position: Vector3, line_direction: Vector3) -> bool, Eid, intersection: Vector3 { 
    smallest_t := FLOAT32_INFINITY;
    selected: Eid;
    selected_intersection: Vector3;

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
                line_point = line_position,
                line_direction = line_direction,
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
            selected_intersection = intersection;
        }
    }

    if is_null(selected) return false, .{}, .{};

    return true, selected, selected_intersection;
}


editor_raycast_to_block :: (using level: *Level, ray_start: Vector3, ray_end: Vector3) -> *Block, collision_position: Vector3i, previous_position_exists: bool, previous_position: Vector3i {
    Raycast_Data :: struct {
        blocks: [] Block;
        collided_block: *Block;
        collision_position: Vector3i;
        previous_position: Vector3i;
        previous_position_exists: bool;
    }

    raycast_visitor :: (position: Vector3i, using data: *Raycast_Data) -> bool {
        // @Speed
        for * blocks {
            success, index := get_3d_index(position, it.position, it.size);
            if success && it.filled[index] {
                collision_position = position;
                collided_block = it;
                return true;
            }
        }

        previous_position_exists = true;
        previous_position = position;
        return false;
    }
    
    data := Raycast_Data.{
        blocks = to_array(blocks)
    };

    raycast(ray_start, ray_end, raycast_visitor, *data);

    block := data.collided_block;
    if !data.collided_block return null, .{}, false, .{};
    return data.collided_block, data.collision_position, data.previous_position_exists, data.previous_position;
}


editor_update :: (using level: *Level, editor: *Editor, mouse: Vector2, dt: float) {
    using context.game_context;

    if editor.mode == {
        case .CAMERA;
            using editor.camera;
            if rotating {
                PITCH_SPEED :: 50;
                YAW_SPEED :: 100;
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

        case .EXTRUDE;
            using editor.extrude;
            world_to_camera := get_editor_camera_matrix(editor);
            camera_to_world := inverse(world_to_camera);
            mouse_direction := multiply_homogeneous(camera_to_world, .{mouse.x, mouse.y, 0}) - editor.camera_position;

            parallel, intersection := get_intersection_between_line_and_plane(
                line_point = editor.camera_position,
                line_direction = mouse_direction,
                plane_point = start_position, 
                plane_normal = .{0, 1, 0} // @Temporary
            );

            if parallel {
                end_position = start_position;
            } else {
                end_position = intersection;
            }

        case .DRAG;
            using editor.drag;
            camera_to_world_rotation_matrix := get_editor_camera_to_world_rotation_matrix(editor);
            camera_to_world := inverse(get_editor_camera_matrix(editor));
            initial_mouse_position := multiply_homogeneous(camera_to_world, .{mouse_start.x, mouse_start.y, 0});
            mouse_position := multiply_homogeneous(camera_to_world, .{mouse.x, mouse.y, 0});
            
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
    
    FLASH_TIME :: 1;
    if !is_null(editor.selected) {
        editor.selected_timer = fmod_cycling(editor.selected_timer + dt / FLASH_TIME, 1);
    }
}
