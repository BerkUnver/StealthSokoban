Level :: struct {
    using types: Entity_Types;
    
    name: string; @Ignore // The file name

    // @TODO: This should be a hash table... probably.
    entities: [..] *Entity; @Ignore
    
    // These are gameplay-only variables. In the future, we might want to better-differentiate
    // between what is modifiable in the editor (which should be as close as we can get to a 
    // pure-data representation of the scene) and what is gameplay state. We could use
    // metaprogramming to do this but it seems like overkill right now.K
    
    level_position: Vector3i; @Ignore
    level_size: Vector3i; @Ignore

    enemy_annihilations: [..] Vector3i; @Ignore
    unused_eids: [..] Entity_Id; @Ignore

    flags: enum {PULLING :: 1;}; @Ignore
    player_can_move_through_blocks: bool; @Ignore
    
    camera_mode: Camera_Mode; @Ignore
    camera: union {
        focus_on_player: struct {
            focus_old: Vector3;
            focus_interp := 1.0;
        };
    }; @Ignore

    camera_pitch_ticks: s8 = 0; @Ignore
    camera_pitch_interp := 1.0; @Ignore
    camera_pitch_old: float64; @Ignore

    camera_yaw_target: float64; @Ignore
    camera_yaw_old: float64; @Ignore
    camera_yaw_interp := 1.0; @Ignore

    camera_matrix: Matrix4; @Ignore

    enemy_timer: float; @Ignore
    dt_modifier := 1.0; @Ignore

    collision: [] Entity_Id; @Ignore
    viewed: [] View_State; @Ignore
    desired_enemy_moves: [] Desired_Enemy_Move; @Ignore
    enemy_move_results: [] Enemy_Move_Result; @Ignore

    // These are stored SOA because we don't want to touch these at the same time.
    // @TODO 3d arrays are stored x-major, then z, then y.
    // This makes sense from the perspective of wanting to be
    // able to type levels directly into code for this initial
    // development period, but may make less sense later.
    // Consider coming back to this.

    view_texture: View_Texture; @Ignore
}


CAMERA_PITCH_TICK_COUNT :: 5; // Starts at zero
CAMERA_MIN_PITCH :: -PI / 3;
CAMERA_MAX_PITCH :: PI / 3;

CAMERA_YAW_TICK_COUNT :: 12;


Camera_Mode :: enum {
    FOCUS_ON_PLAYER;
    FOCUS_ON_LEVEL;
    FOCUS_ON_FLOODFILL;
    COUNT;
}


Player :: struct {
    using #as e: Entity;
    COLOR :: Vector4.{1, 1, 1, 1};
}


Entrance :: struct { 
    using #as e: Entity;
    COLOR :: Vector4.{75.0/255.0, 228.0/255.0, 1, 1};
}


Exit :: struct {
    using #as e: Entity;
    COLOR :: Vector4.{146.0/255.0, 1, 118.0/255.0, 1};
}


Enemy_State :: enum u8 {
    IDLE;
    MOVING;
    SPAWNING;
}


// I did this so we could have a concrete way to see what gameplay direction something is facing.
// It might be better to just have a rotation quaternion on the entity. Let's see what happens.
Facing :: enum u8 {
    X_POSITIVE; // The default, assumed orientation
    Z_POSITIVE;
    X_NEGATIVE;
    Z_NEGATIVE;
    COUNT;
}


facing_vector3i :: (f: Facing) -> Vector3i {
    v := Vector3i.{};
    if f == {
        case .X_POSITIVE; v.x += 1;
        case .Z_POSITIVE; v.z += 1;
        case .X_NEGATIVE; v.x -= 1;
        case .Z_NEGATIVE; v.z -= 1;
    }
    return v;
}


facing_right :: inline (f: Facing) -> Facing {
    return (f - 1 + Facing.COUNT) % Facing.COUNT;
}


facing_left :: inline (f: Facing) -> Facing {
    return (f + 1) % Facing.COUNT;
}


facing_opposite :: inline (f: Facing) -> Facing {
    return (f + 2) % Facing.COUNT;
}


Favored_Direction :: enum u8 {
    LEFT;
    RIGHT;
}


Enemy :: struct {
    using #as e: Entity;

    desired_position: Vector3i; // Only used when we are updating all the enemies.
    MOVING_TIME :: 0.1;
    SPAWNING_TIME :: 0.2;
    ANNIHILATION_TIME :: 0.15;
    moving_from: Vector3;
    state: Enemy_State;
    favored_direction: Favored_Direction;
    facing: Facing;
}


Enemy_Spawner :: struct {
    using #as e: Entity;

    favored_direction: Favored_Direction;
    facing: Facing;

    COLOR :: Vector4.{0.5, 0, 0, 1};
}


/*
Block :: struct {
    size: Vector3i;
    filled: [] bool;
    color: Vector4;
    block_type: bool;
    mesh: Mesh; @Ignore
}


Stationary_Block :: struct {
    using #as e: Entity;
    using block: Block;
}


Moving_Block :: struct {
    using #as e: Entity;
    using block: Block;
}


Door :: struct {
    using #as e: Entity;
    using block: Block;
}
*/

Block_Type :: enum {
    STATIONARY;
    MOVING;
    DOOR;
}


Block :: struct {
    using #as e: Entity;

    size: Vector3i;
    filled: [] bool;
    color: Vector4;
    block_type: Block_Type;
    mesh: Mesh; @Ignore
    // @TODO Make a bit array data structure for better cache coherency
}


// This solely exists as a convenience so I can type blocks into the editor for now.
Temporary_Block :: struct {
    position: Vector3i;
    size: Vector3i;
    filled: [] bool;
    color: Vector4;
    block_type: Block_Type;
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


Add_Block_Result :: enum {
    OK;
    OUT_OF_BOUNDS;
    CELL_ALREADY_OCCUPIED;
}


add_block_to_collision :: (using level: *Level, block: *Block) -> Add_Block_Result {
    offset := block.position - level_position;
    end := offset + block.size;
    if !inside_positive_bounding_box(offset, level_size) return .OUT_OF_BOUNDS;
    if !inside_positive_bounding_box(end - Vector3i.{1, 1, 1}, level_size) return .OUT_OF_BOUNDS;

    // @Speed we could just detect when the failure happens and unwind what we've
    // already added instead of first checking, then adding.

    for :iterate_vector3i block.size {
        if !block.filled[it_index] continue;
        collision_coord := it + offset;
        
        in_bounds, index := get_3d_index(it + offset, level_size);
        assert(in_bounds);
        eid := collision[index];
        if eid return .CELL_ALREADY_OCCUPIED;
    }

    for :iterate_vector3i block.size {
        if !block.filled[it_index] continue;

        collision_coord := it + offset;
        collision_index := get_3d_index_unchecked(collision_coord, level_size);
        collision[collision_index] = block.eid;
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

            if visitor(start, user_data) `return true, (start.x + (ifx dir_x == 1 then 0 else 1) - ray_start.x) / (ray_end.x - ray_start.x);
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


remove_block_from_collision :: (using level: *Level, block: *Block) {
    offset := block.position - level_position;
    for :iterate_vector3i block.size {
        if !block.filled[it_index] continue;
        in_bounds, index := get_3d_index(it + offset, level_size);
        assert(in_bounds);
        eid := collision[index];
        assert(eid != 0);
        assert(get_entity(level, eid) == block);
        collision[index] = 0;
    }
}


get_camera_pitch :: (using level: *Level) -> float {
    pitch := lerp(CAMERA_MIN_PITCH, CAMERA_MAX_PITCH, cast(float, camera_pitch_ticks) / cast(float, CAMERA_PITCH_TICK_COUNT));
    return xx lerp(camera_pitch_old, pitch, camera_pitch_interp);
}


get_camera_yaw :: (using level: *Level) -> float {
    return xx lerp(camera_yaw_old, camera_yaw_target, camera_yaw_interp);
    // return xx lerp(camera_yaw_old, camera_yaw_target, sin((1 - camera_yaw_interp) * PI / 2));
    // This one feels kind of "gummy".
}


load_level_part_1_new :: (using level: *Level, arena: *Memory_Arena) {
    level.* = .{};
}


load_level_part_1_example :: (using level: *Level, arena: *Memory_Arena) {
    using context.game_context;

    // @Speed maybe we can just set what we need to be reset in case
    // this is a reused pointer from an old level. I am going to
    // zero-init everything right now to prevent bugs.
    level.* = .{};

    T :: true;
    F :: false;

    _Entrance = alloc_array(arena, 1, Entrance);
    _Entrance[0] = .{
        position = .{-1, 0, -1},
    };
    
    _Exit = alloc_array(arena, 1, Exit);
    _Exit[0] = .{
        position = .{2, 0, -1},
    };
    
    _Player = alloc_array(arena, 1, Player);
    _Player[0] = .{
        position = _Entrance[0].position,
    };
    
    _Enemy_Spawner = alloc_array(arena, 1, Enemy_Spawner);
    _Enemy_Spawner[0] = .{
        position = .{2, 0, 2},
        facing = .X_NEGATIVE,
    };

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
                T, T, T, T, T, T, T, T, T, T, T, T,
            ],
            color = .{163.0/255.0, 176.0/255.0, 183.0/255.0, 1},
            block_type = .STATIONARY,
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
            block_type = .MOVING,
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
            block_type = .MOVING,
        }
    ];

    _Block = alloc_array(arena, temp_blocks.count, Block);
    for * temp_blocks {
        filled := alloc_view(arena, it.filled.count, bool);
        memcpy(filled.data, it.filled.data, size_of(type_of(it.filled.data.*)) * it.filled.count);

        generated_mesh := make_block_mesh(it.size, filled, arena);

        _Block[it_index] = .{
            position = it.position,
            size = it.size,
            filled = filled,
            color = it.color,
            block_type = it.block_type,
            mesh = generated_mesh
        };
    }

    _Enemy = alloc_array(arena, 2, Enemy);
    assert(_Enemy.count >= 2);
    _Enemy[0] = .{
        position = .{0, 0, 2},
    };
    _Enemy[1] = .{
        position = .{-1, 0, 2},
    };

}


load_level_part_1_deserialize :: (level_name: string, using level: *Level, arena: *Memory_Arena) -> bool {
    using context.game_context;
    
    buf: [100000] u8 = ---;
    success, level_text := read_file(level_name, buf);
    if !success {
        log(.ERROR, "Could not read the file \"%\"\n", level_name); 
    }

    mark := get_mark(arena);
    err := deserialize(level_text, level, arena);
    if !err.ok {
        log(.ERROR, "Encountered an error while deserializing level at byte %,%: %\n", err.loc.start, err.loc.count, err.message);
        restore_mark(arena, mark);
        return false;
    }

    return true;
}


serialize_level :: (using level: *Level) {
    using context.game_context;
    buf: [100000] u8 = ---;
    str := serialize(buf, level);
    assert(write_file(level.name, str));
}


load_level_part_2_init_unserialized_fields :: (level_name: string, using level: *Level, for_mode: Game_Mode, arena: *Memory_Arena) -> bool {
    name = copy_string(arena, level_name);
   
    // Give each entity an Entity_Id
    entity_count := 1;
    #insert -> string {
        buf: [1024] u8;
        sb := make_string_builder(buf);
        for Entity_Types.TYPES {
            print(*sb, "for * _% {\n", it.name);
            print(*sb, "    it.eid = xx entity_count;\n");
            print(*sb, "    it.type = .%;\n", it.name);
            print(*sb, "    entity_count += 1;\n");
            print(*sb, "}\n");
        }
        return get_string(*sb);
    }
    
    for * _Block {
        it.mesh = make_block_mesh(it.size, it.filled, arena);
    }

    if #complete for_mode == {
        case .EDITOR;
            entities = alloc_array(arena, entity_count, *Entity, zero_init = false);
            entities[0] = null;

            for :iterate_entities types {
                entities[it.eid] = it;
            }
            return true;

        case .GAME;
            level_position, level_size = get_block_extents(_Block);
            size_1d := level_size.x * level_size.y * level_size.z;
            // @Hack @Speed @Memory
            // This is a dumb workaround.
            // Right now, the serialization system will allocate as many elements as was serialized for an array.
            // We want to allocate custom sizes, which are as many as you will ever need, so we can not ever
            // dynamically allocate memory while the a level is running, and we can easily know how much memory the
            // game will ever use (when we're in the GAME mode. When we're in the EDITOR mode, do whatever you want.)
            alloc_extra_array_capacity(arena, *_Enemy, size_1d, zero_init=false);

            // Count up all the entities so we can allocate an array big enough
            // to hold pointers to all of them for the Entity_Id system
            // The first slot is null, so we start at 1.

            reserved := 1;
            count := 1;
            #insert -> string {
                buf: [1024] u8;
                sb := make_string_builder(buf);
                for Entity_Types.TYPES {
                    print(*sb, "reserved += _%.allocated;\n", it.name);
                    print(*sb, "count += _%.count;\n", it.name);
                }
                return get_string(*sb);
            }
            count += 1; // For the player we are about to add

            entities = reserve_array(arena, reserved, *Entity, zero_init=false);
            entities.count = count;
            entities[0] = null;

            unused_eids = reserve_array(arena, reserved, Entity_Id, zero_init=false);

            for :iterate_entities types {
                entities[it.eid] = it;
            }

            // @TODO: Make sure none of the other entities are outside of the level

            view_texture = make_view_texture(level_size);

            viewed = alloc_view(arena, size_1d, View_State);
            collision = alloc_view(arena, size_1d, Entity_Id);
            enemy_move_results = alloc_view(arena, size_1d, Enemy_Move_Result);
            desired_enemy_moves = alloc_view(arena, size_1d, Desired_Enemy_Move);
            enemy_annihilations = reserve_array(arena, size_1d / 2, Vector3i);

            for * _Block {
                assert(add_block_to_collision(level, it) == .OK);
            }
            
            for * _Enemy {
                in_bounds, index := get_3d_index(it.position, level_position, level_size);
                assert(in_bounds);
                assert(collision[index] == 0);
                collision[index] = it.eid;
            }

            if _Player.count != 0 {
                log(.ERROR, "There were player entities in the serialized level \"%\".\n", level.name);
                return false;
            }

            if _Entrance.count != 1 {
                log(.ERROR, "There were more or less than 1 level entrances in the serialized level \"%\".\n", level.name);
                return false;
            }

            player := make_entity(level, Player, arena);
            player.position = _Entrance[0].position;

            return true;
    }
}


free_level :: (using level: *Level, level_arena: *Memory_Arena) {   
    // @TODO This is a far-in-the-future kind of thing.
    // We should wrap glGenBuffers, glDeleteBuffers, and similar allocating functions and make a memory debugger
    // that tells us what has leaked when we close the application, because as far as I can tell, there's no good
    // way to natively get that information from OpenGL.

    free(*view_texture);

    for _Block {
        free(*it.mesh);
    }

    clear(level_arena);
}


get_enemy_draw_info :: (level: *Level, enemy: *Enemy) -> model_to_world: Matrix4, color: Vector4 {
    color_weight: float;
    matrix := Matrix4_Identity;
    if #complete enemy.state == {
        case .IDLE;
            color_weight = 1;

        case.MOVING;
            weight := level.enemy_timer / Enemy.MOVING_TIME;
            weight = weight * weight;
            position := (to_vector3(enemy.position) - enemy.moving_from) * (1 - weight);
            matrix = make_translation_matrix4(-position);
            color_weight = 1;

        case .SPAWNING;
            weight := level.enemy_timer / Enemy.SPAWNING_TIME;
            matrix = make_scale_matrix4(.{weight, weight, weight});
            color_weight = weight;
    }
    
    rotation: float;
    if enemy.facing == {
        case .X_POSITIVE;
        case .Z_NEGATIVE; rotation = PI / 2;
        case .X_NEGATIVE; rotation = PI;
        case .Z_POSITIVE; rotation = -PI / 2;
    }
    
    matrix = matrix * make_y_rotation_matrix(Matrix4, -rotation);
    matrix = make_translation_matrix4(to_vector3(enemy.position) + Vector3.{0.5, 0, 0.5}) * matrix;


    color: Vector4;
    if #complete enemy.favored_direction == {
        case .LEFT;
            color = .{0, 68.0 / 255.0, 166.0 / 255.0, 1};
        case .RIGHT;
            color = .{1, 0, 0, 1};
    };

    return matrix, color;
}


level_handle_input :: (using level: *Level, level_arena: *Memory_Arena, event: Input_Event) { 
    if event.key == #char " " {
        if event.down flags |= .PULLING;
        else          flags &= ~.PULLING;
        return;
    }

    if event.key == #char "K" && event.down {
        camera_pitch_old = get_camera_pitch(level);
        camera_pitch_ticks = max(camera_pitch_ticks - 1, 0);
        camera_pitch_interp = 0;
        return;
    }

    if event.key == #char "I" && event.down {
        camera_pitch_old = get_camera_pitch(level);
        camera_pitch_ticks = min(camera_pitch_ticks + 1, CAMERA_PITCH_TICK_COUNT);
        camera_pitch_interp = 0;
        return;
    } 
    
    if event.key == #char "L" && event.down {
        camera_yaw_old = get_camera_yaw(level);
        camera_yaw_interp = 0;
        camera_yaw_target -= TAU / 12;
        return;
    }
   
    if event.key == #char "J" && event.down {
        camera_yaw_old = get_camera_yaw(level);
        camera_yaw_interp = 0;
        camera_yaw_target += TAU / 12;
        return;
    } 

    if event.key == #char "-" && event.down {
        if 1.0 / 16.0 < dt_modifier dt_modifier /= 2;
        return;
    }

    if event.key == #char "=" && event.down {
        if dt_modifier < 16 dt_modifier *= 2;
        return;
    }

    if event.key == #char "M" && event.down {
        player_can_move_through_blocks = !player_can_move_through_blocks;
        return;
    }

    if event.key == #char "U" && event.down {
       camera_mode = (camera_mode + 1) % Camera_Mode.COUNT;
        if camera_mode == {
            case .FOCUS_ON_PLAYER;
                using camera.focus_on_player;
                focus_interp = 1;
        }
        return;
    }

    if !event.down return;
    push_direction: Vector3i;

    move :: (direction: Vector2) #expand {
        rotated := rotate(direction, cast(float, camera_yaw_target));
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

    player := *_Player[0];
    
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

    //          -berk, 2025 - 1 - 22

    // @TODO Add pulling blocks next to you, not just in the opposite direction of where
    // you are moving (I'm pretty sure we want this)


    new_player_position := player.position + push_direction;


    pushed_in_bounds, pushed_index := get_3d_index(new_player_position, level_position, level_size);
    if !pushed_in_bounds return;

    if !player_can_move_through_blocks {
        moving_block_data: [2] *Block;
        moving_blocks: [..] *Block;
        moving_blocks.allocated = 2;
        moving_blocks.data = moving_block_data.data;

        pushed_eid := collision[pushed_index];
        if pushed_eid {
            e := get_entity(level, pushed_eid);

            if e.type == .Enemy return;

            if e.type == .Block {
                pushed_block := as(e, Block);
                if pushed_block.block_type != .MOVING return;
                append_no_resize(*moving_blocks, pushed_block);
            }
        }



        
        if flags & .PULLING {
            pulled_in_bounds, pulled_index := get_3d_index(player.position - push_direction, level_position, level_size);
            if pulled_in_bounds {
                pulled_eid := collision[pulled_index];
                if pulled_eid {
                    pulled_block := as(get_entity(level, pulled_eid), Block);
                    if pulled_block 
                    && pulled_block.block_type == .MOVING
                    && !contains(*moving_blocks, pulled_block) {
                        append_no_resize(*moving_blocks, pulled_block);
                    }
                }
            }
        }
        
        for moving_blocks {
            remove_block_from_collision(level, it);
        }

        for moving_blocks {
            it.position += push_direction;
            if add_block_to_collision(level, it) != .OK {

                // Undo everything we just tried to do
                it.position -= push_direction;
                for #v2 < 0..it_index-1 {
                    block := moving_blocks[it];
                    remove_block_from_collision(level, block);
                    block.position -= push_direction;
                }

                for moving_blocks {
                    assert(add_block_to_collision(level, it) == .OK);
                }

                return;
            }
        }
    }
    
    // @TODO: Add a fade effect when you exit the level.
    if camera_mode == .FOCUS_ON_PLAYER {
        using camera.focus_on_player;
        focus_old = lerp(focus_old, to_vector3(player.position), focus_interp);
        focus_interp = 0;
    }

    player.position = new_player_position;
    /*
        for * _Exit {
            if player.position == it.position {
                free_level(level, level_arena);
                assert(load_level_part_1_deserialize(LEVELS[0], level, level_arena));
                load_level_part_2_init_unserialized_fields(LEVELS[0], level, level_arena);
                load_level_part_3_for_game(level, level_arena);
                break;
            }
        }
    }
    */
}


level_update :: (using level: *Level, dt: float) {
    using context.game_context;

    dt *= dt_modifier;
    
    CAMERA_YAW_TIME :: 1.0 / 12.0;
    camera_yaw_interp = min(camera_yaw_interp + dt / CAMERA_YAW_TIME, 1);

    CAMERA_PITCH_TIME :: 1.0 / 16.0;
    camera_pitch_interp = min(camera_pitch_interp + dt / CAMERA_PITCH_TIME, 1);

    CAMERA_FOCUS_TIME :: 1.0 / 8.0;
    if camera_mode == .FOCUS_ON_PLAYER {
        using camera.focus_on_player;
        focus_interp = min(focus_interp + dt / CAMERA_FOCUS_TIME, 1);
    }
    
    // I commented this out because I want to experiement with a purely floodfill-based visibility mechanic.
    // I will see if this turns out to be a bad idea.

    /*

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

    //      -berk, 2025 - 2 - 3


    for :iterate_vector3i level_size {
        viewed[it_index] &= ~(.VISIBLE | .QUEUED_FOR_FLOODFILL);
    }
    
    mark := get_mark(*frame_arena);
    defer restore_mark(*frame_arena, mark);
    positions := alloc_view(*frame_arena, level_size.x * level_size.y * level_size.z, struct {index: s64; position: Vector3i;}, zero_init=false);
    position_count := 1;
    
    player := *_Player[0];

    player_success, player_index := get_3d_index(player.position, level_position, level_size);
    assert(player_success);
    positions[0] = .{player_index, player.position};
    viewed[player_index] |= .QUEUED_FOR_FLOODFILL;
    
    end := to_vector3(player.position) + Vector3.{0.5, 0.5, 0.5};
    while position_count != 0 {
        position_count -= 1;
        using index_and_position := positions[position_count];

        start := to_vector3(position) + Vector3.{0.5, 0.5, 0.5};
        
        visitor :: (position: Vector3i, using level: *Level) -> terminate_raycast: bool {
            in_bounds, index := get_3d_index(position, level_position, level_size);
            if !in_bounds return false;
            eid := collision[index];
            if is_null(eid) return false;
            return as(eid, Block) != null;
        }
        
        if raycast(start, end, visitor, level) continue;

        viewed[index] |= (.SEEN | .VISIBLE);

        check_position :: (p: Vector3i) #expand {
            in_bounds, index := get_3d_index(p, level_position, level_size);
            if !in_bounds || (viewed[index] & .QUEUED_FOR_FLOODFILL) return;
            eid := collision[index];
            if as(eid, Block) return;
            viewed[index] |= .QUEUED_FOR_FLOODFILL;
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
    */
    
    player := *_Player[0];

    for :iterate_vector3i level_size {
        viewed[it_index] &= ~(.VISIBLE | .QUEUED_FOR_FLOODFILL);
    }

    mark := get_mark(*frame_arena);
    defer restore_mark(*frame_arena, mark);
    // Should this instead be stashed in the data structure for the level so we know how much memory is being used?
    positions := alloc_view(*frame_arena, level_size.x * level_size.y * level_size.z, Vector3i, zero_init=false);
    position_count := 1;

    player_success, player_index := get_3d_index(player.position, level_position, level_size);
    assert(player_success);
    positions[0] = player.position;
    viewed[player_index] |= (.QUEUED_FOR_FLOODFILL | .SEEN | .VISIBLE);

    viewed_start := player.position;
    viewed_end := player.position;

    while position_count {
        position_count -= 1;
        position := positions[position_count];

        check_axis :: (i: int) #expand {
            check_position :: (position: Vector3i) -> bool #expand {
                success, index := get_3d_index(position, level_position, level_size);
                if success && !(viewed[index] & .QUEUED_FOR_FLOODFILL) {
                    eid := collision[index];
                    if !eid || get_entity(level, eid).type != .Block {
                        viewed[index] |= (.QUEUED_FOR_FLOODFILL | .SEEN | .VISIBLE);
                        positions[position_count] = position;
                        position_count += 1;
                        return true;
                    }
                }
                return false;
            }

            p := position;
            p.component[i] += 1;
            if check_position(p) {
                viewed_end.component[i] = max(p.component[i], viewed_end.component[i]);
            }

            n := position;
            n.component[i] -= 1;
            if check_position(n) {
                viewed_start.component[i] = min(n.component[i], viewed_start.component[i]);
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

        memset(desired_enemy_moves.data, xx Desired_Enemy_Move.EMPTY, byte_count(desired_enemy_moves));

        for * _Enemy {  
            desired_direction := facing_vector3i(it.facing);

            in_bounds, index := get_3d_index(it.position + desired_direction, level_position, level_size);
            
            if !in_bounds || (collision[index] && get_entity(level, collision[index]).type == .Block) { // The block in front of you is blocked
                // Try the favored side
                new_facing: Facing;

                if #complete it.favored_direction == {
                    case .LEFT;
                        new_facing = facing_left(it.facing);
                    case .RIGHT;    
                        new_facing = facing_right(it.facing);
                }

                new_desired_direction := facing_vector3i(new_facing);
                in_bounds, index = get_3d_index(it.position + new_desired_direction, level_position, level_size);
                

                if !in_bounds || (collision[index] && get_entity(level, collision[index]).type == .Block) {
                    // Try the disfavored side
                    if #complete it.favored_direction == {
                        case .LEFT;
                            new_facing = facing_right(it.facing);
                        case .RIGHT;
                            new_facing = facing_left(it.facing);
                    }

                    new_desired_direction = facing_vector3i(new_facing);
                    in_bounds, index = get_3d_index(it.position + new_desired_direction, level_position, level_size);

                    if !in_bounds || (collision[index] && get_entity(level, collision[index]).type == .Block) {
                        // Try behind you
                        new_facing = facing_opposite(it.facing);
                        
                        new_desired_direction := facing_vector3i(new_facing);
                        in_bounds, index = get_3d_index(it.position + new_desired_direction, level_position, level_size);
                        
                        if !in_bounds || collision[index] && get_entity(level, collision[index]).type == .Block {
                            it.desired_position = it.position;
                        } else {
                            it.desired_position = it.position + new_desired_direction;
                            it.facing = new_facing;
                        }
                    } else {
                        it.desired_position = it.position + new_desired_direction;
                        it.facing = new_facing;
                    }
                } else {
                    it.desired_position = it.position + new_desired_direction;
                    it.facing = new_facing;
                }
            } else {
                it.desired_position = it.position + desired_direction;
            }

            in_bounds, index = get_3d_index(it.desired_position, level_position, level_size);
            assert(in_bounds);
            
            if #complete desired_enemy_moves[index] == {
                case .EMPTY;
                    desired_enemy_moves[index] = .WILL_BE_FILLED;
                case .WILL_BE_FILLED;
                    desired_enemy_moves[index] = .MUTUAL_ANNIHILATION;
                case .MUTUAL_ANNIHILATION;
                    // Do nothing because this enemy will be destroyed too.
            }
        }

        for * _Enemy_Spawner {
            in_bounds, index := get_3d_index(it.position, level_position, level_size);
            assert(in_bounds);
            
            // Flip the favored direction every tick
            it.favored_direction = ifx it.favored_direction == .LEFT then .RIGHT else .LEFT;

            if collision[index] && get_entity(level, collision[index]).type == .Block continue;
 
            // @Copypasta from above
            if #complete desired_enemy_moves[index] == {
                case .EMPTY;
                    desired_enemy_moves[index] = .WILL_BE_FILLED;
                case .WILL_BE_FILLED;
                    desired_enemy_moves[index] = .MUTUAL_ANNIHILATION;
                case .MUTUAL_ANNIHILATION;
                    // Do nothing because this enemy will be destroyed too.
            }
        }
       
        
        // @Speed this is very dumb that this array is so big.
        memset(enemy_move_results.data, xx Enemy_Move_Result.NOTHING, byte_count(enemy_move_results));

        // Remove all the enemies from the collision to make sure that when we reinsert them, all of the old ones
        // have been cleaned up. Otherwise, if we cleared the filled[index] of the old enemy position,
        // a new enemy could already be there!
        for * _Enemy {
            in_bounds, index := get_3d_index(it.position, level_position, level_size);
            assert(in_bounds);
            assert(collision[index] == it.eid);
            collision[index] = 0;
        }

        for * _Enemy {  
            in_bounds, index := get_3d_index(it.desired_position, level_position, level_size);
            assert(in_bounds);

            if #complete desired_enemy_moves[index] == {
                case .EMPTY;
                    assert(false);

                case .WILL_BE_FILLED;
                    it.state = .MOVING;
                    it.moving_from = to_vector3(it.position);
                    it.position = it.desired_position;
                    assert(collision[index] == 0);
                    collision[index] = it.eid;

                case .MUTUAL_ANNIHILATION;
                    if enemy_move_results[index] == .NOTHING {
                        enemy_move_results[index] = .MUTUAL_ANNIHILATION_HAPPENED;
                        append_no_resize(*enemy_annihilations).* = it.desired_position;
                    }
                    delete_entity(level, it.eid);
                    it_index -= 1; // @Hack so the loop respects that we've deleted the entity.
            }
        }

        for * _Enemy_Spawner {
            in_bounds, index := get_3d_index(it.position, level_position, level_size);
            assert(in_bounds); 
            if #complete desired_enemy_moves[index] == {
                case .EMPTY;
                    assert(collision[index] && get_entity(level, collision[index]).type == .Block);

                case .WILL_BE_FILLED;
                    e := make_entity(level, Enemy);
                    e.position = it.position;
                    e.state = .SPAWNING;
                    e.favored_direction = it.favored_direction;
                    e.facing = it.facing;
                    assert(collision[index] == 0);
                    collision[index] = e.eid;

                case .MUTUAL_ANNIHILATION;
                    // @TODO: If two enemy spawners end up on the same square
                    // (The player pushed a block with an enemy spawner attached
                    // into it), we need a special effect for this situation.
            }
        }
    }
    
    if enemy_timer >= Enemy.MOVING_TIME {
        for * _Enemy {
            if it.state == .MOVING it.state = .IDLE;
        }
    }

    if enemy_timer >= Enemy.SPAWNING_TIME {
        for * _Enemy {
            if it.state == .SPAWNING it.state = .IDLE;
        }
    }

    if enemy_timer >= Enemy.ANNIHILATION_TIME {
        enemy_annihilations.count = 0;
    }
    
    update_view_texture(*view_texture, level_size, viewed);



    //
    // Update the camera matrix
    //

    {
        offset_matrix: Matrix4;
        position_matrix: Matrix4;
        
        CAMERA_MIN_DISTANCE :: 12.0;
        get_focused_camera :: (position: Vector3i, size: Vector3i, distance: float) -> offset_matrix: Matrix4, position_matrix: Matrix4 {
            radius := max(size.x, max(size.y, size.z));
            camera_distance := radius * distance;
            camera_distance = max(CAMERA_MIN_DISTANCE, camera_distance);
            offset_matrix := make_translation_matrix4(.{0, 0, camera_distance});

            focus := to_vector3(position) + to_vector3(size) / 2;
            position_matrix := make_translation_matrix4(-focus);

            return offset_matrix, position_matrix;
        }


        if camera_mode == {
            case .FOCUS_ON_PLAYER;
                using camera.focus_on_player;
                camera_offset := Vector3.{0, 0, CAMERA_MIN_DISTANCE};
                offset_matrix = make_translation_matrix4(camera_offset);

                player := *_Player[0];
                focus_target := to_vector3(player.position);
                focus := lerp(focus_old, focus_target, focus_interp);
                position_matrix = make_translation_matrix4(-focus - Vector3.{0.5, 0.5, 0.5});

            case .FOCUS_ON_LEVEL;
                // :LevelSizeInEditor
                offset_matrix, position_matrix = get_focused_camera(level_position, level_size, 1.8);

            case .FOCUS_ON_FLOODFILL;
                viewed_size := viewed_end - viewed_start + Vector3i.{1, 1, 1};
                offset_matrix, position_matrix = get_focused_camera(viewed_start, viewed_size, 1.8);
        }


        pitch := get_camera_pitch(level);
        pitch_matrix := make_x_rotation_matrix(Matrix4, -pitch);
        
        yaw_matrix := make_y_rotation_matrix(Matrix4, xx -get_camera_yaw(level));
        
        camera_matrix = multiply(FRUSTUM, multiply(offset_matrix, multiply(pitch_matrix, multiply(yaw_matrix, position_matrix))));
    }
}
