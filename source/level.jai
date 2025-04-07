Level :: struct {
    using types: Entity_Types;
    
    name: string; @NoSerialize // The file name

    // @TODO: This should be a hash table... probably.
    entities: [..] *Entity; @NoSerialize
    unused_eids: [..] Entity_Id; @NoSerialize
    
    // These are gameplay-only variables. In the future, we might want to better-differentiate
    // between what is modifiable in the editor (which should be as close as we can get to a 
    // pure-data representation of the scene) and what is gameplay state. We could use
    // metaprogramming to do this but it seems like overkill right now.

    using gameplay: struct {
        level_position: Vector3i;
        level_size: Vector3i;

        mutual_annihilations: [..] Mutual_Annihilation;

        flags: enum_flags {PULLING; DEBUG_MOVEMENT;};
        
        camera_mode: Camera_Mode;

        // These members are only used by the NEAR and FAR camera states.
        // Maybe they should be in the Player struct?
        
        camera_focus_x: s32;
        camera_focus_z: s32;
        camera_focus_old_x: float;
        camera_focus_old_z: float;
        camera_focus_x_interp := 1.0;
        camera_focus_z_interp := 1.0;

        camera_landing_interp: float;

        camera_pitch_ticks: s8 = 1;
        camera_pitch_interp := 1.0;
        camera_pitch_old: float64;

        camera_yaw_target: float64;
        camera_yaw_old: float64;
        camera_yaw_interp := 1.0;
        
        enemy_timer: float;
        dt_modifier := 1.0;
        
        doors: [] Entity_Id; // Only Door entities should be put in here.
        collision: [] Entity_Id;
        desired_collision: [] Entity_Id;
        viewed: [] View_State;

        
        // These are stored SOA because we don't want to touch these at the same time.
        // @TODO 3d arrays are stored x-major, then z, then y.
        // This makes sense from the perspective of wanting to be
        // able to type levels directly into code for this initial
        // development period, but may make less sense later.
        // Consider coming back to this.

        view_texture: View_Texture;
        

        // @Temporary This is very basic, just to get sound to work for now.
        playing_sound_count: int;
        playing_sounds: [1024] Playing_Sound;
            
        // :Checkpoint
        current_data: [] u8;
        checkpoint: Entity_Id;
        checkpoint_data: [] u8;
    } @NoSerialize

    editor: struct {
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
                deletion: bool;
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
    } @NoSerialize
}


CAMERA_PITCH_TICK_COUNT :: 5; // Starts at zero
CAMERA_MIN_PITCH :: -PI / 2;
CAMERA_MAX_PITCH :: PI / 2;

CAMERA_YAW_TICK_COUNT :: 12;

PLAYERLIKE_SPAWNING_TIME :: 0.2;

Camera_Mode :: enum {
    NEAR;
    FAR;
    LEVEL;
    COUNT;
}


// I pulled this stuff out because I plan to eventually share it with the enemies.
Playerlike_State :: enum {
    GROUND;
    // MOVING;
    SPAWNING;
    FALLING;
    DEAD;
}


Playerlike :: struct {
    state: Playerlike_State;
    union { 
        spawning: struct {
            interp: float;
        }
        falling: struct {
            interp: float;
            last_floor_y: s32;
        }
        ground: struct {
            landing_interp: float;
        }
        moving: struct {
            from: Vector3i;
            interp: float;
        }
        dead: struct {
            interp: float;
        }
    }
}


Player :: struct {
    using #as e: Entity;
    using playerlike: Playerlike; @NoSerialize
    COLOR :: Vector4.{1, 1, 1, 1};
}


Checkpoint :: struct {
    using #as e: Entity;
    
    ACTIVE_COLOR :: Vector4.{1, 1, 1, 1};
    COLOR :: Vector4.{0.5, 0.5, 0.5, 1};
}


Exit :: struct {
    using #as e: Entity;
    COLOR :: Vector4.{146.0/255.0, 1, 118.0/255.0, 1};
}


Enemy_State :: enum u8 {
    IDLE;
    FALLING;
}


// I did this so we could have a concrete way to see what gameplay direction something is facing.
// It might be better to just have a rotation quaternion on the entity. Let's see what happens.
Facing :: enum u8 {
    X_POSITIVE; // The default, assumed orientation
    Z_POSITIVE;
    X_NEGATIVE;
    Z_NEGATIVE;
}
FACING_COUNT :: Facing.Z_NEGATIVE + 1;
// This is separate from FACING because we want to expose
// "facing" in the editor.


facing_to_vector3i :: (f: Facing) -> Vector3i {
    v := Vector3i.{};
    if f == {
        case .X_POSITIVE; v.x += 1;
        case .Z_POSITIVE; v.z += 1;
        case .X_NEGATIVE; v.x -= 1;
        case .Z_NEGATIVE; v.z -= 1;
    }
    return v;
}


vector3i_to_facing :: (v: Vector3i) -> Facing {
    assert(v.y == 0);
    assert((v.x != 0 && v.z == 0) || (v.x == 0 && v.z != 0));
    if v.x > 0 return .X_POSITIVE;
    if v.x < 0 return .X_NEGATIVE;
    if v.z > 0 return .Z_POSITIVE;
    if v.z < 0 return .Z_NEGATIVE;
    assert(false);
    return 0;
}

facing_to_matrix4 :: (f: Facing) -> Matrix4 {
    rotation: float;
    if f == {
        case .X_POSITIVE;
        case .Z_NEGATIVE; rotation = PI / 2;
        case .X_NEGATIVE; rotation = PI;
        case .Z_POSITIVE; rotation = -PI / 2;
        case; assert(false);
    }
    
    return make_y_rotation_matrix(Matrix4, -rotation);
}


facing_right :: inline (f: Facing) -> Facing {
    return (f - 1 + FACING_COUNT) % FACING_COUNT;
}


facing_left :: inline (f: Facing) -> Facing {
    return (f + 1) % FACING_COUNT;
}


facing_opposite :: inline (f: Facing) -> Facing {
    return (f + 2) % FACING_COUNT;
}


Favored_Direction :: enum u8 {
    RIGHT;
    LEFT;
}

Enemy_Vfx_Modifiers :: enum_flags u8 {
    SPAWNING;
    FALLING;
    MOVING;
}


Enemy :: struct {
    using #as e: Entity;
    
    favored_direction: Favored_Direction;
    facing: Facing;

    vfx_modifiers: Enemy_Vfx_Modifiers; @NoSerialize
    moving_from: Vector3; @NoSerialize
    state: Enemy_State; @NoSerialize

    result_state: enum u8 {
        ALIVE;
        OUT_OF_BOUNDS; // The enemy won't be in the new collision map

        PRIMARY_ANNIHILATOR;
        // This will stay in the new collision map. I do this so that we can check if the player
        // annihilated with anything. Maybe it would be better to have the player in the collision
        // map and have desired_position / result_state on the player?

        SECONDARY_ANNIHILATOR; // The enemy won't be in the new collision map.
    }; @NoSerialize
    
    /*
    desired: struct {
        position: Vector3i;
        vfx_modifiers: Enemy_Vfx_Modifiers
    } @NoSerialize
    */

    desired_vfx_modifiers: Enemy_Vfx_Modifiers; @NoSerialize
    desired_position: Vector3i; @NoSerialize
}


LEFT_ENEMY_COLOR :: Vector4.{0, 68.0 / 255.0, 166.0 / 255.0, 1};
RIGHT_ENEMY_COLOR :: Vector4.{1, 0, 0, 1};
ENEMY_TICK_TIME :: 0.8;
FALLS_PER_ENEMY_TICK :: 3;

ENEMY_MOVING_VFX_TIME :: 0.1;
ENEMY_FALLING_VFX_TIME :: 0.05;

Enemy_Spawner_Type :: enum {
    ALTERNATING;
    ALL_RIGHT;
    ALL_LEFT;
}


Enemy_Spawner :: struct {
    using #as e: Entity;
    
    enemy_spawner_type: Enemy_Spawner_Type;
    alternating_direction: Favored_Direction; @NoSerialize
    facing: Facing;

    COLOR :: Vector4.{0.5, 0, 0, 1};
}


Enemy_Despawner :: struct {
    using #as e: Entity;
    COLOR :: Vector4.{1, 1, 1, 1};
}


Block :: struct {
    using #as e: Entity;

    size: Vector3i; @NoEditor
    filled: [] bool; // :BitArray
    color: Vector4; @Color
    moveable: bool;
    mesh: Mesh; @NoSerialize // :BitArray
    desired_position: Vector3i; @NoSerialize // Temporary variable that's only used when the block is pushed / pulled
}


Door :: struct {
    using #as e: Entity;

    size: Vector3i; @NoEditor
    filled: [] bool; // :BitArray
    mesh: Mesh; @NoSerialize

    COLOR :: Vector4.{1, 0.5, 0.5, 1};
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


Mutual_Annihilation :: struct {
    position: Vector3i;
    interp: float;
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


is_colliding_below :: (using level: *Level, position: Vector3i) -> bool {
    below := position;
    below.y -= 1;
    in_bounds, index := get_3d_index(below, level_position, level_size);
    if !in_bounds return false;
    eid := collision[index];
    if eid == 0 return false;
    e := get_entity(level, eid);
    return e.type == .Block;
}


load_level_part_1_deserialize :: (level_name: string, arena: *Memory_Arena) -> *Level {
    using context.game_context;
    
    scope_mark(*frame_arena);

    success, data := read_file(level_name, *frame_arena);
    if !success {
        log(.ERROR, "Could not read the file \"%\"\n", level_name); 
        return null;
    } 
    
    return load_level_part_1_deserialize_mem(data, arena);
}


load_level_part_1_deserialize_mem :: (data: string, arena: *Memory_Arena) -> *Level {
    assert(arena.current == 0);

    mark := get_mark(arena);

    level := alloc(arena, Level); 
    err := deserialize(data, level, arena);
    if !err.ok {
        log(.ERROR, "Encountered an error while deserializing level at byte %,%: %\n", err.loc.start, err.loc.count, err.message);
        restore_mark(arena, mark);
        return null;
    }

    return level;
}


serialize_level :: (using level: *Level) {
    using context.game_context;
    buf: [100000] u8 = ---;
    str := serialize(buf, level);
    assert(write_file(level.name, str));
}


load_level_part_2_init_unserialized_fields :: (level_name: string, using level: *Level, for_mode: Game_Mode, arena: *Memory_Arena) -> gameplay_mode_load_succeeded: bool {
    name = copy_string(arena, level_name);
   
    // Give each entity an Entity_Id
    entity_count := 1;
    #insert -> string {
        buf: [1024] u8;
        sb := make_string_builder(buf);
        for ENTITIES {
            print(*sb, "for * _% {\n", it.name);
            print(*sb, "    it.eid = xx entity_count;\n");
            print(*sb, "    it.type = .%;\n", it.name);
            print(*sb, "    entity_count += 1;\n");
            print(*sb, "}\n");
        }
        return get_string(*sb);
    }
    
    for * _Block {
        it.mesh = make_gridlike_mesh(it.size, it.filled, arena);
    }

    for * _Door {
        it.mesh = make_gridlike_mesh(it.size, it.filled, arena);
    }

    if #complete for_mode == {
        case .EDITOR;
            entities = alloc_array(arena, entity_count, *Entity, zero_init = false);
            entities[0] = null;

            for :iterate_entities types {
                entities[it.eid] = it;
            }

            editor.camera_yaw = 0;
            editor.camera_pitch = -PI / 3;

            if _Block.count != 0 {
                // :LevelSizeInEditor
                // It makes me slightly uncomfortable at how this code overlaps with the 
                // gameplay code but we don't have access to the level size in the editor.

                position, size := get_block_extents(_Block);
                level_center := to_vector3(position) + to_vector3(size) / 2;
                level_radius := cast(float, max(size.x, max(size.y, size.z)));

                camera_distance := level_radius * 2;
                camera_y := sin(PI / 3) * camera_distance;
                camera_z := cos(PI / 3) * camera_distance;

                editor.camera_position = .{level_center.x, level_center.y + camera_y, level_center.z - camera_z};
            }
            return true;

        case .GAMEPLAY;
            level_position, level_size = get_block_extents(_Block);
            size_1d := level_size.x * level_size.y * level_size.z;
            // @Hack @Speed @Memory
            // This is a dumb workaround.
            // Right now, the serialization system will allocate as many elements as was serialized for an array.
            // We want to allocate custom sizes, which are as many as you will ever need, so we can not ever
            // dynamically allocate memory while the a level is running, and we can easily know how much memory the
            // game will ever use (when we're in the GAMEPLAY mode. When we're in the EDITOR mode, do whatever you want.)
            alloc_extra_array_capacity(arena, *_Enemy, size_1d, zero_init=false);

            // Count up all the entities so we can allocate an array big enough
            // to hold pointers to all of them for the Entity_Id system
            // The first slot is null, so we start at 1.

            reserved := 1;
            count := 1;
            #insert -> string {
                buf: [1024] u8;
                sb := make_string_builder(buf);
                for ENTITIES {
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
            doors = alloc_view(arena, size_1d, Entity_Id);
            collision = alloc_view(arena, size_1d, Entity_Id);
            desired_collision = alloc_view(arena, size_1d, Entity_Id);
            mutual_annihilations = reserve_array(arena, size_1d, Mutual_Annihilation);

            for * _Block {  
                assert(add_block_to_collision(level, it) == .OK);
            }

            for * door: _Door {
                offset := door.position - level_position;
                for :iterate_vector3i door.size {
                    success, index := get_3d_index(it + offset, level_size);
                    if !success {
                        log(.ERROR, "There was a Door entity outside of the level's bounding box.\n");
                        return false;
                    }
                    
                    // We don't care about overlapping door entities right now.
                    // Maybe we will care about them in the future.
                    doors[index] = door.eid;
                }
            }
            
            for * _Enemy {
                in_bounds, index := get_3d_index(it.position, level_position, level_size);

                if !in_bounds {
                    log(.ERROR, "There was a Enemy entity outside of the level's bounding box.\n");
                    return false;
                }
                
                if collision[index] != 0 {
                    log(.ERROR, "There is an overlap between an Enemy entity and something else at (%, %, %)\n", it.position.x, it.position.y, it.position.z);
                    return false;
                }

                collision[index] = it.eid;
            }

            if _Player.count != 1 {
                log(.ERROR, "There was no player entity in the serialized level \"%\".\n", level.name);
                return false;
            }

            player := *_Player[0];
            set_state(player, .SPAWNING);
            camera_focus_x = player.position.x;
            camera_focus_z = player.position.z;
            
            // :Checkpoint
            current_data = .{arena.current, xx level};
            checkpoint_data = alloc_view(arena, current_data.count, u8, zero_init = false);
            memcpy(checkpoint_data.data, current_data.data, current_data.count);

            return true;
    }
}


free_level :: (using level: *Level, level_arena: *Memory_Arena) {   
    // @TODO This is a far-in-the-future kind of thing.
    // We should wrap glGenBuffers, glDeleteBuffers, and similar allocating functions and make a memory debugger
    // that tells us what has leaked when we close the application, because as far as I can tell, there's no good
    // way to natively get that information from OpenGL.

    free(*view_texture);

    for * _Block {
        free(*it.mesh);
    }

    for * _Door {
        free(*it.mesh);
    }

    clear(level_arena);
}


get_enemy_draw_info :: (level: *Level, enemy: *Enemy) -> model_to_world: Matrix4, bitmap: GLuint {
    using context.game_context;

    matrix := Matrix4_Identity;
    
    // Positional modifications happen "after" scale modifications to rotation matricies,
    // so code that changes the matrix position should go first.

    if enemy.vfx_modifiers & .MOVING {
        weight := level.enemy_timer / ENEMY_MOVING_VFX_TIME;
        weight = weight * weight;
        position := (to_vector3(enemy.position) - enemy.moving_from) * (1 - weight);
        matrix = make_translation_matrix4(-position);
    }

    if enemy.vfx_modifiers & .FALLING {
        weight := 1 - fmod_cycling(level.enemy_timer, ENEMY_TICK_TIME / FALLS_PER_ENEMY_TICK) / ENEMY_FALLING_VFX_TIME;
        weight = weight * weight;
        matrix = make_translation_matrix4(.{0, weight, 0}) * matrix;
    }

    if enemy.vfx_modifiers & .SPAWNING {
        weight := level.enemy_timer / PLAYERLIKE_SPAWNING_TIME;
        matrix = make_scale_matrix4(.{weight, weight, weight}) * matrix;
    }


    matrix = matrix * facing_to_matrix4(enemy.facing);
    matrix = make_translation_matrix4(to_vector3(enemy.position) + Vector3.{0.5, 0.5, 0.5}) * matrix;

    
    bitmap: GLuint;
    if #complete enemy.favored_direction == {
        case .LEFT;
            bitmap = enemy_left_bitmap;
        case .RIGHT;
            bitmap = enemy_right_bitmap;
    };

    return matrix, bitmap;
}


get_player_draw_info :: (player: *Player) -> model_to_world: Matrix4 {
    scale: Matrix4;
    position: Vector3;
    if #complete player.state == {
        case .GROUND; #through;
        case .FALLING;
            scale = Matrix4_Identity;
            position = to_vector3(player.position);
        /*
        case .MOVING;
            scale = Matrix4_Identity;
            position = lerp(to_vector3(player.moving.from), to_vector3(player.position), player.moving.interp);
        */
        case .SPAWNING;
            weight := player.spawning.interp;
            scale = make_scale_matrix4(.{weight, weight, weight});
            position = to_vector3(player.position);
        case .DEAD;
            weight := 1 - player.dead.interp;
            scale = make_scale_matrix4(.{weight, weight, weight});
            position = to_vector3(player.position);
    }
    return make_translation_matrix4(to_vector3(player.position) + Vector3.{0.5, 0.5, 0.5}) * scale;
}


get_enemy_spawner_draw_info :: (enemy_spawner: Enemy_Spawner) -> model_to_world: Matrix4, color: Vector4 {
    color: Vector4;
    if #complete enemy_spawner.enemy_spawner_type == {
        case .ALTERNATING;
            color = .{0, 0.5, 0, 1}; // @TODO: We should have alternating stripes or something on the enemy spawner
        case .ALL_RIGHT;
            color = RIGHT_ENEMY_COLOR;
            color.xyz /= 2;
        case .ALL_LEFT;
            color = LEFT_ENEMY_COLOR;
            color.xyz /= 2;
    }

    matrix := facing_to_matrix4(enemy_spawner.facing);
    matrix = make_translation_matrix4(to_vector3(enemy_spawner.position) + Vector3.{0.5, 0, 0.5}) * matrix;
    return matrix, color;
}


play_sound :: (using level: *Level, wav: *Wav) {
    if playing_sound_count == playing_sounds.count return;
    playing_sounds[playing_sound_count] = .{wav=wav};
    playing_sound_count += 1;
}


set_state :: (player: *Player, state: Playerlike_State) {
    if #complete state == {
        case .GROUND;
            if player.state == .FALLING {
                player.ground.landing_interp = player.falling.interp;
            } else {
                player.ground.landing_interp = 1;
            }
        case .FALLING;
            if player.state == .GROUND {
                player.falling.last_floor_y = player.position.y;
                player.falling.interp = 0;
            } else {
                player.falling.last_floor_y = -100000;
                // This is set to -100000 in case something weird happens.
                // This value shouldn't matter when player.falling.interp == 1.
                player.falling.interp = 1;
            }
        case .DEAD;
            player.dead.interp = 0;
        case .SPAWNING;
            player.spawning.interp = 0;
    }
    player.state = state;
}


// This takes in all the entities that have a "desired_position", and tries to apply them.
use_desired_positions :: (using level: *Level) -> bool {
    using context.game_context;

    memset(desired_collision.data, 0, byte_count(desired_collision));

    for * block: _Block {
        offset := block.desired_position - level_position;

        for :iterate_vector3i block.size {
            if !block.filled[it_index] continue;
            in_bounds, index := get_3d_index(it + offset, level_size);
            if !in_bounds return false;
            if desired_collision[index] != 0 return false;

            desired_collision[index] = block.eid;
        }
    }

    
    for * _Enemy {
        it.result_state = .ALIVE; // A baseline state. Set this to something if it needs to be something else.

        in_bounds, index := get_3d_index(it.desired_position, level_position, level_size);
        
        if !in_bounds {
            if it.desired_position.y < level_position.y {
                it.result_state = .OUT_OF_BOUNDS;
                continue;
            } else {
                return false;
            }
        }

        eid := desired_collision[index];
        if eid == 0 {
            desired_collision[index] = it.eid;
            continue;
        }


        e := get_entity(level, eid);
        if e.type == {
            case .Enemy;
                other_enemy := as(e, Enemy);
                // The enemy in the collision will be the PRIMARY_ANNIHILATOR.
                // The secondary ones aren't ever added to the collision map.
                other_enemy.result_state = .PRIMARY_ANNIHILATOR;
                it.result_state = .SECONDARY_ANNIHILATOR;
            case .Block;
                return false;
        }
    }
   


    // If we got to here, then that means the move is valid and we can do the update.



    temp := collision;
    collision = desired_collision;
    desired_collision = temp;
    

    // If there's an enemy where the player is, even if that enemy is to be mutually annihilated,
    // then the player has died.

    player := *_Player[0];
    if !(flags & .DEBUG_MOVEMENT) {
        if #complete player.state == {
            case .SPAWNING; #through;
            case .GROUND; #through;
            case .FALLING;
                player_in_bounds, player_index := get_3d_index(player.position, level_position, level_size);
                assert(player_in_bounds);
                if collision[player_index] {
                    e := get_entity(level, collision[player_index]);
                    if e.type == {
                        case .Enemy;
                            set_state(player, .DEAD);
                        
                        case .Block;
                            // :PlayerInsideBlock

                        case;
                            assert(false);
                    }
                }

            case .DEAD;
                // Don't do anything because the player has already died.
        }
    }

    for * _Block {
        it.position = it.desired_position;
    }

    for * _Enemy {
        if #complete it.result_state == {
            case .ALIVE;
                it.vfx_modifiers |= it.desired_vfx_modifiers;
                it.position = it.desired_position;

                if #complete it.state == {
                    case .IDLE;
                        if !is_colliding_below(level, it.position) {
                            it.state = .FALLING;
                        }
                    case .FALLING;
                        if is_colliding_below(level, it.position) {
                            it.state = .IDLE;
                        }
                }

            case .OUT_OF_BOUNDS;
                // We currently use the shader that doesn't draw things if they are outside the level.
                // I am assuming that enemies only fall out of the bottom of the level when this is true.
                // Therefore, we should draw the annihilation only at the enemy's old position.
                append_no_resize(*mutual_annihilations, .{position = it.position});
                delete_entity(level, it.eid);
                it_index -= 1; // :DeleteEntityInLoop
                
            case .PRIMARY_ANNIHILATOR;
                it.position = it.desired_position;
                in_bounds, index := get_3d_index(it.position, level_position, level_size);
                assert(in_bounds);
                assert(collision[index] == it.eid);
                append_no_resize(*mutual_annihilations, .{position = it.position});
                collision[index] = 0;
                delete_entity(level, it.eid);
                it_index -= 1; // :DeleteEntityInLoop

            case .SECONDARY_ANNIHILATOR;
                delete_entity(level, it.eid);
                it_index -= 1; // :DeleteEntityInLoop
        }
    }

    return true;
}


load_overworld :: (arena: *Memory_Arena, mode: Game_Mode) -> *Level {
    LEVEL :: "levels/overworld.level";
    level := load_level_part_1_deserialize(LEVEL, arena);
    assert(level != null);
    assert(load_level_part_2_init_unserialized_fields(LEVEL, level, mode, arena));
    return level;
}


gameplay_handle_input :: (using level: *Level, event: Input_Event) { 
    using context.game_context;

    if event.key == #char "C" && event.state == .DOWN {
        // :Checkpoint
        // This is how checkpoints work right now. It is very simple, but I'm not
        // sure how "scalable" it is. Because we store the entire level in a 
        // single arena, and the level takes up a fixed amount of memory when we
        // load it and never any more, it means that we can allocate another segment
        // of equal length in the same arena, and memcpy the level segment into
        // this segment whenever we want to make a checkpoint.

        // When we want to revert back to a checkpoint, we just memcpy the checkpoint
        // segment back into the level segment (We can't just swap the one we're
        // using because all the pointers in the checkpoint segment refer to
        // addresses in the level segment.

        // This is very simple, but it has a couple caveats. I don't think the
        // memory usage is _that_ bad (@Investigate), but there are some things
        // that we _know_ are immutable (such as the Block filled member) that don't
        // need to be copied. The main offender here are the vertices of the Block
        // meshes, :CpuVertices which we probably shouldn't be storing on the CPU
        // anyway.

        //          -berk, 2025 - 4 - 5.

        memcpy(current_data.data, checkpoint_data.data, checkpoint_data.count); 
        return;
    }

    if event.key == #char " " {
        if event.state == .DOWN flags |= .PULLING;
        else                    flags &= ~.PULLING;
        return;
    }

    if event.key == #char "K" && event.state == .DOWN {
        camera_pitch_old = get_camera_pitch(level);
        camera_pitch_ticks = max(camera_pitch_ticks - 1, 0);
        camera_pitch_interp = 0;
        return;
    }

    if event.key == #char "I" && event.state == .DOWN {
        camera_pitch_old = get_camera_pitch(level);
        camera_pitch_ticks = min(camera_pitch_ticks + 1, CAMERA_PITCH_TICK_COUNT);
        camera_pitch_interp = 0;
        return;
    } 
    
    if event.key == #char "L" && event.state == .DOWN {
        camera_yaw_old = get_camera_yaw(level);
        camera_yaw_interp = 0;
        camera_yaw_target -= TAU / 12;
        return;
    }
   
    if event.key == #char "J" && event.state == .DOWN {
        camera_yaw_old = get_camera_yaw(level);
        camera_yaw_interp = 0;
        camera_yaw_target += TAU / 12;
        return;
    } 

    if event.key == #char "-" && event.state == .DOWN {
        if 1.0 / 16.0 < dt_modifier dt_modifier /= 2;
        return;
    }

    if event.key == #char "=" && event.state == .DOWN {
        if dt_modifier < 16 dt_modifier *= 2;
        return;
    }

    if event.key == #char "M" && event.state == .DOWN {
        player := *_Player[0];
        if flags & .DEBUG_MOVEMENT {
            flags &= ~.DEBUG_MOVEMENT;

            in_bounds, index := get_3d_index(player.position, level_position, level_size);
            assert(in_bounds);

            if collision[index] && get_entity(level, collision[index]).type == .Enemy {
                set_state(player, .DEAD);
            } else if is_colliding_below(level, player.position) {
                set_state(player, .GROUND);
            } else {
                set_state(player, .FALLING);
            }
        } else {
            flags |= .DEBUG_MOVEMENT;
            set_state(player, .GROUND);
        }
        return;
    }

    if event.key == #char "U" && event.state == .DOWN {
       camera_mode = (camera_mode + 1) % Camera_Mode.COUNT;
        if camera_mode == {
            case .NEAR; #through;
            case .FAR;
                camera_focus_x_interp = 1;
                camera_focus_z_interp = 1;
        }
        return;
    }

    if event.state != .DOWN return;

    //
    // Player movement code
    //

    push_direction: Vector3i;
    
    if event.key == {
        case xx #char "W"; push_direction = local_to_global_direction( 0,  1, camera_yaw_target);
        case xx #char "A"; push_direction = local_to_global_direction(-1,  0, camera_yaw_target);
        case xx #char "S"; push_direction = local_to_global_direction( 0, -1, camera_yaw_target);
        case xx #char "D"; push_direction = local_to_global_direction( 1,  0, camera_yaw_target);
        case xx #char "Q"; if flags & .DEBUG_MOVEMENT push_direction.y += 1; else return;
        case xx #char "E"; if flags & .DEBUG_MOVEMENT push_direction.y -= 1; else return;
        case; return;
    }
 
    // @TODO Add pulling blocks next to you, not just in the opposite direction of where
    // you are moving (I'm pretty sure we want this)

    player := *_Player[0];
    new_player_position := player.position + push_direction;

    if flags & .DEBUG_MOVEMENT {
        assert(player.state == .GROUND);
        if inside_bounding_box(new_player_position, level_position, level_size) {
            player.position = new_player_position;
            play_sound(level, *footstep);
        }
    } else if player.state == .GROUND { 
        player_in_bounds, player_index := get_3d_index(player.position, level_position, level_size);
        assert(player_in_bounds);
        if collision[player_index] != 0 {
            // :PlayerInsideBlock
            // This could happen if you were in debug mode, then went inside of a block, then
            // came out of debug mode.
            assert(get_entity(level, collision[player_index]).type == .Block);
            return;
        }

        pushed_in_bounds, pushed_index := get_3d_index(new_player_position, level_position, level_size);
        if !pushed_in_bounds return;

        pushed_block: *Block;
        pushed_eid := collision[pushed_index];
        if pushed_eid {
            pushed_entity := get_entity(level, pushed_eid);
            maybe_pushed_block := as(pushed_entity, Block);
            if maybe_pushed_block {
                if !maybe_pushed_block.moveable return;
                pushed_block = maybe_pushed_block;
            }
        }

        pulled_block: *Block;
        if flags & .PULLING {
            pulled_in_bounds, pulled_index := get_3d_index(player.position - push_direction, level_position, level_size);
            if pulled_in_bounds {
                pulled_eid := collision[pulled_index];
                if pulled_eid {
                    pulled_entity := get_entity(level, pulled_eid);
                    maybe_pulled_block := as(pulled_entity, Block);
                    if maybe_pulled_block && maybe_pulled_block.moveable {
                        pulled_block = maybe_pulled_block;
                    }
                }
            }
        }

        if pushed_block && pushed_block == pulled_block {
            pulled_block = null;
        }

        for * _Block {
            if it == pushed_block || it == pulled_block {
                it.desired_position = it.position + push_direction;
            } else {
                it.desired_position = it.position;
            }
        }

        for * _Enemy {
            it.desired_position = it.position;
            it.desired_vfx_modifiers = 0;
        }

        push_enemies :: (block: *Block) -> bool #expand {
            offset := block.position - level_position;
            
            // @CompilerBug It's not letting be return from within the for_expansion...
            // Maybe returning things from inside of for_expansions in macroes is bugged.
            succeeded := true;

            for :iterate_vector3i block.size {
                if !block.filled[it_index] continue;

                next := it + push_direction;

                in_bounds, index := get_3d_index(next, block.size);
                if in_bounds && block.filled[index] continue;

                in_bounds, index = get_3d_index(next + offset, level_size);
                if !in_bounds {
                    succeeded = false;
                    break;
                }

                eid := collision[index];
                if eid {
                    e := get_entity(level, eid);
                    if e.type == {
                        case .Enemy;
                            enemy := as(e, Enemy);
                            enemy.desired_position += push_direction;
                            enemy.desired_vfx_modifiers = 0;
                        case .Block;
                            assert(e != block);
                            succeeded = false;
                            break;
                            // This will have to change if we add multipush
                        case; assert(false);
                    }
                }
            }
            return succeeded;
        }

        if pushed_block {
            if !push_enemies(pushed_block) return;
        }

        if pulled_block {
            if !push_enemies(pulled_block) return;
        }

        
        if !use_desired_positions(level) return;

        assert(player.state != .DEAD);
        // There's no way you could walk into mutually annhilating enemies while
        // you're pushing a block, because the only way a mutual annihilation could
        // happen is if an enemy is pushed by the block you're pushing into another
        // enemy. There is no way that can happen in the square directly in front
        // of you.
        
        player.position = new_player_position;
        play_sound(level, *footstep);

        colliding_eid := collision[pushed_index];
        if colliding_eid {
            e := get_entity(level, colliding_eid);
            if e.type == .Enemy {
                append_no_resize(*mutual_annihilations, .{position = player.position});
                collision[pushed_index] = 0;
                delete_entity(level, e.eid);
                set_state(player, .DEAD);
                return;
            }
        }

        if !is_colliding_below(level, new_player_position) {
            set_state(player, .FALLING);
        }
    }
}


GAME_FRUSTUM :: #run -> Matrix4 {
    FOV :: PI / 5;

    right := cast(float, NEAR_PLANE * tan(FOV / 2));
    top := right * cast(float, INNER_WINDOW_H) / cast(float, INNER_WINDOW_W);
     
    return make_left_handed_frustum_matrix(-right, -top, NEAR_PLANE, right, top, FAR_PLANE);
}


get_gameplay_camera_matrix :: (using level: *Level) -> Matrix4 {
    NEAR_DISTANCE :: 30.0;
    FAR_DISTANCE :: 60.0;


    player := *_Player[0];
    
    // I would rather just do this update whenever the player's position changes. However, 
    // that made the camera logic rather confusing, and I want to be able to directly set
    // the player's position normally, so I am putting it here.

    if player.position.x != camera_focus_x {
        camera_focus_old_x = lerp(camera_focus_old_x, cast(float, camera_focus_x), camera_focus_x_interp);
        camera_focus_x = player.position.x;
        camera_focus_x_interp = 0;
    }

    if player.position.z != camera_focus_z {
        camera_focus_old_z = lerp(camera_focus_old_z, cast(float, camera_focus_z), camera_focus_z_interp);
        camera_focus_z = player.position.z;
        camera_focus_z_interp = 0;
    }


    get_player_camera :: (distance: float) #expand {
        assert(camera_mode == .NEAR || camera_mode == .FAR);
        offset := Vector3.{0, 0, distance};
        offset_matrix = make_translation_matrix4(offset);

        position := to_vector3(player.position);

        x, y, z: float;

        x = lerp(camera_focus_old_x, position.x, camera_focus_x_interp);
        z = lerp(camera_focus_old_z, position.z, camera_focus_z_interp);
        
        // @TODO: We may want to have different code depending on whether the player
        // is moving upwards or downwards on a ladder vs falling. Handle those once
        // ladders are in the game.
        
        if #complete player.state == {
            case .GROUND;
                y = position.y + 1.0 - player.ground.landing_interp;
            case .FALLING;
                if player.position.y <= player.falling.last_floor_y - 1 {
                    y = position.y + 1.0 - player.falling.interp;
                } else {
                    y = xx player.falling.last_floor_y;
                }
            case .DEAD; #through;
            case .SPAWNING;
                y = position.y;
        }

        focus := Vector3.{x, y, z};
        position_matrix = make_translation_matrix4(-focus - Vector3.{0.5, 0.5, 0.5});
    }


    offset_matrix: Matrix4;
    position_matrix: Matrix4;
    if camera_mode == {
        case .NEAR;
            get_player_camera(NEAR_DISTANCE);

        case .FAR;
            get_player_camera(FAR_DISTANCE);

        case .LEVEL;
            RADIUS_MULTIPLIER :: 2.5;
            radius := max(level_size.x, max(level_size.y, level_size.z));
            camera_distance := radius * RADIUS_MULTIPLIER;
            camera_distance = max(NEAR_DISTANCE, camera_distance);
            offset_matrix = make_translation_matrix4(.{0, 0, camera_distance});

            focus := to_vector3(level_position) + to_vector3(level_size) / 2;
            position_matrix = make_translation_matrix4(-focus);
    }


    pitch := get_camera_pitch(level);
    pitch_matrix := make_x_rotation_matrix(Matrix4, -pitch);
    
    yaw_matrix := make_y_rotation_matrix(Matrix4, xx -get_camera_yaw(level));
    
    return multiply(GAME_FRUSTUM, multiply(offset_matrix, multiply(pitch_matrix, multiply(yaw_matrix, position_matrix))));
}


gameplay_level_update :: (using level: *Level, dt: float) {
    using context.game_context;

    player := *_Player[0];

    dt *= dt_modifier;
    
    CAMERA_YAW_TIME :: 1.0 / 12.0;
    camera_yaw_interp = min(camera_yaw_interp + dt / CAMERA_YAW_TIME, 1);

    CAMERA_PITCH_TIME :: 1.0 / 16.0;
    camera_pitch_interp = min(camera_pitch_interp + dt / CAMERA_PITCH_TIME, 1);

    CAMERA_FOCUS_TIME :: 1.0 / 8.0;
    if camera_mode == .NEAR || camera_mode == .FAR {
        camera_focus_x_interp = min(camera_focus_x_interp + dt / CAMERA_FOCUS_TIME, 1);
        camera_focus_z_interp = min(camera_focus_z_interp + dt / CAMERA_FOCUS_TIME, 1);
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

    old_enemy_timer := enemy_timer;
    enemy_timer += dt / ENEMY_TICK_TIME;
    new_enemy_timer := enemy_timer;

    enemy_update_to_do: enum {
        NONE;
        FALLING;
        ALL;
    }

    if enemy_timer >= ENEMY_TICK_TIME {
        enemy_timer = fmod_cycling(enemy_timer, ENEMY_TICK_TIME);
        enemy_update_to_do = .ALL;
    } else if floor(old_enemy_timer / ENEMY_TICK_TIME * FALLS_PER_ENEMY_TICK) < floor(enemy_timer / ENEMY_TICK_TIME * FALLS_PER_ENEMY_TICK) {
        enemy_update_to_do = .FALLING;
    }

    if enemy_update_to_do != .NONE {
        if enemy_update_to_do == .ALL {
            // Run the Enemy_Despawner update BEFORE we do enemy movement.
            // That way, only enemies that were already in a grid cell get despawned.
            for * _Enemy_Despawner {
                in_bounds, index := get_3d_index(it.position, level_position, level_size);
                assert(in_bounds);

                eid := collision[index];
                if !eid continue;
                
                e := get_entity(level, eid);
                enemy := as(e, Enemy);
                if !enemy continue;
                
                collision[index] = 0;
                delete_entity(level, eid);
            }

            for * _Enemy {
                if it.state == {
                    case .IDLE;
                        can_move_to :: (using level: *Level, position: Vector3i) -> bool {
                            if !is_colliding_below(level, position) return false;
                            in_bounds, index := get_3d_index(position, level_position, level_size);
                            assert(in_bounds);
                            eid := collision[index];
                            if eid == 0 return true;
                            if get_entity(level, eid).type == .Block return false;
                            return true;
                        }

                        it.moving_from = to_vector3(it.position);

                        desired_direction := facing_to_vector3i(it.facing);

                        if can_move_to(level, it.position + desired_direction) {
                            it.desired_position = it.position + desired_direction;
                            it.desired_vfx_modifiers = .MOVING;
                        } else {
                            new_facing: Facing;

                            if #complete it.favored_direction == {
                                case .LEFT;
                                    new_facing = facing_left(it.facing);
                                case .RIGHT;    
                                    new_facing = facing_right(it.facing);
                            }

                            desired_direction := facing_to_vector3i(new_facing);

                            if can_move_to(level, it.position + desired_direction) {
                                it.desired_position = it.position + desired_direction;
                                it.desired_vfx_modifiers = .MOVING;
                                it.facing = new_facing;
                            } else {
                                new_facing: Facing;
                                if #complete it.favored_direction == {
                                    case .LEFT;
                                        new_facing = facing_right(it.facing);
                                    case .RIGHT;
                                        new_facing = facing_left(it.facing);
                                }

                                desired_direction := facing_to_vector3i(new_facing);

                                if can_move_to(level, it.position + desired_direction) {
                                    it.desired_position = it.position + desired_direction;
                                    it.desired_vfx_modifiers = .MOVING;
                                    it.facing = new_facing;
                                } else {
                                    new_facing := facing_opposite(it.facing);
                                    desired_direction := facing_to_vector3i(new_facing);

                                    if can_move_to(level, it.position + desired_direction) {
                                        it.desired_position = it.position + desired_direction;
                                        it.desired_vfx_modifiers = .MOVING;
                                        it.facing = new_facing;
                                    } else {
                                        it.desired_position = it.position;
                                        it.desired_vfx_modifiers = 0;
                                    }
                                }
                            }
                        }

                    case .FALLING;
                        it.desired_position = it.position;
                        it.desired_position.y -= 1;
                        it.desired_vfx_modifiers = .FALLING;
                }
            }
        } else {
            for * _Enemy {
                if #complete it.state == {
                    case .IDLE;
                        it.desired_position = it.position;
                        it.desired_vfx_modifiers = 0;
                    case .FALLING;
                        it.desired_position = it.position;
                        it.desired_position.y -= 1;
                        it.desired_vfx_modifiers = .FALLING;
                }
            }
        }

        for * _Block it.desired_position = it.position;
        
        assert(use_desired_positions(level));

        if enemy_update_to_do == .ALL {
            // Now that Enemies have moved, we can run enemy spawner code.
            for * _Enemy_Spawner {
                in_bounds, index := get_3d_index(it.position, level_position, level_size);
                assert(in_bounds);
                
                should_spawn_enemy := false;

                if collision[index] == 0 {
                    should_spawn_enemy = true;
                } else {
                    e := get_entity(level, collision[index]);
                    if e.type == .Enemy {
                        enemy_in_bounds, enemy_index := get_3d_index(e.position, level_position, level_size);
                        assert(enemy_in_bounds);
                        collision[enemy_index] = 0;
                        delete_entity(level, e.eid);
                        append_no_resize(*mutual_annihilations, .{position = it.position});
                    } else if e.type != .Block {
                        should_spawn_enemy = true;
                    }
                }

                if should_spawn_enemy {
                    e := make_entity(level, Enemy);
                    e.position = it.position;
                    e.state = .IDLE;
                    e.vfx_modifiers |= .SPAWNING;

                    if it.enemy_spawner_type == {
                        case .ALTERNATING;
                            e.favored_direction = it.alternating_direction;
                        case .ALL_RIGHT;
                            e.favored_direction = .RIGHT;
                        case .ALL_LEFT;
                            e.favored_direction = .LEFT;
                    }

                    e.facing = it.facing;
                    assert(collision[index] == 0);
                    collision[index] = e.eid;
                }


                if it.enemy_spawner_type == .ALTERNATING {
                    // Flip the direction every tick
                    if it.alternating_direction == .LEFT {
                        it.alternating_direction = .RIGHT;
                    } else {
                        it.alternating_direction = .LEFT;
                    }
                }
            }
        }
    } 


    
    old_fall_timer := fmod_cycling(old_enemy_timer, ENEMY_TICK_TIME / FALLS_PER_ENEMY_TICK);
    new_fall_timer := old_fall_timer + new_enemy_timer - old_enemy_timer;

    if old_fall_timer < ENEMY_FALLING_VFX_TIME && ENEMY_FALLING_VFX_TIME <= new_fall_timer {
        for * _Enemy {
            if it.vfx_modifiers & .FALLING {
                it.vfx_modifiers &= ~.FALLING;
            }
        }
    }

    if old_enemy_timer < ENEMY_MOVING_VFX_TIME && ENEMY_MOVING_VFX_TIME <= new_enemy_timer {
        for * _Enemy {
            if it.vfx_modifiers & .MOVING {
                it.vfx_modifiers &= ~.MOVING;
            }
        }
    }

    if old_enemy_timer < PLAYERLIKE_SPAWNING_TIME && PLAYERLIKE_SPAWNING_TIME <= new_enemy_timer {
        for * _Enemy {
            if it.vfx_modifiers & .SPAWNING {
                it.vfx_modifiers &= ~.SPAWNING;
            }
        }
    }


    for * mutual_annihilations {
        TIME :: 0.15;
        it.interp += dt / TIME;
        if it.interp > 1 remove it;
    }
    
    PLAYER_FALLING_TIME :: 0.2;
    if #complete player.state == {
        case .SPAWNING;
            player.spawning.interp += dt / PLAYERLIKE_SPAWNING_TIME;
            if player.spawning.interp >= 1 {
                if is_colliding_below(level, player.position) {
                    set_state(player, .GROUND);
                } else {
                    // This one should never happen
                    set_state(player, .FALLING); 
                }
            }

        case .GROUND;
            player.ground.landing_interp = min(1.0, player.ground.landing_interp + dt / PLAYER_FALLING_TIME);

        case .FALLING;
            assert(!(flags & .DEBUG_MOVEMENT));
            player.falling.interp += dt / PLAYER_FALLING_TIME;
            while player.falling.interp >= 1 {
                player.falling.interp -= 1;
                new_position := player.position;
                new_position.y -= 1;
               
                if new_position.y < level_position.y {
                    set_state(player, .DEAD);
                    break;
                }

                player.position = new_position;

                if is_colliding_below(level, player.position) {
                    set_state(player, .GROUND);
                    break;
                }
            }

        case .DEAD;
            DEAD_TIME :: PLAYERLIKE_SPAWNING_TIME;
            player.dead.interp += dt / DEAD_TIME;
            if player.dead.interp >= 1 {    
                memcpy(current_data.data, checkpoint_data.data, checkpoint_data.count);
            }
    }

    
    //
    // Update floodfill view
    //


    for :iterate_vector3i level_size {
        viewed[it_index] &= ~(.VISIBLE | .QUEUED_FOR_FLOODFILL);
    }

    mark := get_mark(*frame_arena);
    defer restore_mark(*frame_arena, mark);
    // Should this instead be stashed in the data structure for the level so we know how much memory is being used?
    positions := alloc_view(*frame_arena, level_size.x * level_size.y * level_size.z, Vector3i, zero_init=false);
    position_count := 1;

    player_in_bounds, player_index := get_3d_index(player.position, level_position, level_size);
    assert(player_in_bounds);
    positions[0] = player.position;
    viewed[player_index] |= (.QUEUED_FOR_FLOODFILL | .SEEN | .VISIBLE);

    while position_count {
        position_count -= 1;
        position := positions[position_count];

        check_axis :: (i: int) #expand {
            check_position :: (position: Vector3i) -> bool #expand {
                success, index := get_3d_index(position, level_position, level_size);
                if success && !(viewed[index] & .QUEUED_FOR_FLOODFILL) {
                    eid := collision[index];
                    door_eid := doors[index];
                    if (!eid || get_entity(level, eid).type != .Block) && !door_eid {
                        viewed[index] |= (.QUEUED_FOR_FLOODFILL | .SEEN | .VISIBLE);
                        positions[position_count] = position;
                        position_count += 1;
                    }
                }
            }

            p := position;
            p.component[i] += 1;
            check_position(p);

            n := position;
            n.component[i] -= 1;
            check_position(n);
        }

        check_axis(0);
        check_axis(1);
        check_axis(2);
    }



    update_view_texture(*view_texture, level_size, viewed);
}
