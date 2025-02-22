#insert -> string {
    TYPES :: #string END
    *Type_Info_Struct.[
        type_info(Block),
        type_info(Enemy),
        type_info(Enemy_Spawner),
        type_info(Player),
        type_info(Entrance),
        type_info(Exit),
    ];
    END
    entities := #insert TYPES;
    
    for entities {
        assert(it.members[0].flags & .CONSTANT == 0);
        assert(it.members[0].type == type_info(Entity));
    }

    buf: [4096] u8;
    str := string.{buf.count, buf.data};
    
    _, str = format_print(str, "Entity_Types :: struct {\n");
    _, str = format_print(str, "    TYPES :: %\n", TYPES);
    _, str = format_print(str, "    union {\n");
    _, str = format_print(str, "        struct {\n");
    for entities {
        _, str = format_print(str, "            _%: [..] %;\n", it.name, it.name);
    }
    _, str = format_print(str, "        }\n");
    _, str = format_print(str, "        components: [%] Resizable_Array;\n", entities.count);
    _, str = format_print(str, "    }\n");
    _, str = format_print(str, "}\n");

    count := buf.count - str.count;

    return .{count, buf.data};
}


// We only ever want the arena when we're in the editor mode.
// Should we assert on this or something?
make_entity :: (using level: *Level, index: int, arena: *Memory_Arena = null) -> *Entity {
    array := *types.components[index];
    type := Entity_Types.TYPES[index];
    
    // Note that because "array" is an alias for whatever the actual underlying
    // type is, the count and allocated will NOT CORRESPOND to how big the array
    // actually is. DO NOT CALL THE NORMAL "append" FUNCTION HERE!
    if array.count == array.allocated {
        assert(arena != null);
        array.allocated *= 2;
        new_memory := cast(*u8, alloc(arena, array.allocated * type.runtime_size, zero_init=false));
        memcpy(new_memory, array.data, array.count * type.runtime_size);
        array.data = new_memory;
    }

    e := cast(*Entity, cast(*u8, array.data) + array.count * type.runtime_size);
    array.count += 1;
    
    assert(entities.count < (1 << 24) - 1);
    e.eid = xx entities.count;
    if arena append(*entities, e, arena);
    else append_no_resize(*entities, e);
    


    if type.initializer type.initializer(e);
    else memset(e, 0, type.runtime_size);

    return e;
}


make_entity :: (using level: *Level, $T: Type) -> *T {
    get_entity_index :: () -> int {
        for Entity_Types.TYPES {
            if it == type_info(T) {
                return it_index;
            }
        }
        assert(false);
        return -1;
    }

    INDEX :: #run get_entity_index();
    return xx make_entity(level, INDEX);
}


delete_entity :: (using level: *Level, eid: Entity_Id) {
    e := entities[eid];
    entities[eid] = null;
    
    type_index := -1;
    entity_size := 0;
    // @Speed @Hack
    for * types.components {
        entity_size = Entity_Types.TYPES[it_index].runtime_size;
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

    entities[xx final.eid] = e;
}



Entity_Id :: #type,distinct u32; // Literally just an index


as :: (e: *Entity, $T: Type) -> *T {
    if e.type == T return xx e;
    return null;
}

get_entity :: inline (using level: *Level, eid: Entity_Id) -> *Entity {
    return entities[eid];
}


// The below is an experiment.
// I want to see what happens if we can make sane default behavior for all
// entities, but then be able to go in here and put per-entity code if we 
// need to without it weirdly overlapping the default code.
// There aren't enough entity types or code for that to manifest yet.
// We will see what happens.

//          -berk, 18 - 2 - 2025

entity_mesh :: (e: *Entity) -> *Mesh {
    using context.game_context;

    block := as(e, Block);
    if block return *block.mesh;

    player := as(e, Player);
    if player return *player_mesh;

    exit := as(e, Exit);
    if exit return *exit_mesh;

    entrance := as(e, Entrance);
    if entrance return *entrance_mesh;

    enemy := as(e, Enemy);
    if enemy return *enemy_mesh;

    spawner := as(e, Enemy_Spawner);
    if spawner return *enemy_spawner_mesh;

    assert(false);
    return null;
}


iterate_entities :: (level: *Level, body: Code, flags: For_Flags) #expand {
    #assert flags == 0;
    for `it, `it_index: level.entities {
        if !it continue;
        #insert(remove=#assert false) body;
    }
}
