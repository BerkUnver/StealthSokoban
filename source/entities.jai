// Put these in alphabetical order, please.
Entity_Type :: enum {
    Block;
    Checkpoint;
    Door;
    Enemy;
    Enemy_Despawner;
    Enemy_Spawner;
    Exit;
    Input_Hint;
    Ladder;
    Overworld_Entrance;
    Overworld_Exit;
    Player;
}


ENTITY_TYPE_COUNT :: #run -> s64 {
    values := type_info(Entity_Type).values;
    assert(values.count != 0);

    max := values[0];

    for 1..values.count-1 {
        value := values[it];
        if value > max max = value;
    }
    
    return max + 1;
}


ENTITY_TYPE_INFOS :: #insert -> string {
    sb := make_local_string_builder();
    print(*sb, "*Type_Info_Struct.[\n");
    for type_info(Entity_Type).names {
        print(*sb, "    type_info(%),\n", it);
    }
    print(*sb, "];\n");
    return get_string(*sb);
}


// 0 is our special null value, meaning "This eid is invalid, it doesn't refer to anything."
// Do not call get_entity on these eids.
Entity_Id :: #type,distinct u32;

Entity :: struct {
    type: Entity_Type; @NoSerialize
    eid: Entity_Id; @ReadOnly
    position: Vector3i; // As soon as there's an entity without this member,
    // move this out of here. I don't want to end up with a bunch of weirdly overlapping entities.
}

Entity_Types :: struct {
    #insert -> string {
        sb := make_local_string_builder();
        for ENTITY_TYPE_INFOS {
            print(*sb, "    _%: [..] %;\n", it.name, it.name);
        }
        print(*sb, "    #place _%;\n", ENTITY_TYPE_INFOS[0].name);
        print(*sb, "    components: [%] Resizable_Array;\n", ENTITY_TYPE_INFOS.count);
        str := get_string(*sb);
        return str;
    }
}


// We only ever want the arena when we're in the editor mode.
// Should we assert on this or something?
make_entity :: (using level: *Level, index: int, arena: *Memory_Arena = null) -> *Entity {
    array := *types.components[index];
    type := ENTITY_TYPE_INFOS[index];
    
    // Note that because "array" is an alias for whatever the actual underlying
    // type is, the count and allocated will NOT CORRESPOND to how big the array
    // actually is. DO NOT CALL THE NORMAL "append" FUNCTION HERE!
    if array.count == array.allocated {
        assert(arena != null);
        if array.allocated == 0 array.allocated = 8;
        else array.allocated *= 2;
        new_memory := cast(*u8, alloc(arena, array.allocated * type.runtime_size, zero_init=false));
        memcpy(new_memory, array.data, array.count * type.runtime_size);
        array.data = new_memory;

        for 0..array.count-1 {
            offset := it * type.runtime_size;
            e := cast(*Entity, array.data + offset);
            set(*entities, e.eid, e);
        }
    }

    e := cast(*Entity, cast(*u8, array.data) + array.count * type.runtime_size);
    array.count += 1;
    init_from_info(type, e);

    e.type = xx index;
    
    success, eid := pop(*unused_eids);
    if !success eid = xx (entities.count + 1);
    e.eid = eid;

    set(*entities, e.eid, e, arena);

    return e;
}


make_entity :: (using level: *Level, $T: Type, arena: *Memory_Arena = null) -> *T {
    INDEX :: #run -> int {
        for ENTITY_TYPE_INFOS {
            if it == type_info(T) {
                return it_index;
            }
        }
        assert(false);
        return -1;
    }

    return xx make_entity(level, INDEX, arena);
}


delete_entity :: (using level: *Level, eid: Entity_Id, arena: *Memory_Arena = null) {
    assert(eid != 0);
    
    // @TODO: If we delete the entity with the highest eid, it still gets appended here.
    // It doesn't matter right now, so I'm ignoring it.
    if arena append(*unused_eids, eid, arena);
    else append_no_resize(*unused_eids, eid);

    
    e_ptr := get(*entities, eid);
    assert(e_ptr != null);
    e := e_ptr.*;
    set(*entities, eid, null);
    
    type_index := -1;
    entity_size := 0;

    // @Speed @Hack
    for * types.components {
        entity_size = ENTITY_TYPE_INFOS[it_index].runtime_size;
        if it.data <= e && e < it.data + it.count * entity_size {
            type_index = it_index;
            break;
        }
    }
    assert(type_index >= 0);

    array := *types.components[type_index];
    
    offset := cast(*u8, e) - cast(*u8, array.data);
    index := offset / entity_size;
    array.count -= 1;

    if index == array.count return;

    final := cast(*Entity, cast(*u8, array.data) + array.count * entity_size);
    memcpy(e, final, entity_size);
    assert(e.eid != 0);
    set(*entities, e.eid, e); // Make sure we correctly update the lookup table for the eid we just removed
}


as :: (e: *Entity, $T: Type) -> *T {
    INDEX :: #run -> int {
        for type_info(Entity_Type).names {
            if it == type_info(T).name {
                return it_index;
            }
        }
        assert(false);
        return 1;
    }

    if e.type == xx INDEX return xx e;
    return null;
}


get_entity :: (using level: *Level, eid: Entity_Id) -> *Entity {
    assert(eid != 0);
    v := get(*entities, eid);
    assert(v != null);
    return v.*;
}


iterate_entities :: (types: *Entity_Types, body: Code, flags: For_Flags) #expand {
    `it_index := -1; // It doesn't make sense to use this here
    `it: *Entity = null;
    #assert flags == 0;
    
    // @Speed This generates more code EVERY TIME this macro
    // is invoked! This might kill compile times!
    #insert -> string {
        sb := make_local_string_builder();
        for ENTITY_TYPE_INFOS {
            print(*sb, "for * e: types._% {\n", it.name);
            print(*sb, "    it = e;\n");
            print(*sb, "    #insert body;\n");
            print(*sb, "}\n");
        }
        return get_string(*sb);
    }
}


// The below is an experiment.
// I want to see what happens if we can make sane default behavior for all
// entities, but then be able to go in here and put per-entity code if we 
// need to without it weirdly overlapping the default code.
// There aren't enough entity types or code for that to manifest yet.
// We will see what happens.

//          -berk, 2025 - 2 - 18 

entity_mesh :: (e: *Entity) -> *Mesh {
    using context.game_context;

    if #complete e.type == {
        case .Block;
            return *as(e, Block).mesh;
        case .Door;
            return *as(e, Door).mesh;
        case .Player;
            return player_mesh;
        case .Exit;
            return exit_mesh;
        case .Enemy;
            return enemy_mesh;
        case .Enemy_Spawner;
            return enemy_spawner_mesh;
        case .Enemy_Despawner;
            return enemy_despawner_mesh;
        case .Checkpoint;
            return checkpoint_mesh;
        case .Overworld_Entrance;
            return overworld_entrance_mesh;
        case .Overworld_Exit;
            return overworld_exit_mesh;
        case .Input_Hint;
            return *as(e, Input_Hint).mesh;
        case .Ladder;
            return ladder_mesh;
    }

    return null;
}


entity_mesh_to_world_matrix :: (level: *Level, e: *Entity) -> Matrix4 {
    if e.type == {
        case .Enemy;
            return get_enemy_draw_info(level, as(e, Enemy));
        case .Enemy_Spawner;
            return get_enemy_spawner_draw_info(as(e, Enemy_Spawner));
        case .Player;
            return get_player_draw_info(level, as(e, Player));
        case .Ladder;
            return get_ladder_draw_info(as(e, Ladder));
        case;
            return make_translation_matrix4(to_vector3(e.position));;
    }
}


entity_facing :: (e: *Entity) -> *Facing {
    #insert -> string {
        sb := make_local_string_builder();
        print(*sb, "if #complete e.type == {\n");
        for info: ENTITY_TYPE_INFOS {
            print(*sb, "    case .%;\n", info.name);

            found := false;

            for member: info.members {
                if member.name == "facing" && member.type == type_info(Facing) {
                    print(*sb, "        return *cast(*%, e).facing;\n", info.name);
                    found = true;
                    break;
                }
            }

            if !found {
                print(*sb, "        return null;\n");
            }
        }
        print(*sb, "}\n");

        return get_string(*sb);
    }
}
