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
    return 0 <= v.x && v.x < bbox.x
        && 0 <= v.y && v.y < bbox.y
        && 0 <= v.z && v.z < bbox.z;
}


inside_bounding_box :: (v: Vector3i, position: Vector3i, size: Vector3i) -> bool {
    end := position + size;
    return position.x <= v.x && v.x < end.x
        && position.y <= v.y && v.y < end.y
        && position.z <= v.z && v.z < end.z;
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


print :: (s: string, args: ..Any) {
    buf: [4096] u8;
    sb := make_string_builder(buf);
    print(*sb, s, ..args);
    os_print(get_string(*sb));
}


Log_Level :: enum {
    OK;
    ERROR;
};


log :: (level: Log_Level, s: string, args: ..Any, loc := #caller_location) {
    using context.game_context;
    
    if level == .ERROR set_console_text_color(.RED);

    buf: [4096] u8 = ---;
    sb := make_string_builder(buf);
   
    print(*sb, "%(%): ", loc.fully_pathed_filename, loc.line_number);
    print(*sb, s, ..args);
    os_print(get_string(*sb));

    if level == .ERROR set_console_text_color(.WHITE);
}



byte_count :: (a: [] $T) -> s64 {
    return size_of(T) * a.count;
}


slice :: (a: [] $T, start: int) -> [] T {
    assert(start <= a.count);
    return .{data=a.data + start, count = a.count - start};
}


contains :: (a: *[..] $T, item: T) -> bool {
    for a.* if it == item return true;
    return false;
}

contains :: (a: [] $T, item: T) -> bool {
    for a if it == item return true;
    return false;
}


pop :: (a: *[..] $T) -> bool, T {
    item: T;
    if a.count == 0 return false, item;
    item = a.*[a.count - 1];
    a.count -= 1;
    return true, item;
}


copy_string :: (arena: *Memory_Arena, str: string) -> string {
    mem := alloc(arena, str.count, zero_init=false);
    memcpy(mem, str.data, str.count);
    return .{str.count, mem};
}


// Copied from jai/modules/String. Named "compare" there.
strcmp :: (a: string, b: string) -> int {
    for 0..min(a.count, b.count)-1 {
        if a[it] > b[it] return 1;
        if a[it] < b[it] return -1;
    }
    if a.count > b.count return 1;
    if a.count < b.count return -1;
    return 0;
}


init_from_info :: (info: *Type_Info_Struct, ptr: *void) {
    if info.initializer info.initializer(ptr);
    else memset(ptr, 0, info.runtime_size);
}


// Code for hsv_to_rgb and rgb_to_hsv taken from here:
// https://axonflux.com/handy-rgb-to-hsl-and-rgb-to-hsv-color-model-c

hsv_to_rgb :: (h: float, s: float, v: float) -> r: float, g: float, b: float {
    i := floor(h * 6);
    f := h * 6 - i;
    p := v * (1 - s);
    q := v * (1 - f * s);
    t := v * (1 - (1 - f) * s);
    
    r, g, b: float;

    if i == 0 {
        r = v; g = t; b = p;
    } else if i == 1 {
        r = q; g = v; b = p;
    } else if i == 2 {
        r = p; g = v; b = t;
    } else if i == 3 {
        r = p; g = q; b = v;
    } else if i == 4 {
        r = t; g = p; b = v;
    } else if i == 5 {
        r = v; g = p; b = q;
    }

    return r, g, b;
}


rgb_to_hsv :: (r: float, g: float, b: float) -> h: float, s: float, v: float {
    rgb_max := max(r, max(g, b));
    rgb_min := min(r, min(g, b));
    
    value := rgb_max; 
    range := rgb_max - rgb_min;
    saturation := ifx rgb_max == 0 then 0 else range / rgb_max;
    
    hue: float;
    if rgb_max == rgb_min {
        hue = 0; 
    } else {
        if rgb_max == r {
            hue = (g - b) / range + (ifx g < b then 6 else 0);
        } else if rgb_max == g {
            hue = (b - r) / range + 2;
        } else if rgb_max == b {
            hue = (r - g) / range + 4;
        }
        hue /= 6;
    }

    return hue, saturation, value;
}


begins_with :: (s: string, begin: string) -> bool {
    if s.count < begin.count return false;
    for begin #no_abc {
        if it != s[it_index] return false;
    }
    return true;
}


advance :: (s: string, count: int) -> string {
    assert(s.count >= count);
    return .{s.count - count, s.data + count};
}


assign_int :: (info: *Type_Info_Integer, ptr: *void, value: s64) {
    // @Incomplete: We should do our own bounds checking and have an appropriate failure
    // message, jai native bounds check failure just crashes the program.
    if info.runtime_size == {
        case 1;
            if info.signed cast(*s8, ptr).* = xx value;
            else           cast(*u8, ptr).* = xx value;
        case 2;
            if info.signed cast(*s16, ptr).* = xx value;
            else           cast(*u16, ptr).* = xx value;
        case 4;
            if info.signed cast(*s32, ptr).* = xx value;
            else           cast(*u32, ptr).* = xx value;
        case 8;
            if info.signed cast(*s64, ptr).* = xx value;
            else           cast(*u64, ptr).* = xx value;
        case; assert(false);
    }
}


assign_float :: (info: *Type_Info_Float, ptr: *void, value: float64) {
    if info.runtime_size == {
        case 4; 
            cast(*float32, ptr).* = xx value;
        case 8;
            cast(*float64, ptr).* = value;
        case; assert(false);
    }
}


local_to_global_direction :: (x: float, z: float, yaw: float64) -> Vector3i {
    rotated := rotate(Vector2.{x, z}, yaw);
    dir: Vector3i;
    if abs(rotated.x) > abs(rotated.y) {
        dir.x += cast(s32, sign(rotated.x));
    } else {
        dir.z += cast(s32, sign(rotated.y));
    }

    return dir;
}

get :: (str: string, $T: Type) -> T, string {
    data := str.data;
    return cast(*T, data).*, advance(str, size_of(T));
}


parse_number :: (str: string, start_index: int) -> success: bool, end_index: int, is_float: bool, int_value: s64, float_value: float64 {
    assert(start_index <= str.count);

    if str.count == start_index {
        return false, 0, false, 0, 0;
    }

    index := start_index;
    negative := false;

    if str[index] == #char "-" {
        negative = true;
        index += 1;
    }

    if str.count == index {
        return false, index, false, 0, 0;
    }

    if str[index] < #char "0" && #char "9" < str[index] {
        return false, index, false, 0, 0;
    }


    value: u64 = xx (str[index] - #char "0");
    index += 1;

    while true {
        if index >= str.count {
            result := cast(s64, value);
            if negative result *= -1;
            return success=true, end_index=index, is_float=false, int_value=result, float_value=0;
        }

        if #char "0" <= str[index] && str[index] <= #char "9" {
            value *= 10;
            value += str[index] - #char "0";
            index += 1;
            continue;
        }

        if str[index] == #char "." {
            index += 1;
            fractional_value: float64 = 0;
            current_place := 0.1;
            while true {
                if index >= str.count || (str[index] < #char "0" || #char "9" < str[index]) {
                    result := cast(float64, value);
                    if negative result *= -1;
                    result += fractional_value;
                    return success=true, end_index=index, is_float=true, int_value=0, float_value=result;
                }

                fractional_value += current_place * cast(float64, str[index] - #char "0");
                index += 1;
                current_place /= 10;
            }
            assert(false); // We should never get here.
            continue;
        }

        result := cast(s64, value);
        if negative then result *= -1;
        return success=true, end_index=index, is_float=false, int_value=result, float_value=0;
    }
    
    assert(false); // Unreachable
    return false, 0, false, 0, 0;
}


