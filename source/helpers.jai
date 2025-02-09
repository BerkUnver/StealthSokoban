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

    new_data := arena_alloc_array(arena, new_size.x * new_size.y * new_size.z, T);
    
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
    buf: [4096] u8;
    buf_str := string.{buf.count, buf.data};
    buf_str = format_print(buf_str, s, ..args);
    context.game_context.os_print(buf_str);
}


byte_count :: (a: [] $T) -> s64 {
    return size_of(T) * a.count;
}


slice :: (a: [] $T, start: int) -> [] T {
    assert(start <= a.count);
    return .{data=a.data + start, count = a.count - start};
}
