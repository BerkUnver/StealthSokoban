// Based on the Jai standard hash table

Table :: struct(
    Key_Type: Type,
    Value_Type: Type,
    hash_function := default_hash
    // hash_function is an autobake instead of a function pointer
    // so dll hot-reloading will still work.
) {
    Entry :: struct {
        key: Key_Type;
        value: Value_Type;
        hash: u32;
    }
    
    entries: [] Entry;
    count: int;
    max_count: int;
}

LOAD_FACTOR :: 0.7;

NO_HASH :: 0;
REMOVED_HASH :: 1;
FIRST_VALID_HASH :: 2;


djb2_hash :: (s: string) -> u32 {
    hash: u32 = 5381;
    for 0..s.count-1 #no_abc #no_aoc {
        hash = ((hash << 5) + hash) + s[it];    // hash * 33 + c
    }
    return hash;
}


// @CompilerBug The compiler crashes if I try to make this a polymorph,
// I think it does not like polymorphs as default parameters for bakeable
// function arguments.
default_hash :: (any: Any) -> u32 {
    return djb2_hash(.{any.type.runtime_size, any.value_pointer});
}


table_hash :: (table: *Table, val: $T) -> u32 {
    hash := table.hash_function(dynamic_any(type_info(T), *val));
    if hash < FIRST_VALID_HASH hash += FIRST_VALID_HASH;
    return hash;
}


make_table :: (arena: *Memory_Arena, max_count: int, $K: Type, $V: Type, $hash_function := default_hash) -> result: Table(K, V, hash_function) {
    // @TODO: Test what happens when max_count close to zero.
    assert(max_count >= 0);
    entries_count := cast(int, ceil(cast(float, max_count) / LOAD_FACTOR));
    if entries_count < 8 entries_count = 8;

    // The triangular numbers scheme we are using will visit every slot of the table only when the table
    // has a power of two size.
    power := 1;
    while entries_count > power power <<= 1;
    entries_count = power;

    max_count = xx ceil(cast(float, entries_count) * LOAD_FACTOR);

    return .{
        entries = alloc_view(arena, entries_count, Table(K, V, hash_function).Entry),
        max_count = max_count
    };
}


add :: (using table: *Table, key: table.Key_Type, value: table.Value_Type, arena: *Memory_Arena = null) {
    ptr := add(table, key, arena);
    ptr.* = value;
}


add :: (using table: *Table, key: table.Key_Type, arena: *Memory_Arena = null) -> *table.Value_Type {
    if count >= max_count {
        assert(arena != null);
        
        old_entries := table.entries;

        table.* = make_table(arena, count + 1, table.Key_Type, table.Value_Type, table.hash_function);
        
        for * old_entries {
            if it.hash >= FIRST_VALID_HASH {
                add(table, it.key, it.value);
            }
        }
    }
    
    hash := table_hash(table, key);

    index := hash % entries.count;
    increment := 0;
    while entries[index].hash >= FIRST_VALID_HASH {
        index += increment;
        index %= entries.count;
        increment += 1;
    }

    entries[index] = .{
        key=key,
        hash=hash
    };

    count += 1;

    return *entries[index].value;
}


set :: (using table: *Table, key: table.Key_Type, value: table.Value_Type, arena: *Memory_Arena = null) {
    v := get(table, key);
    if v {
        v.* = value;
    } else {
        add(table, key, value, arena);
    }
}


// "remove" is a keyword, so I can't use it for the name of
// this procedure...
delete :: (using table: *Table, key: table.Key_Type) -> bool {
    assert(count <= max_count);

    hash := table_hash(table, key);

    index := hash % entries.count;
    increment := 0;
    while entries[index].hash >= FIRST_VALID_HASH {
        entry := *entries[index];
        if entry.hash == hash && entry.key == key {
            entry.hash = REMOVED_HASH;
            count -= 1;
            return true;
        }

        index += increment;
        index %= entries.count;
        increment += 1;
    }

    return false;
}


get :: (using table: *Table, key: table.Key_Type) -> *table.Value_Type {
    assert(count <= max_count);

    hash := table_hash(table, key);

    index := hash % entries.count;
    increment := 0; 
    while entries[index].hash != NO_HASH {
        entry := *entries[index];

        // entry.hash == hash will fail if entry.hash == REMOVED_HASH.
        // In that case, we will continue searching as we should.
        if entry.hash == hash && entry.key == key {
            return *entry.value;
        }

        index += increment;
        index %= entries.count;
        increment += 1;
    }

    return null;
}

