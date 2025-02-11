Level :: struct {
    selectables: Fixed_Array(32, *Selectable);
    
    blocks: Fixed_Array(32, Block);
    player: Player;
    
    entrance: Selectable;
    exit:     Selectable;
    
    // These are gameplay-only variables. In the future, we might want to better-differentiate
    // between what is modifiable in the editor (which should be as close as we can get to a 
    // pure-data representation of the scene) and what is gameplay state. We could use
    // metaprogramming to do this but it seems like overkill right now.

    flags: enum {PULLING :: 1;};
    
    camera_pitch_ticks: s8 = 1;
    camera_yaw_ticks: s8;

    collision: Collision;
}


CAMERA_PITCH_TICK_COUNT :: 5; // Starts at zero
CAMERA_MIN_PITCH :: -PI / 3;
CAMERA_MAX_PITCH :: PI / 3;

CAMERA_YAW_TICK_COUNT :: 12;

Selectable :: struct {
    position: Vector3i;
    mesh: Mesh;
}


Player :: Selectable;


Block :: struct {
    using #as selectable: Selectable;

    size: Vector3i;
    filled: [] bool;
    color: Vector4;
    moveable: bool;
    // @TODO Make a bit array data structure for better cache coherency

}


// This solely exists as a convenience so I can type blocks into the editor for now.
Temporary_Block :: struct {
    position: Vector3i;
    size: Vector3i;
    filled: [] bool;
    color: Vector4;
    moveable: bool;
}



Collision :: struct {
    position: Vector3i;
    size: Vector3i;

    filled: [] *Block;
    viewed: [] View_State;
    // This is stored SOA because we don't want to touch these at the same time.
    // @TODO This is stored x-major, then z, then y.
    // This makes sense from the perspective of wanting to be
    // able to type levels directly into code for this initial
    // development period, but may make less sense later.
    // Consider coming back to this.

    texture: Collision_Texture;
}


View_State :: enum_flags u8 { // @Volatile :ViewState
    SEEN;
    VISIBLE;
    
    QUEUED_FOR_FLOODFILL;
}


get_block_extents :: (blocks: [] Block) -> position: Vector3i, size: Vector3i {
    if blocks.count == 0 return .{}, .{};
    start := blocks[0].position;
    end := start + blocks[0].size;

    for 1..blocks.count-1 {
        block := *blocks[it];
        start = min(start, block.position);
        end = max(end, block.position + block.size);
    }

    size := end - start;
    
    return start, size;
}


// Fits to the given blocks. DOES NOT INSERT THEM INTO THE COLLISION MAP.
make_collision :: (blocks: [] Block, arena: *Memory_Arena) -> Collision {
    position, size := get_block_extents(blocks);

    size_1d := size.x * size.y * size.z;
    
    return .{
        position = position,
        size = size,
        filled = arena_alloc_array(arena, size_1d, *Block),
        viewed = arena_alloc_array(arena, size_1d, View_State),
        texture = make_collision_texture(size)
    };
}


get_block :: (col: *Collision, position: Vector3i) -> in_bounds: bool, block: *Block {
    success, index := get_3d_index(position, col.position, col.size);
    if !success return false, null;
    return true, col.filled[index];
}


Add_Block_Result :: enum {
    OK;
    OUT_OF_BOUNDS;
    CELL_ALREADY_OCCUPIED;
}


add_block_to_collision :: (col: *Collision, block: *Block) -> Add_Block_Result {
    offset := block.position - col.position;
    end := offset + block.size;
    if !inside_positive_bounding_box(offset, col.size) return .OUT_OF_BOUNDS;
    if (end.x < 0 || col.size.x < end.x ||
        end.x < 0 || col.size.x < end.x ||
        end.x < 0 || col.size.x < end.x ) return .OUT_OF_BOUNDS;

    // @Speed we could just detect when the failure happens and unwind what we've
    // already added instead of first checking, then adding.

    for :iterate_vector3i block.size {
        filled := block.filled[it_index];
        if !filled continue;
        collision_coord := it + offset;
        success, collision_index := get_3d_index(collision_coord, col.size);
        block_already_there := col.filled[collision_index];
        if block_already_there return .CELL_ALREADY_OCCUPIED;
    }

    for :iterate_vector3i block.size {
        filled := block.filled[it_index];
        if !filled continue;
        collision_coord := it + offset;
        collision_index := get_3d_index_unchecked(collision_coord, col.size);
        col.filled[collision_index] = block;
    }

    return .OK;
}


// @Speed @TODO: When we add the player seeing mechanic, we want to have this routine know about Collision and do some early-out checks and possibly automatically do index conversion because this is going to get called hundreds of times every frame.
raycast :: (ray_start: Vector3, ray_end: Vector3, $visitor: (position: Vector3i, user_data: $T) -> terminate_raycast: bool, user_data: T, wiggle_room := Vector3.{}/*, projection := Matrix4_Identity*/) -> collided: bool {
    raycast_x :: (y_plane: s32, z_plane: s32, ray_start_x: float, ray_end_x: float, user_data: T) -> bool {
        x_steps := cast(s32, floor(ray_end_x) - floor(ray_start_x));

        x := cast(s32, floor(ray_start_x));
        start := Vector3i.{x, y_plane, z_plane};
        if inline visitor(start, user_data) return true;

        i : s32 = 0;
        dir := cast(s32, sign(x_steps));
        while i != x_steps {
            i += dir;
            start.x += dir;

            if inline visitor(start, user_data) return true;
        }

        return false;
    }


    raycast_zx :: (y_plane: s32, ray_start_x: float, ray_start_z: float, ray_end_x: float, ray_end_z: float, user_data: T) -> bool {
        z_steps := cast(s32, floor(ray_end_z) - floor(ray_start_z));

        if z_steps == 0 {
            return raycast_x(y_plane, xx floor(ray_start_z), ray_start_x, ray_end_x, user_data);
        } else {
            m := (ray_end_x - ray_start_x) / (ray_end_z - ray_start_z);
            b := ray_start_x - m * ray_start_z;
            
            z_plane := cast(s32, floor(ray_start_z));
            z := z_plane + cast(s32, z_steps > 0);

            x := m * z + b;

            if raycast_x(y_plane, z_plane, ray_start_x, x, user_data) return true;
            
            i := 0;
            dir := sign(z_steps);
            range_end := z_steps - dir; // Every cube except the last one

            while i != range_end {
                i += dir;
                z_plane += dir;
                z += dir;
                old_x := x;
                x = m * z + b;
                if raycast_x(y_plane, z_plane, old_x, x, user_data) return true;
            }
            
            z_plane += dir;
            return raycast_x(y_plane, z_plane, x, ray_end_x, user_data);
        }
    }
    
    y_steps := cast(s32, floor(ray_end.y) - floor(ray_start.y));
    
    wiggle_room_z := sign(ray_end.z - ray_start.z) * wiggle_room.z;

    if y_steps == 0 {
        if raycast_zx(xx floor(ray_start.y), ray_start.x, ray_start.z, ray_end.x, ray_end.z, user_data) return true;
        return false;
    } else {
        ray_length := ray_end - ray_start;

        y_plane := cast(s32, floor(ray_start.y));
        y := y_plane + cast(s32, y_steps > 0);
        t := (y - ray_start.y) / ray_length.y;

        x := ray_start.x + ray_length.x * t;
        z := ray_start.z + ray_length.z * t;

        if raycast_zx(y_plane, ray_start.x, ray_start.z, x, z, user_data) return true;
        
        i := 0;
        dir := sign(y_steps);
        range_end := y_steps - dir;
        while i != range_end {
            i += dir;
            y_plane += dir;
            y += dir;
            t := (y - ray_start.y) / ray_length.y;
            old_x := x;
            old_z := z;
            x = ray_start.x + ray_length.x * t;
            z = ray_start.z + ray_length.z * t;
            
            // If z and old_z are really close together
            // (the ray is almost straight along the z-axis)
            // then, the start_z and end_z values might be swapped.
            // This is probably fine, because the ray will still
            // be almost straight.

            start_z := old_z + wiggle_room_z;
            end_z := z - wiggle_room_z;
            
            // draw_arrow(.{old_x, xx y_plane, start_z}, .{x, xx (y_plane + 1), end_z}, .{1, 0, 0, 1}, *projection);

            if raycast_zx(y_plane, old_x, start_z, x, end_z, user_data) return true;
        }

        y_plane += dir;
        if raycast_zx(y_plane, x, z, ray_end.x, ray_end.z, user_data) return true;
        return false; // We made it to the end of the raycast.
    }
}


remove_block_from_collision :: (col: *Collision, block: *Block) {
    for :iterate_vector3i block.size {
        filled := block.filled[it_index];
        if !filled continue;
        absolute_coord := block.position + it;
        collision_coord := absolute_coord - col.position;

        collision_index := get_3d_index_unchecked(collision_coord, col.size);
        block_already_there := col.filled[collision_index];
        assert(block_already_there == block);
        col.filled[collision_index] = null;
    }
}


get_gameplay_camera_matrix :: (using level: *Level) -> Matrix4 {
    camera_offset := Vector3.{0, 0, 12};
    offset_matrix := make_translation_matrix4(camera_offset);
    
    position_matrix := make_translation_matrix4(-to_vector3(player.position) - Vector3.{0.5, 0.5, 0.5});

    pitch := lerp(CAMERA_MIN_PITCH, CAMERA_MAX_PITCH, cast(float, camera_pitch_ticks) / cast(float, CAMERA_PITCH_TICK_COUNT));
    pitch_matrix := make_x_rotation_matrix(Matrix4, -pitch);

    yaw_matrix := make_y_rotation_matrix(Matrix4, -get_camera_yaw(level));
    
    return multiply(FRUSTUM, multiply(offset_matrix, multiply(pitch_matrix, multiply(yaw_matrix, position_matrix))));
}


get_camera_yaw :: (using level: *Level) -> float {
    return TAU * cast(float, camera_yaw_ticks) / cast(float, CAMERA_YAW_TICK_COUNT);
}


update_level_visibility :: (using level: *Level) {
    // The following code is nontrivial so I will write an explanation.
    // We are using a variant of the naive version of floodfill where you try to fill all the cells adjacent to you.
    // Here's why:
    // A cell will only be visible if it has at least one neighboring cell that is visible.
    // That means if a raycast fails, we can stop propagating the raycast early. This might be premature optimization
    // because in our worst-cast scenario you will have to check most of the cells in the level anyway.
    // The QUEUED_FOR_FLOODFILL bit exists to tell us that a cell is already on the floodfill stack.
    // This prevents many copies of the same cell from ending up on the floodfill stack and blowing up memory.
    
    // @Speed So, this is our first real reality check of this game.
    // Running this on a 20x20x20 level already starts to lag out the game.
    // For this initial development period this is fine, but we will soon have levels bigger than that.
    // Rather than optimizing CPU floodfill, the best solution might to be to run it as a compute shader.

    //      -berk, 2 - 3 - 2025


    for :iterate_vector3i collision.size {
        collision.viewed[it_index] &= ~(.VISIBLE | .QUEUED_FOR_FLOODFILL);
    }
    
    using context.game_context;

    mark := get_mark(*frame_arena);
    defer restore_mark(*frame_arena, mark);
    positions := arena_alloc_array(*frame_arena, collision.size.x * collision.size.y * collision.size.z, struct {index: s64; position: Vector3i;}, zero_init=false);
    position_count := 1;

    player_success, player_index := get_3d_index(player.position, collision.position, collision.size);
    assert(player_success);
    positions[0] = .{player_index, player.position};
    collision.viewed[player_index] |= .QUEUED_FOR_FLOODFILL;
    
    end := to_vector3(player.position) + Vector3.{0.5, 0.5, 0.5};
    while position_count != 0 {
        position_count -= 1;
        using index_and_position := positions[position_count];

        visitor :: (position: Vector3i, collision: *Collision) -> terminate_raycast: bool {
            success, index := get_3d_index(position, collision.position, collision.size);
            if !success return false;
            return collision.filled[index] != null;
        }
        
        start := to_vector3(position) + Vector3.{0.5, 0.5, 0.5};
        
        projection := get_gameplay_camera_matrix(level);

        WIGGLE_ROOM :: Vector3.{0.01, 0.01, 0.01};
        if raycast(start, end, visitor, *collision, wiggle_room=WIGGLE_ROOM/*, projection=get_gameplay_camera_matrix(level)*/) continue;

        collision.viewed[index] |= (.SEEN | .VISIBLE);

        px := position; px.x += 1;
        nx := position; nx.x -= 1;
        py := position; py.y += 1;
        ny := position; ny.y -= 1;
        pz := position; pz.z += 1;
        nz := position; nz.z -= 1;
       
        check_position :: (p: Vector3i) #expand {
            success, index := get_3d_index(p, `collision.position, collision.size);
            if !success return;

            if collision.filled[index] || (collision.viewed[index] & .QUEUED_FOR_FLOODFILL) return;
            
            collision.viewed[index] |= .QUEUED_FOR_FLOODFILL;
            `positions[`position_count] = .{index, p};
            position_count += 1;
        }
        
        check_position(px);
        check_position(nx);
        check_position(py);
        check_position(ny);
        check_position(pz);
        check_position(nz);
    }

    update_collision_texture(*collision);
}


make_level_for_editor :: (using level: *Level, level_arena: *Memory_Arena) {
    // @Speed maybe we can just set what we need to be reset in case
    // this is a reused pointer from an old level. I am going to
    // zero-init everything right now to prevent bugs.
    level.* = .{};

    T :: true;
    F :: false;
    
    entrance = .{
        position = .{-3, 0, -2},
        mesh = make_cuboid_vertex_mesh(.{0.15, 0, 0.15}, .{0.85, 0.1, 0.85}, level_arena)
    };
    
    exit = .{
        position = .{2, 0, -1},
        mesh = make_cuboid_vertex_mesh(.{0.15, 0, 0.15}, .{0.85, 0.1, 0.85}, level_arena)
    };
    
    player = .{
        position = entrance.position,
        mesh = make_cuboid_vertex_mesh(.{0.2, 0.2, 0.2}, .{0.8, 0.8, 0.8}, level_arena)
    };

    assert(append(*selectables, *entrance));
    assert(append(*selectables, *exit));
    assert(append(*selectables, *player));

    temp_blocks := Temporary_Block.[
        .{
            position = .{-3, -1, -2},
            size = .{6, 1, 8},
            filled = .[
                T, T, T, T, T, T,
                T, T, T, T, T, T,
                T, T, T, T, T, T,
                T, T, T, T, T, T,
                T, T, T, T, T, T,
                T, T, T, T, T, T,
                T, T, T, T, T, T,
                T, T, T, T, T, T,
            ],
            color = .{163.0/255.0, 176.0/255.0, 183.0/255.0, 1},
            moveable = false
        },
        .{
            position = .{-3, 0, -2},
            size = .{6, 1, 2},
            filled = .[
                F, F, F, F, T, T,
                T, T, F, T, T, F, 
            ],
            color = .{204.0/255.0, 206.0/255.0, 207.0/255.0, 1},
            // .{1, 143.0/255.0, 0, 1} Orange color that I liked
            moveable = false
        },
        .{
            position = .{-1, 0, 4},
            size = .{1, 2, 1},
            filled = .[
                T,
                T,
            ],
            color = .{0, 0, 1, 1},
            moveable = true
        }
    ];

    for * temp_blocks {
        using it;
        filled_allocated := arena_alloc_array(level_arena, filled.count, bool);
        memcpy(filled_allocated.data, filled.data, size_of(type_of(filled.data.*)) * filled.count);

        block := append(*blocks);
        assert(block != null);
        
        generated_mesh := make_block_mesh(size, filled_allocated, level_arena);

        block.* = .{
           position = position,
           size = size,
           filled = filled_allocated,
           color = color,
           moveable = moveable,
           mesh = generated_mesh
        };
        
        assert(append(*selectables, block));
    }
}


make_level_for_game :: (using level: *Level, level_arena: *Memory_Arena) {
    make_level_for_editor(level, level_arena);

    collision = make_collision(to_array(blocks), level_arena);
    for * blocks {
        assert(add_block_to_collision(*collision, it) == .OK);
    }
}



free_level :: (using level: *Level, level_arena: *Memory_Arena) {   
    // @TODO This is a far-in-the-future kind of thing.
    // We should wrap glGenBuffers, glDeleteBuffers, and similar allocating functions and make a memory debugger
    // that tells us what has leaked when we close the application, because as far as I can tell, there's no good
    // way to natively get that information from OpenGL.

    free(*collision.texture);

    free(*player.mesh);
    free(*entrance.mesh);
    free(*exit.mesh);

    for blocks {
        free(*it.mesh);
    }

    clear_arena(level_arena);
}


level_handle_input :: (using level: *Level, level_arena: *Memory_Arena, event: Input_Event) { 
    if event.key == #char " " {
        if event.down flags |= .PULLING;
        else          flags &= ~.PULLING;
    } else if event.key == #char "K" && event.down {
        camera_pitch_ticks = max(camera_pitch_ticks - 1, 0);
    } else if event.key == #char "I" && event.down {
        camera_pitch_ticks = min(camera_pitch_ticks + 1, CAMERA_PITCH_TICK_COUNT);
    } else if event.key == #char "L" && event.down {
        camera_yaw_ticks = (camera_yaw_ticks - 1 + CAMERA_YAW_TICK_COUNT) % CAMERA_YAW_TICK_COUNT;
    } else if event.key == #char "J" && event.down {
        camera_yaw_ticks = (camera_yaw_ticks + 1) % CAMERA_YAW_TICK_COUNT;
    } else {
        if !event.down return;
        push_direction: Vector3i;

        move :: (direction: Vector2) #expand {
            rotated := rotate(direction, get_camera_yaw(level));
            if abs(rotated.x) > abs(rotated.y) {
                push_direction.x += cast(s32, sign(rotated.x));
            } else {
                push_direction.z += cast(s32, sign(rotated.y));
            }
        }

        if event.key == {
            case xx #char "W"; move(.{0, 1});
            case xx #char "A"; move(.{-1, 0});
            case xx #char "S"; move(.{0, -1});
            case xx #char "D"; move(.{1, 0});
            case xx #char "Q"; push_direction.y += 1;
            case xx #char "E"; push_direction.y -= 1;
            case; return;

        }
        
        new_player_position := player.position + push_direction;

        
        // This code took a while to put together and likely is only going to get more complex.

        // When the player moves, either the entire move needs to succeed at once or fail at once.
        // When the player pushes or pulls a block, a lot about the game state needs to change.
        // If we're trying to update the game state and we find out that the move the player is
        // trying to make is illegal, then we need to undo all the changes we made to the game
        // state while determining if that move is legal.

        // Right now, I am just removing all the blocks from the collision map, updating them,
        // re-adding them to the collision map, and undoing all of that if it turns out one of
        // the blocks is overlapping with something.
        
        // If we are not _very_ careful, this could get messy really quickly.
        // Possibly consider investigating an alternate strategy that does not touch the core
        // game state until we _know_ we can make a move, then do the update.

        //          -berk, 22 - 1 - 2025.

        // @TODO Add pulling blocks next to you, not just in the opposite direction of where
        // you are moving (I'm pretty sure we want this)

        moving_blocks: Fixed_Array(2, *Block);
        
        pushed_in_bounds, pushed_block := get_block(*collision, new_player_position);
        if !pushed_in_bounds return;

        if pushed_block {
            if !pushed_block.moveable return;
            assert(append(*moving_blocks, pushed_block));
        }

        if flags & .PULLING {
            pulled_in_bounds, pulled_block := get_block(*collision, player.position - push_direction);
            if pulled_in_bounds && pulled_block && pulled_block.moveable && !contains(*moving_blocks, pulled_block) {
                assert(append(*moving_blocks, pulled_block));
            }
        }
        
        for moving_blocks {
            remove_block_from_collision(*collision, it);
        }

        move_failed := false;
        for moving_blocks {
            it.position += push_direction;
            if add_block_to_collision(*collision, it) != .OK {

                // Undo everything we just tried to do
                it.position -= push_direction;
                for #v2 < 0..it_index-1 {
                    block := moving_blocks[it];
                    remove_block_from_collision(*collision, block);
                    block.position -= push_direction;
                }

                for moving_blocks {
                    assert(add_block_to_collision(*collision, it) == .OK);
                }

                move_failed = true;
                break;
            }
        }

        if !move_failed {
            player.position = new_player_position;
            if player.position == exit.position {
                free_level(level, level_arena);
                make_level_for_game(level, level_arena);
            }
        }
    }
}


