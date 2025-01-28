Level :: struct {
    blocks: Fixed_Array(32, Block);
    
    player_position: Vector3i;
    flags: enum {PULLING :: 1;};
    
    camera_position: Vector3;
    camera_projection: Matrix4;

    collision: Collision;
}


Collision :: struct {
    position: Vector3i;
    size: Vector3i;

    filled: [] *Block;
    // @TODO This is stored x-major, then z, then y.
    // This makes sense from the perspective of wanting to be 
    // able to type levels directly into code for this initial
    // development period, but may make less sense later.
    // Consider coming back to this.
    // @TODO Implement a bit array for better cache coherency.
}


Block :: struct {
    position: Vector3i;
    size: Vector3i;
    filled: [] bool;
    color: Vector4;
    moveable: bool;
    // @TODO Pregenerate the mesh for the block and upload it to the GPU
    // @TODO Make a bit array data structure for better cache coherency
}

get_block :: (col: *Collision, position: Vector3i) -> in_bounds: bool, block: *Block {
    local_position := position - col.position;
    if local_position.x < 0 || col.size.x <= local_position.x
    || local_position.y < 0 || col.size.y <= local_position.y
    || local_position.z < 0 || col.size.z <= local_position.z {
        return false, null;
    }
    
    index := convert_3d_coordinate_to_index(local_position, col.size);
    return true, col.filled[index];
}


make_collision :: (level_arena: *Memory_Arena) -> Collision {
    START :: Vector3i.{-10, -10, -10};
    END :: Vector3i.{10, 10, 10};
    size := END - START;
    collision_array_size := size.x * size.y * size.z;

    success, collision_memory := arena_alloc_array(level_arena, collision_array_size, *Block);
    assert(success);

    return Collision.{
        position = START,
        size = size,
        filled = collision_memory
    };
}


add_block_to_collision :: (col: *Collision, block: *Block) -> bool {
    if block.position.x < col.position.x return false;
    if block.position.y < col.position.y return false;
    if block.position.z < col.position.z return false;
    if block.position.x + block.size.x > col.position.x + col.size.x return false;
    if block.position.y + block.size.y > col.position.y + col.size.y return false;
    if block.position.z + block.size.z > col.position.z + col.size.z return false;
    
    offset := block.position - col.position;

    // @Speed we could just detect when the failure happens and unwind what we've
    // already added instead of first checking, then adding.
    
    for :iterate_vector3i block.size {
        filled := block.filled[it_index];
        if !filled continue;
        collision_coord := it + offset;
        collision_index := convert_3d_coordinate_to_index(collision_coord, col.size);
        block_already_there := col.filled[collision_index];
        if block_already_there return false;
    }

    for :iterate_vector3i block.size {
        filled := block.filled[it_index];
        if !filled continue;
        collision_coord := it + offset;
        collision_index := convert_3d_coordinate_to_index(collision_coord, col.size);
        col.filled[collision_index] = block;
    }

    return true;
}

// Raycast :: struct {start: Vector3; end: Vector3;}
// raycast :: (ray: Raycast, body: Code, for_flags: For_Flags) #expand {
raycast :: (ray_start: Vector3, ray_end: Vector3, $visitor: (position: Vector3, user_data: $T), user_data: T) {
    raycast_x :: (y_plane: float, z_plane: float, ray_start_x: float, ray_end_x: float, user_data: T) {
        x_steps := cast(s32, floor(ray_end_x) - floor(ray_start_x));

        x := floor(ray_start_x);
        start := Vector3.{x, y_plane, z_plane};
        inline visitor(start, user_data);

        i : s32 = 0;
        dir := cast(s32, sign(x_steps));
        while i != x_steps {
            i += dir;
            start.x += dir;

            inline visitor(start, user_data);
        }
    }


    raycast_zx :: (y_plane: float, ray_start_x: float, ray_start_z: float, ray_end_x: float, ray_end_z: float, user_data: T) {
        z_steps := cast(s32, floor(ray_end_z) - floor(ray_start_z));

        if z_steps == 0 {
            raycast_x(y_plane, floor(ray_start_z), ray_start_x, ray_end_x, user_data);
        } else {
            m := (ray_end_x - ray_start_x) / (ray_end_z - ray_start_z);
            b := ray_start_x - m * ray_start_z;
            
            z_plane := floor(ray_start_z);
            z := z_plane + cast(s32, z_steps > 0);

            x := m * z + b;

            raycast_x(y_plane, z_plane, ray_start_x, x, user_data);
            
            i := 0;
            dir := sign(z_steps);
            range_end := z_steps - dir; // Every cube except the last one

            while i != range_end {
                i += dir;
                z_plane += dir;
                z += dir;
                old_x := x;
                x = m * z + b;
                raycast_x(y_plane, z_plane, old_x, x, user_data);
            }
            
            z_plane += dir;
            raycast_x(y_plane, z_plane, x, ray_end_x, user_data);
        }
    }
    
    y_steps := cast(s32, floor(ray_end.y) - floor(ray_start.y));
    
    if y_steps == 0 {
        raycast_zx(floor(ray_start.y), ray_start.x, ray_start.z, ray_end.x, ray_end.z, user_data);
    } else {
        ray_length := ray_end - ray_start;

        y_plane := floor(ray_start.y);
        y := y_plane + cast(s32, y_steps > 0);
        t := (y - ray_start.y) / ray_length.y;

        x := ray_start.x + ray_length.x * t;
        z := ray_start.z + ray_length.z * t;

        raycast_zx(y_plane, ray_start.x, ray_start.z, x, z, user_data);
        
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

            raycast_zx(y_plane, old_x, old_z, x, z, user_data);
        }

        y_plane += dir;
        raycast_zx(y_plane, x, z, ray_end.x, ray_end.z, user_data);
    }
}


remove_block_from_collision :: (col: *Collision, block: *Block) {
    for :iterate_vector3i block.size {
        filled := block.filled[it_index];
        if !filled continue;
        absolute_coord := block.position + it;
        collision_coord := absolute_coord - col.position;

        collision_index := convert_3d_coordinate_to_index(collision_coord, col.size);
        block_already_there := col.filled[collision_index];
        assert(block_already_there == block);
        col.filled[collision_index] = null;
    }
}


add_block_to_level :: (level: *Level, level_arena: *Memory_Arena, position: Vector3i, size: Vector3i, filled: [] bool, color: Vector4, moveable: bool) {
     assert(position.x >= level.collision.position.x
            && position.y >= level.collision.position.y
            && position.z >= level.collision.position.z);
     assert(position.x + size.x < level.collision.position.x + level.collision.size.x
            && position.y + size.y < level.collision.position.y + level.collision.size.y
            && position.z + size.z < level.collision.position.z + level.collision.size.z);

     assert(size.x * size.y * size.z == filled.count);
    
     // Do we need more elegant failure cases here?

     success, filled_allocated := arena_alloc_array(level_arena, filled.count, bool);
     assert(success);
     memcpy(filled_allocated.data, filled.data, size_of(type_of(filled.data.*)) * filled.count);

     block := append(*level.blocks);
     assert(block != null);
    
     block.* = .{
        position = position,
        size = size,
        filled = filled_allocated,
        color = color,
        moveable = moveable
     };

     assert(add_block_to_collision(*level.collision, block));
}


init_camera :: (using l: *Level) {
    FOV :: PI / 3;
    NEAR :: 0.1;

    right := cast(float, NEAR * tan(FOV / 2));
    top := right * cast(float, INNER_WINDOW_H) / cast(float, INNER_WINDOW_W);
    
    rotation := make_x_rotation_matrix4(xx (PI / 3));
    frustum  := make_left_handed_frustum_matrix(-right, -top, NEAR, right, top, 1000);

    camera_projection = multiply(frustum, rotation);
    camera_position = .{0, 8, -4};
}


test_game_level_init :: (level: *Level, level_arena: *Memory_Arena) {
    T :: true;
    F :: false;
     
    level.player_position = .{0, 0, -1};
    level.collision = make_collision(level_arena);
    init_camera(level);

    add_block_to_level(level, level_arena, 
        position = .{-3, -1, -2},
        size = .{6, 1, 4},
        filled = .[
            T, T, T, T, T, T,
            T, T, T, T, T, T,
            T, T, T, T, T, T,
            T, T, T, T, T, T
        ],
        color = .{1, 0, 0, 1},
        moveable = false
    );
    
    add_block_to_level(level, level_arena, 
        position = .{-3, 0, -2},
        size = .{6, 1, 4},
        filled = .[
            F, F, F, F, F, T,
            T, F, F, F, F, F, 
            F, F, F, F, F, F,
            T, T, T, T, T, T
        ],
        color = .{1, 143.0/255.0, 0, 1},
        moveable = false
    );

    add_block_to_level(level, level_arena, 
        position = .{-1, 0, -2},
        size = .{3, 1, 2},
        filled = .[
            T, T, T,
            T, F, T
        ],
        color = .{0, 0, 1, 1},
        moveable = true
    );
    /* 
    block_3 := append(*blocks);
    block_3.* = .{
        position = .{-1, 0, 0},
        size = .{3, 1, 1},
        filled = .[T, T, T],
        color = .{0, 0.5, 0, 1},
        moveable = true
    };
    */
}


test_editor_level_init :: (level: *Level, level_arena: *Memory_Arena) {
    T :: true;
    F :: false;

    level.player_position = .{0, 0, -1};
    level.collision = make_collision(level_arena);
    init_camera(level);

    add_block_to_level(level, level_arena, 
        position = .{-3, -1, -2},
        size = .{6, 1, 4},
        filled = .[
            T, T, T, T, T, T,
            T, T, T, T, T, T,
            T, T, T, T, T, T,
            T, T, T, T, T, T
        ],
        color = .{0, 0, 0.5, 1},
        moveable = false
    );
}


level_update :: (using level: *Level, event: Input_Event) { 
    if event.key == #char " " {
        if event.down flags |= .PULLING;
        else          flags &= ~.PULLING;
    } else {
        if !event.down return;
        push_direction: Vector3i;
        if event.key == {
            case xx #char "W"; push_direction.z += 1;
            case xx #char "A"; push_direction.x -= 1;
            case xx #char "S"; push_direction.z -= 1;
            case xx #char "D"; push_direction.x += 1;
            case xx #char "Q"; push_direction.y += 1;
            case xx #char "E"; push_direction.y -= 1;
            case; return;

        }
        
        new_player_position := player_position + push_direction;

        
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
            pulled_in_bounds, pulled_block := get_block(*collision, player_position - push_direction);
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
            if !add_block_to_collision(*collision, it) {

                // Undo everything we just tried to do
                it.position -= push_direction;
                for #v2 < 0..it_index-1 {
                    block := moving_blocks[it];
                    remove_block_from_collision(*collision, block);
                    block.position -= push_direction;
                }

                for moving_blocks {
                    assert(add_block_to_collision(*collision, it));
                }

                move_failed = true;
                break;
            }
        }

        if !move_failed player_position = new_player_position;
    }
}
