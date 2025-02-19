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

    buf: [4096] u8;
    str := string.{buf.count, buf.data};
    
    _, str = format_print(str, "Entities :: struct {\n");
    _, str = format_print(str, "    TYPES :: %\n", TYPES);
    _, str = format_print(str, "    union {\n");
    _, str = format_print(str, "        struct {\n");
    for entities {
        _, str = format_print(str, "            _%: [] %;\n", it.name, it.name);
    }
    _, str = format_print(str, "        }\n");
    _, str = format_print(str, "        components: [%] Array_View_64;\n", entities.count);
    _, str = format_print(str, "    }\n");
    _, str = format_print(str, "}\n");

    count := buf.count - str.count;

    return .{count, buf.data};
}


instantiate_entity :: (using level: *Level, index: int, arena: *Memory_Arena) {  
    using context.game_context;

    array := entities.components[index];
    type := Entities.TYPES[index];
    entity_size := type.runtime_size;
    assert(0 <= index && index < Entities.TYPES.count);

    // @TODO: Dynamically resizing array (BUT FOR USE IN THE EDITOR ONLY.)
    new_memory := cast(*u8, arena_alloc(arena, (array.count + 1) * entity_size, zero_init=false));
    memcpy(new_memory, array.data, array.count * entity_size);
    e := new_memory + array.count * entity_size;
    entities.components[index] = .{array.count + 1, new_memory};

    if type == type_info(Block) {
        block := cast(*Block, e);
        temp := Temporary_Block.{
            size = .{1, 1, 1},
            filled = .[true],
            color = .{1, 1, 1, 1},
        };
        make_block_from_temporary_block(*temp, block, arena);
    } else {
        memset(e, 0, entity_size);
    }
}


// @TODO: Rename to Eid once the old Eid is deleted
Entity_Id :: struct {
    type: u16;
    index: u16;
}


as :: (e: *void, eid: Entity_Id, $T: Type) -> *T {
    if Entities.TYPES[eid.type] == type_info(T) return cast(*T, e);
    return null;
}


get_entity :: (using entities: *Entities, eid: Entity_Id) -> *void {
    assert(components[eid.type].count > eid.index);
    return components[eid.type].data + eid.index * TYPES[eid.type].runtime_size;
}


// The below is an experiment.
// I want to see what happens if we can make sane default behavior for all
// entities, but then be able to go in here and put per-entity code if we 
// need to without it weirdly overlapping the default code.
// There aren't enough entity types or code for that to manifest yet.
// We will see what happens.

//          -berk, 18 - 2 - 2025


entity_position :: (e: *void, eid: Entity_Id) -> *Vector3i {
    #insert -> string {
        buf: [4096] u8;
        str := string.{buf.count, buf.data};

        _, str = format_print(str, "if eid.type == {\n");
        for 0..Entities.TYPES.count - 1 {
            _, str = format_print(str, "    case %;\n", it);
            _, str = format_print(str, "        return *cast(*%, e).position;\n", Entities.TYPES[it].name);
        }
        _, str = format_print(str, "}\n");
        return .{buf.count - str.count, buf.data};
    }
    assert(false);
    return null;
}


entity_mesh :: (e: *void, eid: Entity_Id) -> *Mesh {
    using context.game_context;

    block := as(e, eid, Block);
    if block return *block.mesh;

    player := as(e, eid, Player);
    if player return *player_mesh;

    exit := as(e, eid, Exit);
    if exit return *exit_mesh;

    entrance := as(e, eid, Entrance);
    if entrance return *entrance_mesh;

    enemy := as(e, eid, Enemy);
    if enemy return *enemy_mesh;

    spawner := as(e, eid, Enemy_Spawner);
    if spawner return *enemy_spawner_mesh;

    assert(false);
    return null;
}


iterate_entities :: (using entities: *Entities, body: Code, flags: For_Flags) #expand {
    #assert flags == 0;
    for array, type_index: components {
        size := TYPES[type_index].runtime_size;
        for i: 0..array.count-1 {
            `it_index := Entity_Id.{type=xx type_index, index=xx i};
            `it := cast(*void, array.data + i * size);
            #insert(break=break array, remove=#assert false) body;
        }
    }
}
