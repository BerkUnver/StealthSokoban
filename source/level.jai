Level :: struct {
    blocks: Fixed_Array(32, Block);

    player_position: Vector3i;
    flags: enum {PULLING :: 1;};
    entrance: Vector3i;
    exit: Vector3i;

    camera_position: Vector3;
    camera_pitch: float;
    camera_yaw: float;
    camera_projection: Matrix4;

    collision: Collision;
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
}


View_State :: enum_flags u8 {
    SEEN;
    VISIBLE;
    
    QUEUED_FOR_FLOODFILL;
}


// :EditorCollision
/*
I have arrived at a bit of a conundrum. Currently, in the game, each collision cube
is only allowed to be occupied by one thing. This makes sense for the gameplay mode.
However, in the editor, this makes less sense. Once we start adding multi-extrusion
and especially dragging, we may want to allow multiple things to overlap in the
editor, and have a visual warning if they do. This would require a different 
collision data structure for the editor than the game. We need a collision data
structure in the editor so we can pick individual level elements with the mouse
cursor (though this may eventually change to using the meshes of each entity) and
so warning us about overlaps is fast.

A lot of this seems to be predicting things in the future that don't exist in the
game yet. THE GOAL IS TO GET TO A MINIMALLY WORKING LEVEL EDITOR AS FAST AS
POSSIBLE SO I CAN START DESIGNING LEVELS! ALWAYS KEEP THAT IN MIND!

            -berk, 28 - 1 - 2025
*/


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
    success, index := get_3d_index(position, col.position, col.size);
    if !success return false, null;
    return true, col.filled[index];
}


make_collision :: (level_arena: *Memory_Arena) -> Collision {
    START :: Vector3i.{-10, -10, -10};
    END :: Vector3i.{10, 10, 10};
    size := END - START;
    collision_array_size := size.x * size.y * size.z;

    filled := arena_alloc_array(level_arena, collision_array_size, *Block);

    viewed := arena_alloc_array(level_arena, collision_array_size, View_State);

    return Collision.{
        position = START,
        size = size,
        filled = filled,
        viewed = viewed
    };
}


add_block_to_collision :: (col: *Collision, block: *Block) -> bool {
    offset := block.position - col.position;
    assert(inside_positive_bounding_box(offset, col.size));
    assert(inside_positive_bounding_box(offset + block.size, col.size));

    // @Speed we could just detect when the failure happens and unwind what we've
    // already added instead of first checking, then adding.

    for :iterate_vector3i block.size {
        filled := block.filled[it_index];
        if !filled continue;
        collision_coord := it + offset;
        collision_index := get_3d_index_unchecked(collision_coord, col.size);
        block_already_there := col.filled[collision_index];
        if block_already_there return false;
    }

    for :iterate_vector3i block.size {
        filled := block.filled[it_index];
        if !filled continue;
        collision_coord := it + offset;
        collision_index := get_3d_index_unchecked(collision_coord, col.size);
        col.filled[collision_index] = block;
    }

    return true;
}


// @Speed @TODO: When we add the player seeing mechanic, we want to have this routine know about Collision and do some early-out checks and possibly automatically do index conversion because this is going to get called hundreds of times every frame.
raycast :: (ray_start: Vector3, ray_end: Vector3, $visitor: (position: Vector3i, user_data: $T) -> terminate_raycast: bool, user_data: T) -> collided: bool {
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

            if raycast_zx(y_plane, old_x, old_z, x, z, user_data) return true;
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


add_block_to_level :: (level: *Level, level_arena: *Memory_Arena, position: Vector3i, size: Vector3i, filled: [] bool, color: Vector4, moveable: bool) {
     assert(position.x >= level.collision.position.x
            && position.y >= level.collision.position.y
            && position.z >= level.collision.position.z);
     assert(position.x + size.x < level.collision.position.x + level.collision.size.x
            && position.y + size.y < level.collision.position.y + level.collision.size.y
            && position.z + size.z < level.collision.position.z + level.collision.size.z);

     assert(size.x * size.y * size.z == filled.count);
    
     // Do we need more elegant failure cases here?

     filled_allocated := arena_alloc_array(level_arena, filled.count, bool);
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

init_camera :: (using level: *Level) {
    FOV :: PI / 3;
    NEAR :: 0.1;

    right := cast(float, NEAR * tan(FOV / 2));
    top := right * cast(float, INNER_WINDOW_H) / cast(float, INNER_WINDOW_W);
    
    camera_projection = make_left_handed_frustum_matrix(-right, -top, NEAR, right, top, 1000);
    camera_pitch = -PI / 3;
    camera_position = .{0, 8, -4};
}


get_camera_matrix :: (using level: *Level) -> Matrix4 {
    position_matrix := make_translation_matrix4(-camera_position);
    pitch_matrix := make_x_rotation_matrix(Matrix4, -camera_pitch);
    yaw_matrix := make_y_rotation_matrix(Matrix4, -camera_yaw);

    return multiply(camera_projection, multiply(pitch_matrix, multiply(yaw_matrix, position_matrix)));
}


get_camera_to_world_rotation_matrix :: (using level: *Level) -> Matrix3 {
    yaw_matrix := make_y_rotation_matrix(Matrix3, camera_yaw);
    pitch_matrix := make_x_rotation_matrix(Matrix3, camera_pitch);
    return multiply(yaw_matrix, pitch_matrix);
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

    player_success, player_index := get_3d_index(player_position, collision.position, collision.size);
    assert(player_success);
    positions[0] = .{player_index, player_position};
    collision.viewed[player_index] |= .QUEUED_FOR_FLOODFILL;
    
    end := to_vector3(player_position) + Vector3.{0.5, 0.5, 0.5};
    while position_count != 0 {
        position_count -= 1;
        using index_and_position := positions[position_count];

        visitor :: (position: Vector3i, collision: *Collision) -> terminate_raycast: bool {
            success, index := get_3d_index(position, collision.position, collision.size);
            if !success return false;
            return collision.filled[index] != null;
        }
        
        start := to_vector3(position) + Vector3.{0.5, 0.5, 0.5};

        if raycast(start, end, visitor, *collision) continue;
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
}


test_level_init :: (level: *Level, level_arena: *Memory_Arena) {
    T :: true;
    F :: false;
     
    level.collision = make_collision(level_arena);
    level.entrance = .{-3, 0, -2};
    level.player_position = level.entrance;
    level.exit = .{2, 0, -1};
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
        color = .{163.0/255.0, 176.0/255.0, 183.0/255.0, 1},
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
        color = .{204.0/255.0, 206.0/255.0, 207.0/255.0, 1},
        // .{1, 143.0/255.0, 0, 1} Orange color that I liked
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

level_handle_input :: (using level: *Level, level_arena: *Memory_Arena, event: Input_Event) { 
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

        if !move_failed {
            player_position = new_player_position;
            if player_position == exit {
                clear_arena(level_arena);
                test_level_init(level, level_arena);
            }
        }
    }
}


