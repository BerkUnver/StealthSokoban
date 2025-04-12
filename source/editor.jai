Editor_Mode :: enum {
    IDLE;
    // We can change the selection in this mode. Other modes expect the selection
    // (and camera angle) to be fixed.

    CAMERA; // The camera is moving. DO NOT CHANGE THE SELECTION.

    // Do not allow changing the camera angle or selection in any of the below modes,
    // or else it could mess up what the user is working on.
    EXTRUDE; // We're extruding a gridlike we clicked on
    DRAG_OLD; // @TODO delete this!
    DRAG;
}


EDITOR_FRUSTUM :: #run -> Matrix4 {
    FOV :: PI / 3;

    right := cast(float, NEAR_PLANE * tan(FOV / 2));
    top := right * cast(float, INNER_WINDOW_H) / cast(float, INNER_WINDOW_W);

    return make_left_handed_frustum_matrix(-right, -top, NEAR_PLANE, right, top, FAR_PLANE);
}


DRAG_START :: 0.15;
DRAG_END :: 0.85;


get_editor_camera_matrix :: (using level: *Level) -> Matrix4 {
    position_matrix := make_translation_matrix4(-editor.camera_position);
    pitch_matrix := make_x_rotation_matrix(Matrix4, -editor.camera_pitch);
    yaw_matrix := make_y_rotation_matrix(Matrix4, -editor.camera_yaw);

    return multiply(EDITOR_FRUSTUM, multiply(pitch_matrix, multiply(yaw_matrix, position_matrix)));
}


get_editor_camera_to_world_rotation_matrix :: (using level: *Level) -> Matrix3 {
    yaw_matrix := make_y_rotation_matrix(Matrix3, editor.camera_yaw);
    pitch_matrix := make_x_rotation_matrix(Matrix3, editor.camera_pitch);
    return multiply(yaw_matrix, pitch_matrix);
}


editor_handle_input :: (using level: *Level, arena: *Memory_Arena, mouse: Vector2, event: Input_Event) {
    using context.game_context;

    camera_to_world := inverse(get_editor_camera_matrix(level));

    if editor.mode == {
        case .IDLE;
            mouse_start := editor.camera_position;
            mouse_end := multiply_homogeneous(camera_to_world, .{mouse.x, mouse.y, 1});
            mouse_direction := mouse_end - mouse_start;

            if (event.key == .MOUSE_RIGHT_BUTTON || event.key == xx #char " ") && event.state == .DOWN {
                editor.mode = .CAMERA;
                editor.camera = .{
                    rotating_previous_mouse_position = mouse
                };
                return;
            }
            
            // Check to see if the camera is moving
            if event.state == .DOWN 
            && (event.key == #char "W" 
             || event.key == #char "A"
             || event.key == #char "S"
             || event.key == #char "D"
             || event.key == #char "Q"
             || event.key == #char "E") {
                    editor.mode = .CAMERA;
                    editor.camera = .{};
                    return;
            }
            
            if event.key == xx #char "Z" && event.state == .DOWN {
                Data :: struct {
                    level: *Level;
                    selected: Entity_Id;
                    selected_position: Vector3i;
                    previous_position: Vector3i;
                    previous_position_exists: bool;
                }

                visitor :: (position: Vector3i, using data: *Data) -> bool {
                    check_gridlike_entities :: (entities: [] $T) #expand {
                        for entities {
                            success, index := get_3d_index(position, it.position, it.size);
                            if success && it.filled[index] {
                                selected = it.eid;
                                selected_position = position;
                                `return true;
                            }
                        }
                    }

                    check_gridlike_entities(level._Block);
                    check_gridlike_entities(level._Door);

                    previous_position = position;
                    previous_position_exists = true;
                    return false;
                }

                data := Data.{level=level};
                collided, t := raycast(mouse_start, mouse_end, visitor, *data);

                if collided {
                    // There won't be a previous position if we started the raycast
                    // while the camera was inside of something. We shouldn't do 
                    // anything in that case.
                    if !data.previous_position_exists return;

                    start_position: Vector3i;
                    tweak_sign := 0.0;

                    if keys_down[Key.SHIFT] != keys_down[Key.CTRL] {
                        start_position = data.selected_position;
                        tweak_sign = 1;
                    } else {
                        start_position = data.previous_position;
                        tweak_sign = -1;
                    }

                    tweak := tweak_sign * normalize(mouse_direction) * 0.001;
                    // Because the intersection between the mouse and a gridlike by definition
                    // lies exactly on an integer value of an axis for one of the coordinates,
                    // there will be weird floating-point precision errors when we try to 
                    // calculate future intersections. Therefore, we tweak in the direction we 
                    // want to go to avoid this.

                    intersection := mouse_start + mouse_direction * t + tweak;

                    editor.mode = .EXTRUDE;
                    editor.extrude = .{
                        selected = data.selected,
                        start_position = start_position,
                        start_intersection = intersection,
                        end_intersection = intersection,
                        plane_normal = .{0, 1, 0},
                        deletion = keys_down[Key.CTRL],
                    };

                } else {
                    // Commenting this out for now because we have new Door entities that are like Block entities
                    // but not exactly. It is ambiguous which one we would want to spawn.

                    /*
                    parallel, point, new_block_t := get_intersection_between_line_and_plane(
                        line_point = mouse_start,
                        line_direction = mouse_direction,
                        plane_point = .{0, 0, 0},
                        plane_normal = .{0, 1, 0}
                    );

                    if parallel || new_block_t <= 0 return;

                    filled := alloc_view(arena, 1, bool);
                    filled[0] = true;
                    size := Vector3i.{1, 1, 1};

                    block := make_entity(level, Block, arena);
                    block.size = size;
                    block.position = .{xx floor(point.x), 0, xx floor(point.z)};
                    block.filled = filled;
                    block.color = .{1, 1, 1, 1};
                    block.mesh = make_block_mesh(size, filled, arena);

                    start_intersection := point + normalize(mouse_direction) * 0.001;

                    editor.mode = .EXTRUDE;
                    editor.extrude = .{
                        selected_block = block,
                        start_position = block.position,
                        start_intersection = point,
                        end_intersection = point,
                        plane_normal = .{0, 1, 0},
                    };
                    */
                }
                return;
            }


            if event.key == .MOUSE_LEFT_BUTTON && event.state == .DOWN {
                drag_clicked := false;

                if editor.selected {
                    e := get_entity(level, editor.selected);

                    
                    smallest_exists := false;
                    smallest_t: float;
                    smallest_index: int;

                    for 0..2 {
                        normal: Vector3;
                        normal.component[it] = 1;
                        
                        parallel, point, t := get_intersection_between_line_and_plane(mouse_start, mouse_direction, to_vector3(e.position), normal);

                        if !parallel && !smallest_exists || (smallest_exists && t < smallest_t) {
                            a_index := (it + 1) % 3;
                            a := point.component[a_index] - cast(float, e.position.component[a_index]);
                            a_positive := editor.camera_position.component[a_index] < xx e.position.component[a_index];

                            b_index := (it + 2) % 3;
                            b := point.component[b_index] - cast(float, e.position.component[b_index]);
                            b_positive := editor.camera_position.component[b_index] < xx e.position.component[b_index];

                            if (a_positive && DRAG_START < a && a < DRAG_END)
                            || (!a_positive && -DRAG_END < a && a < -DRAG_START)
                            || (b_positive && DRAG_START < b && b < DRAG_END)
                            || (!b_positive && -DRAG_END < b && b < -DRAG_START) {
                                smallest_exists = true;
                                smallest_t = t;
                                smallest_index = it;
                            }
                        }
                    }

                    if smallest_exists {
                        drag_clicked = true;
                        editor.mode = .DRAG;
                        editor.drag = .{index = xx smallest_index};
                    }
                }

                if !drag_clicked {
                    success, selected, intersection := get_intersection_with_selectable_meshes(level, mouse_start, mouse_end);

                    if success {
                        editor.selected = selected;
                        editor.selected_timer = 0;
                    } else {
                        editor.selected = 0;
                    }
                }

                return;
            }

            if (event.key == .BACKSPACE || event.key == .DELETE) && event.state == .DOWN {
                if editor.selected != 0 {
                    delete_entity(level, editor.selected, arena);
                    editor.selected = 0;
                }
                return;
            }
            
            enable_drag :: (index: u8) #expand {
                if editor.selected {
                    e := get_entity(level, editor.selected);
                    editor.mode = .DRAG_OLD;
                    editor.drag_old = .{
                        mouse_start = mouse,
                        selectable_start = e.position,
                        index = index
                    };
                }
            }

            if event.key == xx #char "1" && event.state == .DOWN {
                enable_drag(0);
                return;
            }

            if event.key == xx #char "2" && event.state == .DOWN {
                enable_drag(1);
                return;
            }

            if event.key == xx #char "3" && event.state == .DOWN {
                enable_drag(2);
                return;
            }

            if .ARROW_START <= event.key && event.key <= .ARROW_END && event.state == .DOWN {
                if editor.selected == 0 return;
                e := get_entity(level, editor.selected);

                dir: Vector3i;
                if event.key == {
                    case .UP_ARROW;     dir = local_to_global_direction( 0,  1, xx editor.camera_yaw);
                    case .LEFT_ARROW;   dir = local_to_global_direction(-1,  0, xx editor.camera_yaw);
                    case .DOWN_ARROW;   dir = local_to_global_direction( 0, -1, xx editor.camera_yaw);
                    case .RIGHT_ARROW;  dir = local_to_global_direction( 1,  0, xx editor.camera_yaw);
                    case; assert(false);
                }

                facing := vector3i_to_facing(dir);
                
                enemy := as(e, Enemy);
                if enemy {
                    enemy.facing = facing;
                    return;
                }

                enemy_spawner := as(e, Enemy_Spawner);
                if enemy_spawner {
                    enemy_spawner.facing = facing;
                    return;
                }

                return;
            }


            if (.F_BASE < event.key && event.key < Key.F_BASE + 1 + ENTITIES.count) && event.state == .DOWN {
                success, _, intersection := get_intersection_with_selectable_meshes(level, mouse_start, mouse_end);
                position: Vector3i;
                if success {
                    // The 0.001 go-back is in case the intersection is on an integer boundary (like colliding with Blocks),
                    // where we're at risk of floating-point errors.
                    position = to_vector3i(floor(intersection - normalize(mouse_direction) * 0.001));
                } else {
                    parallel, intersection, t := get_intersection_between_line_and_plane(
                        line_point = mouse_start,
                        line_direction = mouse_direction,
                        plane_point = .{0, 0, 0},
                        plane_normal = .{0, 1, 0}
                    );

                    if parallel || t <= 0 return;

                    position = .{xx floor(intersection.x), 0, xx floor(intersection.z)};
                }


                index := cast(int, event.key - 1 - .F_BASE);
                e := make_entity(level, index, arena);
                e.position = position;


                init_grid_entity :: (e: *$T) #expand {
                    filled := alloc_view(arena, 1, bool);
                    filled[0] = true;

                    e.size = .{1, 1, 1};
                    e.filled = filled;
                    e.mesh = make_gridlike_mesh(.{1, 1, 1}, filled, arena);
                }

                if e.type == .Block {
                    block := as(e, Block);
                    init_grid_entity(block);
                    block.color = .{1, 1, 1, 1};
                } else if e.type == .Door {
                    door := as(e, Door);
                    init_grid_entity(door);
                }
                return;
            }

        case .CAMERA;
            using editor.camera;

            if event.key == #char " " && event.state == .DOWN && !keys_down[Key.MOUSE_RIGHT_BUTTON] {
                rotating_previous_mouse_position = mouse;
                return;
            }

            if event.key == .MOUSE_RIGHT_BUTTON && event.state == .DOWN && !keys_down[#char " "] {
                rotating_previous_mouse_position = mouse;
                return;
            }

            if !keys_down[#char "W"]
            && !keys_down[#char "S"]
            && !keys_down[#char "A"]
            && !keys_down[#char "D"]
            && !keys_down[#char "Q"]
            && !keys_down[#char "E"] 
            && !keys_down[#char " "] 
            && !keys_down[Key.MOUSE_RIGHT_BUTTON] {
                // The user has released all keys.
                // :AltTab this might not be true on Windows.
                editor.mode = .IDLE;
            }
            
        case .EXTRUDE;
            using editor.extrude;
            if event.key == #char " " && event.state == .DOWN {
                for plane_normal.component {
                    if it == 1 {
                        plane_normal.component[it_index] = 0;
                        plane_normal.component[(it_index + 1) % plane_normal.component.count] = 1;
                        break;
                    }
                }
            } else if event.key == #char "Z" && event.state == .UP {
                position, size := get_editor_extrude_size(level);

                extrude_gridlike_entity :: (e: *$T/Entity) #expand {
                    if deletion {
                        offset := position - e.position;
                        // @Speed iterate over the overlap between the selection and the block
                        for :iterate_vector3i size {    
                            success, index := get_3d_index(it + offset, e.size);
                            if success e.filled[index] = false;
                        }

                        // Now, we want to shrink where the block boundaries are if we can.

                        all_zero := true;
                        new_position: Vector3i;
                        new_end: Vector3i;

                        for :iterate_vector3i e.size {
                            filled := e.filled[it_index];
                            if !filled continue;
                            cell_position := it + e.position;
                            
                            if all_zero {
                                all_zero = false;
                                new_position = cell_position;
                                new_end = cell_position;
                            } else {
                                if cell_position.x < new_position.x new_position.x = cell_position.x;
                                if cell_position.y < new_position.y new_position.y = cell_position.y;
                                if cell_position.z < new_position.z new_position.z = cell_position.z;
                                
                                if cell_position.x > new_end.x new_end.x = cell_position.x;
                                if cell_position.y > new_end.y new_end.y = cell_position.y;
                                if cell_position.z > new_end.z new_end.z = cell_position.z;
                            }
                        }

                        if all_zero {
                            if e.eid == editor.selected editor.selected = 0;
                            delete_entity(level, e.eid, arena);
                        } else {
                            new_size := new_end - new_position + Vector3i.{1,1,1};
                            if e.size != new_size {
                                new_filled := alloc_view(arena, new_size.x * new_size.y * new_size.z, bool);
                                for :iterate_vector3i v: new_size {
                                    success, src_index := get_3d_index(v + new_position, e.position, e.size);
                                    assert(success);
                                    new_filled[it_index] = e.filled[src_index];
                                }

                                e.filled = new_filled;
                                e.position = new_position;
                                e.size = new_size;
                            }

                            update_gridlike_mesh(e, arena);
                        }
                    } else {
                        e.position, e.size, e.filled = realloc_3d_array_to_fit_subarea(e.position, e.size, e.filled, position, size, arena);
                        offset := position - e.position;

                        for :iterate_vector3i size {
                            gridlike_position := it + offset;
                            success, index := get_3d_index(gridlike_position, e.size);
                            assert(success);
                            e.filled[index] = true;
                        }

                        update_gridlike_mesh(e, arena);
                    }
                }

                e := get_entity(level, selected);
                if e.type == .Block {
                    extrude_gridlike_entity(as(e, Block));
                } else if e.type == .Door {
                    extrude_gridlike_entity(as(e, Door));
                } else assert(false);

                editor.mode = .IDLE;
            }

        case .DRAG_OLD;
            using editor.drag_old;
            if event.state == .UP && ((index == 0 && event.key == xx #char "1")
                                   || (index == 1 && event.key == xx #char "2")
                                   || (index == 2 && event.key == xx #char "3")) {
                // @TODO: change level_position or level_size to accomadate the new position.
                editor.mode = .IDLE;
            }

        case .DRAG;
            if event.key == .MOUSE_LEFT_BUTTON && event.state == .UP {
                editor.mode = .IDLE;
            }
    }
}


get_intersection_with_selectable_meshes :: (using level: *Level, line_start: Vector3, line_end: Vector3) -> bool, Entity_Id, intersection: Vector3 { 
    line_direction := line_end - line_start;
    smallest_t := FLOAT32_INFINITY;
    selected_found := false;
    selected: Entity_Id;
    selected_intersection: Vector3;
    
    for :iterate_entities e: types {
        // :CpuPositions
        // The way we currently do mouse picking of onscreen meshes is by
        // doing a raycast from the mouse and checking it against each tri
        // of each entity's mesh on the CPU. What we should probably actually do
        // is once we have a real renderer, we should do a separate picking render
        // pass, and therefore we don't have to store our mesh vertex positions
        // on the CPU.

        mesh := entity_mesh(e);
        matrix := inverse(entity_mesh_to_world_matrix(level, e));

        local_line_start := multiply_homogeneous(matrix, line_start);
        local_line_end   := multiply_homogeneous(matrix, line_end);
        local_line_direction := local_line_end - local_line_start;

        assert(mesh.vertex_positions.count % 3 == 0);
        tri_count := mesh.vertex_positions.count / 3;

        for i: 0..tri_count-1 {
            start := i * 3;
            v0 := mesh.vertex_positions[start];
            v1 := mesh.vertex_positions[start+1];
            v2 := mesh.vertex_positions[start+2];

            normal := cross(v1-v0, v2-v0);

            // Because t is a ratio of how much of the line_direction to add to the 
            // line_point to get the intersection, we can use t on the untransformed
            // versions of line_point and line_direction.

            parallel, local_intersection, t := get_intersection_between_line_and_plane(
                line_point = local_line_start,
                line_direction = local_line_direction,
                plane_point = v0,
                plane_normal = normal
            );

            if parallel continue;
          
            if t <= 0 || smallest_t < t continue;

            // Make sure the intersection point is within the triangle
            if dot(normal, cross(v1-v0, local_intersection-v0)) <= 0 continue;
            if dot(normal, cross(v2-v1, local_intersection-v1)) <= 0 continue;
            if dot(normal, cross(v0-v2, local_intersection-v2)) <= 0 continue;
            
            smallest_t = t;
            selected_found = true;
            selected = e.eid;
            selected_intersection = line_start + line_direction * t;
        }
    }

    return selected_found, selected, selected_intersection;
}


editor_update :: (using level: *Level,  mouse: Vector2, dt: float) {
    using context.game_context;

    if editor.mode == {
        case .CAMERA;
            using editor.camera;
            if keys_down[#char " "] || keys_down[Key.MOUSE_RIGHT_BUTTON] {
                PITCH_SPEED :: 50;
                YAW_SPEED :: 100;
                mouse_movement := rotating_previous_mouse_position - mouse;
                rotating_previous_mouse_position = mouse;
                
                editor.camera_yaw += mouse_movement.x * dt * YAW_SPEED;
                editor.camera_yaw = fmod_cycling(editor.camera_yaw, TAU);

                editor.camera_pitch -= mouse_movement.y * dt * PITCH_SPEED; 
                clamp(*editor.camera_pitch, -PI/2, PI/2);
            }

            CAMERA_NORMAL_SPEED :: 240.0 / 60.0;
            CAMERA_FAST_SPEED :: 960.0 / 60.0;

            camera_speed := CAMERA_NORMAL_SPEED;
            if keys_down[Key.SHIFT] camera_speed = CAMERA_FAST_SPEED;

            x := cast(int, keys_down[#char "D"]) - cast(int, keys_down[#char "A"]);
            y := cast(int, keys_down[#char "Q"]) - cast(int, keys_down[#char "E"]);
            z := cast(int, keys_down[#char "W"]) - cast(int, keys_down[#char "S"]);
            dir := Vector3.{xx x, xx y, xx z};

            camera_movement := get_editor_camera_to_world_rotation_matrix(level) * dir * (dt * camera_speed);
            editor.camera_position += camera_movement;

        case .EXTRUDE;
            using editor.extrude;
            world_to_camera := get_editor_camera_matrix(level);
            camera_to_world := inverse(world_to_camera);
            mouse_direction := multiply_homogeneous(camera_to_world, .{mouse.x, mouse.y, 0}) - editor.camera_position;

            parallel, intersection := get_intersection_between_line_and_plane(
                line_point = editor.camera_position,
                line_direction = mouse_direction,
                plane_point = start_intersection,
                plane_normal = to_vector3(plane_normal)
            );

            if parallel {
                end_intersection = start_intersection;
            } else {
                end_intersection = intersection;
            }

        case .DRAG_OLD;
            using editor.drag_old;
            camera_to_world_rotation_matrix := get_editor_camera_to_world_rotation_matrix(level);
            camera_to_world := inverse(get_editor_camera_matrix(level));
            initial_mouse_position := multiply_homogeneous(camera_to_world, .{mouse_start.x, mouse_start.y, 0});
            mouse_position := multiply_homogeneous(camera_to_world, .{mouse.x, mouse.y, 0});
            
            e := get_entity(level, editor.selected);
            selected_position := to_vector3(e.position);

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
                e.position.component[index] = selectable_start.component[index];
            } else {
                movement := intersection.component[index] - initial_intersection.component[index];
                new_position_component := cast(s32, round(cast(float, selectable_start.component[index]) + movement));
                e.position.component[index] = new_position_component;
            }

        case .DRAG;
            using editor.drag;
            camera_to_world_rotation_matrix := get_editor_camera_to_world_rotation_matrix(level);
            camera_to_world := inverse(get_editor_camera_matrix(level));
            mouse_start := multiply_homogeneous(camera_to_world, .{mouse.x, mouse.y, 0});
            mouse_direction := mouse_start - editor.camera_position;


            assert(editor.selected != 0);
            e := get_entity(level, editor.selected);

            normal: Vector3;
            normal.component[index] = 1;

            parallel, point, t := get_intersection_between_line_and_plane(mouse_start, mouse_direction, to_vector3(e.position), normal);
            if !parallel {
                e.position.component[(index + 1) % 3] = xx floor(point.component[(index + 1) % 3]);
                e.position.component[(index + 2) % 3] = xx floor(point.component[(index + 2) % 3]);
            }
    }
    
    FLASH_TIME :: 1;
    if editor.selected {
        editor.selected_timer = fmod_cycling(editor.selected_timer + dt / FLASH_TIME, 1);
    }
}


get_editor_extrude_size :: (using level: *Level) -> position: Vector3i, size: Vector3i {
    assert(editor.mode == .EXTRUDE);
    using editor.extrude;

    start := start_position;
    end := to_vector3i(floor(end_intersection));

    MAX_SIZE :: 40;

    // We cancel out the axis we aren't extruding on.
    // This prevents weird floating-point errors when the plane we're extruding on
    // lines up with the axis and the value of one of the members of end_intersection
    // is either slighty above or below that axis.

    if plane_normal.x != 0 end.x = start.x;
    else if end.x > start.x end.x = min(start.x + MAX_SIZE, end.x);
    else end.x = max(start.x - MAX_SIZE, end.x);

    if plane_normal.y != 0 end.y = start.y;
    else if end.y > start.y end.y = min(start.y + MAX_SIZE, end.y);
    else end.y = max(start.y - MAX_SIZE, end.y);

    if plane_normal.z != 0 end.z = start.z;
    else if end.z > start.z end.z = min(start.z + MAX_SIZE, end.z);
    else end.z = max(start.z - MAX_SIZE, end.z);
    
    min_x, max_x := min_max(start.x, end.x);
    min_y, max_y := min_max(start.y, end.y);
    min_z, max_z := min_max(start.z, end.z);
    
    position := Vector3i.{min_x, min_y, min_z};
    size := Vector3i.{max_x - min_x + 1, max_y - min_y + 1, max_z - min_z + 1};

    return position, size;
}
