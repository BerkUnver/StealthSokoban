Level :: struct {
    selectables: Fixed_Array(32, Selectable);
    
    blocks: Fixed_Array(32, Block);
    ENEMY_COUNT :: 32;
    enemies: Fixed_Array(ENEMY_COUNT, Enemy); // @TODO: Get deleting these to work in the editor!
    enemy_spawners: Fixed_Array(32, Enemy_Spawner);

    player:   Simple_Entity;
    entrance: Simple_Entity;
    exit:     Simple_Entity;
    
    // These are gameplay-only variables. In the future, we might want to better-differentiate
    // between what is modifiable in the editor (which should be as close as we can get to a 
    // pure-data representation of the scene) and what is gameplay state. We could use
    // metaprogramming to do this but it seems like overkill right now.
    
    enemy_annihilations: Fixed_Array(ENEMY_COUNT / 2, Vector3);
    #assert ENEMY_COUNT % 2 == 0;

    flags: enum {PULLING :: 1;};
    
    camera_pitch_ticks: s8 = 0;
    camera_yaw_ticks: s8;

    enemy_timer: float;

    collision: Collision;
}


CAMERA_PITCH_TICK_COUNT :: 5; // Starts at zero
CAMERA_MIN_PITCH :: -PI / 3;
CAMERA_MAX_PITCH :: PI / 3;

CAMERA_YAW_TICK_COUNT :: 12;


Selectable :: struct {
    position: *Vector3i;
    mesh: *Mesh;
    delete_index := -1;
    delete_size: u64;
    delete_array: *void; // @TODO: Make sure this is at least a Fixed_Array of something.
}


Eid :: struct { // Entity ID
    type: Type;
    ptr: *void;
}



make_eid :: inline (ptr: *$T) -> Eid {
    return .{T, ptr};
}


as :: inline (eid: Eid, $T: Type) -> *T {
    if eid.type == T return eid.ptr;
    return null;
}


eq :: inline (a: Eid, b: Eid) -> bool {
    if a.ptr == b.ptr {
        assert(a.type == b.type);
        return true;
    }
    return false;
}


is_null :: inline (eid: Eid) -> bool {
    return eid.ptr == null;
}


// Right now, most of our level entities are pretty simple
// so having this struct, which represents those,
// is probably fine.
Simple_Entity :: struct {
    position: Vector3i;
    mesh: Mesh;
}


Enemy_State :: enum {
    IDLE;
    MOVING;
    SPAWNING;
}

Enemy :: struct {
    position: Vector3i;
    desired_position: Vector3i; // Only used when we are updating all the enemies.
    MOVING_TIME :: 0.1;
    SPAWNING_TIME :: 0.2;
    moving_from: Vector3;
    moving_timer: float; // We could find a way to store one of these for all enemies.
    state: Enemy_State;
}

Enemy_Spawner :: struct {
    position: Vector3i;
}

Block :: struct {
    position: Vector3i;
    size: Vector3i;
    filled: [] bool;
    color: Vector4;
    moveable: bool;
    mesh: Mesh;
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

    filled: [] Eid;
    viewed: [] View_State;
    desired_enemy_moves: [] Desired_Enemy_Move;
    enemy_move_results: [] Enemy_Move_Result;

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


Desired_Enemy_Move :: enum u8 {
    EMPTY;
    WILL_BE_FILLED;
    MUTUAL_ANNIHILATION;
    // we may move it somewhere else in the future.
}


Enemy_Move_Result :: enum u8 {
    NOTHING;
    MUTUAL_ANNIHILATION_HAPPENED;
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
        filled = arena_alloc_array(arena, size_1d, Eid),
        viewed = arena_alloc_array(arena, size_1d, View_State),
        desired_enemy_moves = arena_alloc_array(arena, size_1d, Desired_Enemy_Move),
        enemy_move_results = arena_alloc_array(arena, size_1d, Enemy_Move_Result),
        texture = make_collision_texture(size),
    };
}


// @Cleanup delete this and the below function. Just use the index-getting functions directly.
get_filled :: (collision: *Collision, position: Vector3i) -> in_bounds: bool, eid: Eid, index: s64 {
    success, index := get_3d_index(position, collision.position, collision.size);
    if !success return false, .{}, -1;
    return true, collision.filled[index], index;
}


get_filled_relative :: (collision: *Collision, position: Vector3i) -> in_bounds: bool, eid: Eid, index: s64 {
    success, index := get_3d_index(position, collision.size);
    if !success return false, .{}, -1;
    return true, collision.filled[index], index;
}


Add_Block_Result :: enum {
    OK;
    OUT_OF_BOUNDS;
    CELL_ALREADY_OCCUPIED;
}


add_block_to_collision :: (collision: *Collision, block: *Block) -> Add_Block_Result {
    offset := block.position - collision.position;
    end := offset + block.size;
    if !inside_positive_bounding_box(offset, collision.size) return .OUT_OF_BOUNDS;
    if (end.x < 0 || collision.size.x < end.x ||
        end.x < 0 || collision.size.x < end.x ||
        end.x < 0 || collision.size.x < end.x ) return .OUT_OF_BOUNDS;

    // @Speed we could just detect when the failure happens and unwind what we've
    // already added instead of first checking, then adding.

    for :iterate_vector3i block.size {
        filled := block.filled[it_index];
        if !filled continue;
        collision_coord := it + offset;
        
        in_bounds, eid := get_filled_relative(collision, it + offset);
        if in_bounds && !is_null(eid) return .CELL_ALREADY_OCCUPIED;
    }

    for :iterate_vector3i block.size {
        filled := block.filled[it_index];
        if !filled continue;

        collision_coord := it + offset;
        collision_index := get_3d_index_unchecked(collision_coord, collision.size);
        collision.filled[collision_index] = make_eid(block);
    }

    return .OK;
}


// @Speed @TODO: When we add the player seeing mechanic, we want to have this routine know about Collision and do some early-out checks and possibly automatically do index conversion because this is going to get called hundreds of times every frame.
raycast :: (ray_start: Vector3, ray_end: Vector3, $visitor: (position: Vector3i, user_data: $T) -> terminate_raycast: bool, user_data: T) -> collided: bool, t: float {
    EPSILON :: 0.001;
    
    sign_x := sign(ray_end.x - ray_start.x);
    sign_z := sign(ray_end.z - ray_start.z);

    raycast_x :: (y_plane: s32, z_plane: s32, ray_start_x: float, ray_end_x: float, user_data: T) #expand {
        round_start_x := round(ray_start_x);
        round_end_x := round(ray_end_x);

        if abs(round_start_x - ray_start_x) < EPSILON {
            ray_start_x = round_start_x + sign_x * EPSILON;
        }

        if abs(round_end_x - ray_end_x) < EPSILON {
            ray_end_x = round_end_x - sign_x * EPSILON;
        }

        floor_start_x := floor(ray_start_x);
        floor_end_x := floor(ray_end_x);

        x_steps := cast(s32, floor_end_x - floor_start_x);

        // This cannot be factored outside of these helper functions because floating point
        // error may cause the values of ray_start_x and ray_end_x to be slightly wrong,
        // causing the value of (ray_end_x - ray_start_x) to have the opposite sign of what 
        // we expect. I don't want to do a deep investigation right now to find out
        // precisely what the problem is.

        // The correct thing to do might just be having different branches for positive
        // and negative. When I come back to this I might rewrite it to be like that,
        // which will DEFINITELY be simpler and maybe faster.

        //          - berk, 14 - 2 - 2025

        dir_x := sign(x_steps);

        x := cast(s32, floor_start_x);
        start := Vector3i.{x, y_plane, z_plane};
        if visitor(start, user_data) `return true, (ray_start_x - ray_start.x) / (ray_end.x - ray_start.x);

        i : s32 = 0;
        while i != x_steps {
            i += dir_x;
            start.x += dir_x;

            if visitor(start, user_data) `return true, (start.x + ifx dir_x == 1 then 0 else 1 - ray_start.x) / (ray_end.x - ray_start.x);
        }
    }


    raycast_zx :: (y_plane: s32, ray_start_x: float, ray_start_z: float, ray_end_x: float, ray_end_z: float, user_data: T) #expand {

        round_start_z := round(ray_start_z);
        round_end_z := round(ray_end_z);

        if abs(round_start_z - ray_start_z) < EPSILON {
            ray_start_z = round_start_z + sign_z * EPSILON;
        }

        if abs(round_end_z - ray_end_z) < EPSILON {
            ray_end_z = round_end_z - sign_z * EPSILON;
        }
        
        floor_start_z := floor(ray_start_z);
        floor_end_z := floor(ray_end_z);

        z_steps := cast(s32, floor_end_z - floor_start_z);

        if z_steps == 0 {
            raycast_x(y_plane, xx floor_start_z, ray_start_x, ray_end_x, user_data);
        } else {
            dir_z := sign(z_steps);

            m := (ray_end_x - ray_start_x) / (ray_end_z - ray_start_z);
            b := ray_start_x - m * ray_start_z;
            
            z_plane := cast(s32, floor_start_z);
            z := z_plane + cast(s32, z_steps > 0);

            x := m * z + b;

            raycast_x(y_plane, z_plane, ray_start_x, x, user_data);
            
            i := 0;
            range_end := z_steps - dir_z; // Every cube except the last one

            while i != range_end {
                i += dir_z;
                z_plane += dir_z;
                z += dir_z;
                old_x := x;
                x = m * z + b;
                raycast_x(y_plane, z_plane, old_x, x, user_data);
            }
            
            z_plane += dir_z;
            raycast_x(y_plane, z_plane, x, ray_end_x, user_data);
        }
    }
   
    floor_start_y := floor(ray_start.y);
    floor_end_y := floor(ray_end.y);

    y_steps := cast(s32, floor_end_y - floor_start_y);

    if y_steps == 0 {
        raycast_zx(xx floor_start_y, ray_start.x, ray_start.z, ray_end.x, ray_end.z, user_data);
        return false, 0;
    } else {
        dir_y := sign(y_steps);

        ray_length := ray_end - ray_start;

        y_plane := cast(s32, floor_start_y);
        y := y_plane + cast(s32, y_steps > 0);
        t := (y - ray_start.y) / ray_length.y;

        x := ray_start.x + ray_length.x * t;
        z := ray_start.z + ray_length.z * t;
        
        raycast_zx(y_plane, ray_start.x, ray_start.z, x, z, user_data);
        
        i := 0;
        range_end := y_steps - dir_y;
        while i != range_end {
            i += dir_y;
            y_plane += dir_y;
            y += dir_y;
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

            raycast_zx(y_plane, old_x, old_z, x, z, user_data);
        }

        y_plane += dir_y;

        raycast_zx(y_plane, x, z, ray_end.x, ray_end.z, user_data);

        return false, 0;
    }
}


remove_block_from_collision :: (collision: *Collision, block: *Block) {
    offset := block.position - collision.position;
    for :iterate_vector3i block.size {
        filled := block.filled[it_index];
        if !filled continue;
        in_bounds, eid, index := get_filled_relative(collision, it + offset);
        assert(in_bounds && eid.ptr == block);
        collision.filled[index] = .{};
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


make_level_for_editor :: (using level: *Level, level_arena: *Memory_Arena) {
    using context.game_context;

    // @Speed maybe we can just set what we need to be reset in case
    // this is a reused pointer from an old level. I am going to
    // zero-init everything right now to prevent bugs.
    level.* = .{};

    T :: true;
    F :: false;
    
    entrance = .{
        position = .{-1, 0, -1},
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
    
    append(*enemies).* = .{
        position = .{0, 0, 0},
    };

    append(*enemies).* = .{
        position = .{-1, 0, 0},
    };

    append(*enemy_spawners).* = .{
        position = .{2, 0, 0},
    };
    
    // @TODO: Factor this to be editor-only.
    assert(append(*selectables, .{position=*entrance.position, mesh=*entrance.mesh}));
    assert(append(*selectables, .{position=*exit.position,     mesh=*exit.mesh}));
    assert(append(*selectables, .{position=*player.position,   mesh=*player.mesh}));
    
    register_selectables :: (array: *Fixed_Array($N, $T), mesh: *Mesh) #expand {
        for * array {
            s := append(*selectables);
            s.* = .{
                position = *it.position,
                mesh = mesh,
                delete_index = it_index,
                delete_size = size_of(type_of(it.*)),
                delete_array = *array
            };
        }
    }
    
    register_selectables(*enemies, *enemy_mesh);
    register_selectables(*enemy_spawners, *enemy_spawner_mesh);

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
            size = .{1, 3, 1},
            filled = .[
                T,
                T,
                T,
            ],
            color = .{0, 0, 1, 1},
            moveable = true
        }
    ];

    for * temp_blocks add_temporary_block_to_level(it, level, level_arena);
}


make_level_for_game :: (using level: *Level, level_arena: *Memory_Arena) {
    make_level_for_editor(level, level_arena);

    collision = make_collision(to_array(blocks), level_arena);
    for * blocks {
        assert(add_block_to_collision(*collision, it) == .OK);
    }
    
    for * enemies {
        in_bounds, eid, index := get_filled(*collision, it.position);
        assert(in_bounds && is_null(eid));
        collision.filled[index] = make_eid(it);
    }
}


add_temporary_block_to_level :: (using temp_block: *Temporary_Block, using level: *Level, level_arena: *Memory_Arena) {
    filled_allocated := arena_alloc_array(level_arena, filled.count, bool);
    memcpy(filled_allocated.data, filled.data, size_of(type_of(filled.data.*)) * filled.count);
    
    index := blocks.count;
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
    
    // @TODO: Figure out what to do when we exceed the maximum number of blocks we're allowing right now.
    s := append(*selectables);
    s.* = .{
        position = *block.position,
        mesh = *block.mesh,
        delete_index = index,
        delete_size = size_of(Block),
        delete_array = *blocks
    };
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
        
        pushed_in_bounds, pushed_eid := get_filled(*collision, new_player_position);
        if !pushed_in_bounds return;
        if !is_null(pushed_eid) {
            pushed_block := as(pushed_eid, Block);
            if pushed_block {
                if !pushed_block.moveable return;
                assert(append(*moving_blocks, pushed_block));
            } else {
                enemy := as(pushed_eid, Enemy);
                if enemy return;
            }
        }



        
        if flags & .PULLING {
            pulled_in_bounds, pulled_eid := get_filled(*collision, player.position - push_direction);
            if pulled_in_bounds {
                pulled_block := as(pulled_eid, Block);
                if pulled_block && pulled_block.moveable && !contains(*moving_blocks, pulled_block) {
                    assert(append(*moving_blocks, pulled_block));
                }
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


level_update :: (using level: *Level, dt: float) {
    // The following code is nontrivial so I will write an explanation.
    // We are using a variant of the naive version of floodfill where you try to fill all the cells adjacent to you.
    // Here's why:
    // A cell will only be visible if it has at least one neighboring cell that is visible.
    // That means if a raycast fails, we can stop propagating the raycast early. This might be premature optimization
    // because in our worst-cast scenario you will have to check most of the cells in the level anyway.
    // The QUEUED_FOR_FLOODFILL bit exists to tell us that a cell is already on the floodfill stack.
    // This prevents many copies of the same cell from ending up on the floodfill stack and blowing up memory.
   
    // :SlowRaycast
    // @Speed So, this is our first real reality check of this game.
    // Running this with ~4000 raycasts/frame is already lagging out the game.
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

        start := to_vector3(position) + Vector3.{0.5, 0.5, 0.5};
        
        visitor :: (position: Vector3i, collision: *Collision) -> terminate_raycast: bool {
            in_bounds, eid := get_filled(collision, position);
            if !in_bounds || is_null(eid) return false;
            return as(eid, Block) != null;
        }
        
        if raycast(start, end, visitor, *collision) continue;

        collision.viewed[index] |= (.SEEN | .VISIBLE);

        check_position :: (p: Vector3i) #expand {
            success, eid, index := get_filled(*collision, p);
            if !success || as(eid, Block) || (collision.viewed[index] & .QUEUED_FOR_FLOODFILL) return;
            collision.viewed[index] |= .QUEUED_FOR_FLOODFILL;
            positions[position_count] = .{index, p};
            position_count += 1;
        }
        
        // We only need to floodfill in the directions facing away from where the player is facing.
        // This is important because we add a little epsilon fudge factor to allow the raycast to
        // not behave inconsistently when it perfectly aligns with grid boundaries. If we raycast
        // in all directions, we could end up having a successful raycast above a wall, floodfilling
        // downwards to a place behind a wall, then doing a raycast from there and having it
        // succeed if the ray perfectly aligns with grid boundaries.

        // [*] [ ] [ ]
        // [W] [S] [W]
        // [S] [S] [P]

        // P: Player, W: Fall, S: Succeed raycast
        // We floodfill to above the wall on the left, which floodfills in the z axis and the raycast
        // succeeds, which then floodfills downwards into [*], which succeeds because of the fudge
        // factor even though it shouldn't.

        // This could possibly hint to deeper underlying logical fallacies in the code. BE ON THE
        // LOOKOUT FOR FURTHER WEIRD STUFF. If anything else weird happens it might be good to
        // cause the "fudge factor" to be stricter against the player instead of looser against them,
        // which would prevent this ambiguity from happening.
        
        // :SlowRaycast
        // If @Speed becomes an issue and we decide to put do this as a compute shader then the 
        // fudge factor is going to have to be stricter anyway because we can't do floodfilling
        // in a compute shader.

        //          - berk, 11 - 2 - 2025

        check_axis :: (i: int) #expand #no_abc {
            diff := end.component[i] - start.component[i];
            if diff < 0 {
                positive := position;
                positive.component[i] += 1;
                check_position(positive);
            } else if diff > 0 {
                negative := position;
                negative.component[i] -= 1;
                check_position(negative);
            } else {
                positive := position;
                positive.component[i] += 1;
                check_position(positive);
                negative := position;
                negative.component[i] -= 1;
                check_position(negative);
            }
        }

        check_axis(0);
        check_axis(1);
        check_axis(2);
    }


    ENEMY_TICK_TIME :: 1;
    enemy_timer += dt;
    if enemy_timer >= ENEMY_TICK_TIME {
        enemy_timer = fmod_cycling(enemy_timer, ENEMY_TICK_TIME);

        memset(collision.desired_enemy_moves.data, xx Desired_Enemy_Move.EMPTY, byte_count(collision.desired_enemy_moves));

        for * enemies { 
            desired_position := it.position;
            desired_position.x -= 1;

            in_bounds, index := get_3d_index(desired_position, collision.position, collision.size);
            
            if !in_bounds || as(collision.filled[index], Block) {
                it.desired_position = it.position;
            } else {
                it.desired_position = desired_position;
            }

            in_bounds, index = get_3d_index(it.desired_position, collision.position, collision.size);
            assert(in_bounds);
            
            if #complete collision.desired_enemy_moves[index] == {
                case .EMPTY;
                    collision.desired_enemy_moves[index] = .WILL_BE_FILLED;
                case .WILL_BE_FILLED;
                    collision.desired_enemy_moves[index] = .MUTUAL_ANNIHILATION;
                case .MUTUAL_ANNIHILATION;
                    // Do nothing because this enemy will be destroyed too.
            }
        }

        for * enemy_spawners {
            in_bounds, index := get_3d_index(it.position, collision.position, collision.size);
            assert(in_bounds);
 
            // @Copypasta from above
            if #complete collision.desired_enemy_moves[index] == {
                case .EMPTY;
                    collision.desired_enemy_moves[index] = .WILL_BE_FILLED;
                case .WILL_BE_FILLED;
                    collision.desired_enemy_moves[index] = .MUTUAL_ANNIHILATION;
                case .MUTUAL_ANNIHILATION;
                    // Do nothing because this enemy will be destroyed too.
            }
        }
       
        
        // @Speed this is very dumb that this array is so big.
        memset(collision.enemy_move_results.data, xx Enemy_Move_Result.NOTHING, byte_count(collision.enemy_move_results));

        // Remove all the enemies from the collision to make sure that when we reinsert them, all of the old ones
        // have been cleaned up. Otherwise, if we cleared the collision.filled[index] of the old enemy position,
        // a new enemy could already be there!
        for * enemies {
            in_bounds, eid, index := get_filled(*collision, it.position);
            assert(eid.ptr == it);
            collision.filled[index] = .{};
        }

        for * enemies {
            in_bounds, index := get_3d_index(it.desired_position, collision.position, collision.size);
            assert(in_bounds);
            if #complete collision.desired_enemy_moves[index] == {
                case .EMPTY;
                    assert(false);

                case .WILL_BE_FILLED;
                    it.state = .MOVING;
                    it.moving_from = to_vector3(it.position);
                    it.position = it.desired_position;
                    collision.filled[index] = make_eid(it);

                case .MUTUAL_ANNIHILATION;
                    if collision.enemy_move_results[index] == .NOTHING {
                        collision.enemy_move_results[index] = .MUTUAL_ANNIHILATION_HAPPENED;
                        assert(append(*enemy_annihilations, to_vector3(it.desired_position)));
                    }
                    remove it;
            }
        }

        for * enemy_spawners {
            in_bounds, index := get_3d_index(it.position, collision.position, collision.size);
            assert(in_bounds); 
            if #complete collision.desired_enemy_moves[index] == {
                case .EMPTY;
                    assert(false);

                case .WILL_BE_FILLED;
                    e := append(*enemies);
                    e.* = .{position = it.position, state = .SPAWNING};
                    assert(is_null(collision.filled[index]));
                    collision.filled[index] = make_eid(e);

                case .MUTUAL_ANNIHILATION;
                    // @TODO: If two enemy spawners end up on the same square
                    // (The player pushed a block with an enemy spawner attached
                    // into it), we need a special effect for this situation.
            }
        }
    }
    
    if enemy_timer >= Enemy.MOVING_TIME {
        for * enemies {
            if it.state == .MOVING it.state = .IDLE;
        }
    }

    if enemy_timer >= Enemy.SPAWNING_TIME {
        for * enemies {
            if it.state == .SPAWNING it.state = .IDLE;
        }
    }
    
    update_collision_texture(*collision);
}
