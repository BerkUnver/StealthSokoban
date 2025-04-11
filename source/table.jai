// Based on the Jai standard hash table

Table :: struct(
    Key_Type: Type,
    Value_Type: Type,
    hash_function: (string) -> u32
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


table_hash :: (table: *Table, val: $T) -> u32 {
    hash := table.hash_function(.{size_of(T), xx *val});
    if hash < FIRST_VALID_HASH hash += FIRST_VALID_HASH;
    return hash;
}


make_table :: (arena: *Memory_Arena, max_count: int, $K: Type, $V: Type, $hash_function := djb2_hash) -> result: Table(K, V, hash_function) {
    // @TODO: Test what happens when max_count close to zero.
    assert(max_count > 0);
    entries_count := cast(int, ceil(cast(float, max_count) / LOAD_FACTOR));

    // The triangular numbers scheme we are using will visit every slot of the table only when the table
    // has a power of two size.
    power := 1;
    while entries_count > power power <<= 1;
    entries_count = power;

    return .{
        entries = alloc_view(arena, entries_count, Table(K, V, hash_function).Entry),
        max_count = max_count
    };
}


add :: (using table: *Table, key: table.Key_Type, value: table.Value_Type) {
    assert(count < max_count);
    assert(entries.count >= 2);
    
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
        value=value,
        hash=hash
    };
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

