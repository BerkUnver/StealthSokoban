jai_string_equals_c_string :: (jai_string: string, c_string: *u8) -> bool {
    for 0..jai_string.count-1 {
        if c_string[it] == #char "\0" return false;
        if c_string[it] != jai_string[it] return false;
    }
    
    if c_string[jai_string.count] != #char "\0" return false;
    return true;
}


iterate_vector3i :: (v: Vector3i, body: Code, for_flags: For_Flags) #expand {
    #assert for_flags == 0;

    y_chunk := v.x * v.z;
    for `y_index: 0..v.y-1 {
        y_offset := y_index * y_chunk;
        for `z_index: 0..v.z-1 {
            z_offset := y_offset + z_index * v.x;
            for `x_index: 0..v.x-1 {
                `it_index := z_offset + x_index;
                `it := Vector3i.{x_index, y_index, z_index};
                #insert(break=break y_index, continue=continue, remove=#assert false) body;
            }
        }
    }
}


get_3d_index_unchecked :: (coord: Vector3i, size: Vector3i) -> s64 {
    return coord.y * size.z * size.x + coord.z * size.x + coord.x;
}


inside_positive_bounding_box :: (v: Vector3i, bbox: Vector3i) -> bool {
    return
        0 <= v.x && v.x < bbox.x &&
        0 <= v.y && v.y < bbox.y &&
        0 <= v.z && v.z < bbox.z;
}


get_3d_index :: (position: Vector3i, array_position: Vector3i, array_size: Vector3i) -> bool, s64 {
    coord := position - array_position;
    if !inside_positive_bounding_box(coord, array_size) return false, 0;
    return true, get_3d_index_unchecked(coord, array_size);
}


get_3d_index :: (position: Vector3i, size: Vector3i) -> bool, s64 {
    if !inside_positive_bounding_box(position, size) return false, 0;
    return true, get_3d_index_unchecked(position, size);
}


realloc_3d_array_to_fit_subarea :: (position: Vector3i, size: Vector3i, data: [] $T, sub_position: Vector3i, sub_size: Vector3i, arena: *Memory_Arena) -> new_position: Vector3i, new_size: Vector3i, new_data: [] T {
    new_position := min(position, sub_position);
    new_end := max(position + size, sub_position + sub_size);
    new_size := new_end - new_position;
    
    if position == new_position && size == new_size return position, size, data;

    new_data := alloc_view(arena, new_size.x * new_size.y * new_size.z, T);
    
    // @Speed memcpy the x axis instead of calculating it one-by-one.
    offset := position - new_position;
    for :iterate_vector3i size {
        new_index := get_3d_index_unchecked(it + offset, new_size);
        new_data[new_index] = data[it_index];
    }

    return new_position, new_size, new_data;
}


restore_mark :: (arena: *Memory_Arena, marker: s64) {
    assert(arena.current >= marker);
    arena.current = marker;
}


print :: (s: string, args: ..Any) {
    using context.game_context;
    buf: [4096] u8;
    sb := make_string_builder(buf);
    print(*sb, s, ..args);
    os_print(get_string(*sb));
}


byte_count :: (a: [] $T) -> s64 {
    return size_of(T) * a.count;
}


slice :: (a: [] $T, start: int) -> [] T {
    assert(start <= a.count);
    return .{data=a.data + start, count = a.count - start};
}


Memory_Arena :: struct {
    data: *u8;
    count: s64;
    current: s64;
}

make_arena :: (memory: *u8, count: s64) -> Memory_Arena {
    return .{
        data = memory,
        count = count,
        current = 0
    };
}


clear :: inline (arena: *Memory_Arena) {
    arena.current = 0;
}


alloc :: (arena: *Memory_Arena, count: s64, zero_init := true) -> *void {
    assert(count >= 0);
    ret := arena.data + arena.current;
    arena.current += count;
    if zero_init memset(ret, 0, count);
    return ret;
}

alloc :: (arena: *Memory_Arena, $T: Type, zero_init := true) -> *T {
    return alloc(arena, size_of(T), zero_init);
}

alloc_view :: (arena: *Memory_Arena, count: s64, $T: Type, zero_init := true) -> [] T #must {
    byte_count := size_of(T) * count; 
    ret := alloc(arena, byte_count, zero_init);
    return .{data=xx ret, count=count};
}


get_mark :: (arena: *Memory_Arena) -> s64 {
    return arena.current;
}




reserve_array :: (arena: *Memory_Arena, reserve: s64, $T: Type, zero_init := true) -> [..] T {
    mem := alloc(arena, reserve * size_of(T), zero_init);

    array: [..] T;
    array.data = mem;
    array.allocated = reserve;
    array.allocator.data = arena;

    // I don't love the implicit allocator semantics that Jai wants you to use,
    // so I am avoiding them for now. However, I will set the allocator data to the
    // arena so we can assert that we're resizing using the same arena.

    return array;
}


alloc_array :: (arena: *Memory_Arena, count: s64, $T: Type, zero_init := true) -> [..] T {
    allocated := count;
    if 0 < allocated && allocated < 8 allocated = 8;
    mem := alloc(arena, allocated * size_of(T), zero_init);

    array: [..] T;
    array.count = count;
    array.data = mem;
    array.allocated = allocated;
    array.allocator.data = arena;
    
    return array;
}


alloc_extra_array_capacity :: (arena: *Memory_Arena, array: *[..] $T, new_capacity: s64, zero_init := true) {
    if new_capacity < array.allocated return;
    mem := alloc(arena, new_capacity * size_of(T), zero_init=false);
    memcpy(mem, array.data, size_of(T) * array.count);
    if zero_init memset(mem + size_of(T) * array.count, 0, size_of(T) * (new_capacity - array.count));

    array.data = mem;
    array.allocated = new_capacity;
}


append_no_resize :: (a: *[..] $T) -> *T {
    assert(a.count < a.allocated);
    item := a.data + a.count;
    a.count += 1;
    return item;
}


append_no_resize :: (a: *[..] $T, item: T) {
    append_no_resize(a).* = item;
}


contains :: (a: *[..] $T, item: T) -> bool {
    for a.* if it == item return true;
    return false;
}

contains :: (a: [] $T, item: T) -> bool {
    for a if it == item return true;
    return false;
}


append :: (a: *[..] $T, arena: *Memory_Arena) -> *T {
    if a.count == a.allocated {
        if a.count == 0 a.allocated = 8;
        else a.allocated *= 2;
        new_memory := alloc(arena, a.allocated * size_of(T), zero_init=false);
        memcpy(new_memory, a.data, a.count * size_of(T));
        a.data = new_memory;
    }

    item := a.data + a.count;
    a.count += 1;

    return item;
}


append :: inline (a: *[..] $T, item: T, arena: *Memory_Arena) {
    append(a, arena).* = item;
}


init_from_info :: (info: *Type_Info_Struct, ptr: *void) {
    if info.initializer info.initializer(ptr);
    else memset(ptr, 0, info.runtime_size);
}
