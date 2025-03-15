Editor_Mode :: enum {
    IDLE;
    // We can change the selection in this mode. Other modes expect the selection
    // (and camera angle) to be fixed.

    CAMERA; // The camera is moving. DO NOT CHANGE THE SELECTION.

    // Do not allow changing the camera angle or selection in any of the below modes,
    // or else it could mess up what the user is working on.
    EXTRUDE; // We're extruding a gridlike we clicked on
    DRAG;
}


Editor :: struct {
    mode: Editor_Mode;

    union {
        camera: struct {
            rotating_previous_mouse_position: Vector2;
        }

        extrude: struct {
            selected: Entity_Id;
            start_position: Vector3i;
            start_intersection: Vector3;
            end_intersection: Vector3;
            plane_normal: Vector3i;
        }

        drag: struct {
            mouse_start: Vector2;
            selectable_start: Vector3i;
            index: u8;
        }
    }
    
    selected: Entity_Id;
    selected_timer: float;
    
    camera_position := Vector3.{0, 8, -4};
    camera_pitch: float;
    camera_yaw: float;
}


EDITOR_FRUSTUM :: #run -> Matrix4 {
    FOV :: PI / 3;

    right := cast(float, NEAR_PLANE * tan(FOV / 2));
    top := right * cast(float, INNER_WINDOW_H) / cast(float, INNER_WINDOW_W);

    return make_left_handed_frustum_matrix(-right, -top, NEAR_PLANE, right, top, FAR_PLANE);
}


get_editor_camera_matrix :: (ed: *Editor) -> Matrix4 {
    position_matrix := make_translation_matrix4(-ed.camera_position);
    pitch_matrix := make_x_rotation_matrix(Matrix4, -ed.camera_pitch);
    yaw_matrix := make_y_rotation_matrix(Matrix4, -ed.camera_yaw);

    return multiply(EDITOR_FRUSTUM, multiply(pitch_matrix, multiply(yaw_matrix, position_matrix)));
}


get_editor_camera_to_world_rotation_matrix :: (ed: *Editor) -> Matrix3 {
    yaw_matrix := make_y_rotation_matrix(Matrix3, ed.camera_yaw);
    pitch_matrix := make_x_rotation_matrix(Matrix3, ed.camera_pitch);
    return multiply(yaw_matrix, pitch_matrix);
}


editor_handle_input :: (using level: *Level, level_arena: *Memory_Arena, editor: *Editor, mouse: Vector2, event: Input_Event, keys_down: *[Key.COUNT] bool) {
    using context.game_context;

    camera_to_world := inverse(get_editor_camera_matrix(editor));

    if event.key == #char "S" && keys_down.*[Key.CTRL] && event.down {
        serialize_level(level);
        log(.OK, "Serialized level.\n");
        return;
    }

    if editor.mode == {
        case .IDLE;
            mouse_start := editor.camera_position;
            mouse_end := multiply_homogeneous(camera_to_world, .{mouse.x, mouse.y, 1});
            mouse_direction := mouse_end - mouse_start;

            if (event.key == .MOUSE_RIGHT_BUTTON || event.key == xx #char " ") && event.down {
                editor.mode = .CAMERA;
                editor.camera = .{
                    rotating_previous_mouse_position = mouse
                };
                return;
            }
            
            // Check to see if the camera is moving
            if event.down 
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
            
            if event.key == #char "X" && event.down {
                mouse_start := editor.camera_position;
                mouse_end := multiply_homogeneous(camera_to_world, .{mouse.x, mouse.y, 1});

                Data :: struct {
                    level: *Level;
                    arena: *Memory_Arena;
                    editor: *Editor;
                }

                visitor :: (position: Vector3i, using d: *Data) -> bool {
                    remove_gridlike_cell :: (entities: [] $T) #expand {
                        for * entities {
                            success, index := get_3d_index(position, it.position, it.size);
                            if !success || !it.filled[index] continue;

                            it.filled[index] = false;

                            all_zero := true;
                            new_position: Vector3i;
                            new_end: Vector3i;

                            for :iterate_vector3i v: it.size {
                                filled := it.filled[it_index];
                                if !filled continue;
                                cell_position := v + it.position;
                                
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
                                if it.eid == editor.selected editor.selected = 0;
                                delete_entity(level, it.eid, arena);
                            } else {
                                new_size := new_end - new_position + Vector3i.{1,1,1};
                                if it.size != new_size {
                                    new_filled := alloc_view(arena, new_size.x * new_size.y * new_size.z, bool);
                                    for :iterate_vector3i v: new_size {
                                        success, src_index := get_3d_index(v + new_position, it.position, it.size);
                                        assert(success);
                                        new_filled[it_index] = it.filled[src_index];
                                    }

                                    it.filled = new_filled;
                                    it.position = new_position;
                                    it.size = new_size;
                                }

                                update_gridlike_mesh(it, arena);
                            }
                            `return true;
                        }

                    }

                    remove_gridlike_cell(level._Block);
                    remove_gridlike_cell(level._Door);
                    return false;
                }
                
                data := Data.{ level=level, editor=editor, arena=level_arena };
                raycast(mouse_start, mouse_end, visitor, *data);
                return;
            }
            
            if event.key == xx #char "Z" && event.down {
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

                    if keys_down.*[Key.SHIFT] {
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

                    filled := alloc_view(level_arena, 1, bool);
                    filled[0] = true;
                    size := Vector3i.{1, 1, 1};

                    block := make_entity(level, Block, level_arena);
                    block.size = size;
                    block.position = .{xx floor(point.x), 0, xx floor(point.z)};
                    block.filled = filled;
                    block.color = .{1, 1, 1, 1};
                    block.mesh = make_block_mesh(size, filled, level_arena);

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


            if event.key == .MOUSE_LEFT_BUTTON && event.down {
                success, selected, intersection := get_intersection_with_selectable_meshes(level, editor, mouse_start, mouse_end);
                
                if success {
                    editor.selected = selected;
                    editor.selected_timer = 0;
                } else {
                    editor.selected = 0;
                }

                return;
            }

            if (event.key == .BACKSPACE || event.key == .DELETE) && event.down {
                delete_entity(level, editor.selected, level_arena);
                editor.selected = 0;
                return;
            }
            
            enable_drag :: (index: u8) #expand {
                if editor.selected {
                    e := get_entity(level, editor.selected);
                    editor.mode = .DRAG;
                    editor.drag = .{
                        mouse_start = mouse,
                        selectable_start = e.position,
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

            if (.F_BASE < event.key && event.key < Key.F_BASE + 1 + ENTITIES.count) && event.down {
                success, _, intersection := get_intersection_with_selectable_meshes(level, editor, mouse_start, mouse_end);
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
                e := make_entity(level, index, level_arena);
                e.position = position;


                init_grid_entity :: (e: *$T) #expand {
                    filled := alloc_view(level_arena, 1, bool);
                    filled[0] = true;

                    e.size = .{1, 1, 1};
                    e.filled = filled;
                    e.mesh = make_gridlike_mesh(.{1, 1, 1}, filled, level_arena);
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

            if event.key == #char " " && event.down && !keys_down.*[Key.MOUSE_RIGHT_BUTTON] {
                rotating_previous_mouse_position = mouse;
                return;
            }

            if event.key == .MOUSE_RIGHT_BUTTON && event.down && !keys_down.*[#char " "] {
                rotating_previous_mouse_position = mouse;
                return;
            }

            if !keys_down.*[#char "W"]
            && !keys_down.*[#char "S"]
            && !keys_down.*[#char "A"]
            && !keys_down.*[#char "D"]
            && !keys_down.*[#char "Q"]
            && !keys_down.*[#char "E"] 
            && !keys_down.*[#char " "] 
            && !keys_down.*[Key.MOUSE_RIGHT_BUTTON] {
                // The user has released all keys.
                // :AltTab this might not be true on Windows.
                editor.mode = .IDLE;
            }
            
        case .EXTRUDE;
            using editor.extrude;
            if event.key == #char " " && event.down {
                for plane_normal.component {
                    if it == 1 {
                        plane_normal.component[it_index] = 0;
                        plane_normal.component[(it_index + 1) % plane_normal.component.count] = 1;
                        break;
                    }
                }
            } else if event.key == #char "Z" && !event.down {
                position, size := get_editor_extrude_size(editor);
                extrude_gridlike_entity :: (e: $T) #expand {
                    e.position, e.size, e.filled = realloc_3d_array_to_fit_subarea(e.position, e.size, e.filled, position, size, level_arena);
                    offset := position - e.position;

                    for :iterate_vector3i size {
                        gridlike_position := it + offset;
                        success, index := get_3d_index(gridlike_position, e.size);
                        assert(success);
                        e.filled[index] = true;
                    }
                    update_gridlike_mesh(e, level_arena);
                }

                e := get_entity(level, selected);
                if e.type == .Block {
                    extrude_gridlike_entity(as(e, Block));
                } else if e.type == .Door {
                    extrude_gridlike_entity(as(e, Door));
                } else assert(false);

                editor.mode = .IDLE;
            }

        case .DRAG;
            using editor.drag;
            if !event.down && ((index == 0 && event.key == xx #char "1")
                            || (index == 1 && event.key == xx #char "2")
                            || (index == 2 && event.key == xx #char "3")) {
                // @TODO: change level_position or level_size to accomadate the new position.
                editor.mode = .IDLE;
            }
    }
}


get_intersection_with_selectable_meshes :: (using level: *Level, editor: *Editor, line_start: Vector3, line_end: Vector3) -> bool, Entity_Id, intersection: Vector3 { 
    line_direction := line_end - line_start;
    smallest_t := FLOAT32_INFINITY;
    selected_found := false;
    selected: Entity_Id;
    selected_intersection: Vector3;
    
    for :iterate_entities e: types {
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


editor_update :: (using level: *Level, editor: *Editor, mouse: Vector2, keys_down: *[Key.COUNT] bool, dt: float) {
    using context.game_context;

    if editor.mode == {
        case .CAMERA;
            using editor.camera;
            if keys_down.*[#char " "] || keys_down.*[Key.MOUSE_RIGHT_BUTTON] {
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
            if keys_down.*[Key.SHIFT] camera_speed = CAMERA_FAST_SPEED;

            x := cast(int, keys_down.*[#char "D"]) - cast(int, keys_down.*[#char "A"]);
            y := cast(int, keys_down.*[#char "Q"]) - cast(int, keys_down.*[#char "E"]);
            z := cast(int, keys_down.*[#char "W"]) - cast(int, keys_down.*[#char "S"]);
            dir := Vector3.{xx x, xx y, xx z};

            camera_movement := get_editor_camera_to_world_rotation_matrix(editor) * dir * (dt * camera_speed);
            editor.camera_position += camera_movement;

        case .EXTRUDE;
            using editor.extrude;
            world_to_camera := get_editor_camera_matrix(editor);
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

        case .DRAG;
            using editor.drag;
            camera_to_world_rotation_matrix := get_editor_camera_to_world_rotation_matrix(editor);
            camera_to_world := inverse(get_editor_camera_matrix(editor));
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
    }
    
    FLASH_TIME :: 1;
    if editor.selected {
        editor.selected_timer = fmod_cycling(editor.selected_timer + dt / FLASH_TIME, 1);
    }
}


get_editor_extrude_size :: (editor: *Editor) -> position: Vector3i, size: Vector3i {
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
