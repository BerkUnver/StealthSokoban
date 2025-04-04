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


realloc_3d_array_to_fit_subarea :: (position: Vector3i, size: Vector3i, data: [] $T, sub_position: Vector3i, sub_size: Vector3i, allocator: Allocator) -> new_position: Vector3i, new_size: Vector3i, new_data: [] T {
    new_position := min(position, sub_position);
    new_end := max(position + size, sub_position + sub_size);
    new_size := new_end - new_position;
    
    if position == new_position && size == new_size return position, size, data;

    new_data := alloc_view(allocator, new_size.x * new_size.y * new_size.z, T);
    
    // @Speed memcpy the x axis instead of calculating it one-by-one.
    offset := position - new_position;
    for :iterate_vector3i size {
        new_index := get_3d_index_unchecked(it + offset, new_size);
        new_data[new_index] = data[it_index];
    }

    return new_position, new_size, new_data;
}


print :: (s: string, args: ..Any) {
    using context.game_context;
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


get_mark :: (arena: *Memory_Arena) -> s64 {
    return arena.current;
}


restore_mark :: (arena: *Memory_Arena, marker: s64) {
    assert(arena.current >= marker);
    arena.current = marker;
}


scope_mark :: (arena: *Memory_Arena) #expand {
    mark := get_mark(arena);
    `defer restore_mark(arena, mark);
}


arena_allocator_proc : Allocator_Proc : (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, allocator_data: *void) -> *void {


    _alloc :: (arena: *Memory_Arena, count: s64) -> *void {
        new_current := arena.current + count;
        assert(new_current <= arena.count);
        ret := arena.data + arena.current;
        arena.current = new_current;
        return ret;
    }

    arena := cast(*Memory_Arena, allocator_data);
    if #complete mode == {
        case .ALLOCATE;
            return _alloc(arena, size);

        case .RESIZE;
            if old_memory == null {
                assert(old_size == 0);
                return _alloc(arena, size);
            }

            current := arena.data + arena.current;
            assert(arena.data <= old_memory && old_memory <= current);
            if size < old_size return old_memory;
            
            if old_memory + old_size == current {
                _alloc(arena, size - old_size);
                return old_memory;
            }

            new_memory := _alloc(arena, size);
            memcpy(new_memory, old_memory, old_size);
            return new_memory;

        case .IS_THIS_YOURS;
            ret := arena.data <= old_memory && old_memory <= arena.data + arena.current;
            return xx cast(s64, ret);

        case .CAPS;
            return xx Allocator_Caps.HINT_I_AM_A_FAST_BUMP_ALLOCATOR|.IS_THIS_YOURS;

        case .FREE; #through; // Do we want this to assert false? Do nothing? Log something?
        case .STARTUP; #through;
        case .SHUTDOWN; #through;
        case .THREAD_START; #through;
        case .THREAD_STOP; #through;
        case .CREATE_HEAP; #through;  // @Investigate What does this do?
        case .DESTROY_HEAP; #through; // @Investivate What does this do?
        case;
            assert(false);
            return null;
    }
}


alloc :: (allocator: Allocator, size: s64, zero_init := false) -> *void {
    data := allocator.proc(.ALLOCATE, size, 0, null, allocator.data);
    if zero_init memset(data, 0, size);
    return data;
}


alloc_view :: (allocator: Allocator, count: s64, $T: Type, zero_init := true) -> [] T #must {
    byte_count := size_of(T) * count; 
    ret := alloc(allocator, byte_count, zero_init);
    return .{data=xx ret, count=count};
}


alloc_array :: (allocator: Allocator, count: s64, $T: Type, zero_init := true) -> [..] T {
    array := reserve_array(allocator, count, T, zero_init);
    array.count = count;
    return array;
}


reserve_array :: (allocator: Allocator, count: s64, $T: Type, zero_init := true) -> [..] T {
    allocated := count;
    if 0 < allocated && allocated < 8 allocated = 8;
    mem := alloc(allocator, allocated * size_of(T), zero_init);

    array: [..] T;
    array.data = mem;
    array.allocated = allocated;
    array.allocator = allocator;
    return array;
}


append :: (a: *[..] $T, allocator: Allocator) -> *T {
    if a.count == a.allocated {
        if a.count == 0 a.allocated = 8;
        else a.allocated *= 2;
        a.data = realloc(allocator, a.data, a.count * size_of(T), a.allocated * size_of(T), zero_init = false);
    }

    item := a.data + a.count;
    a.count += 1;

    return item;
}


realloc :: (allocator: Allocator, old: *void, old_size: s64, new_size: s64, zero_init := true) -> *void {
    data := allocator.proc(.RESIZE, new_size, old_size, old, allocator.data);
    if zero_init memset(old + old_size, 0, new_size - old_size);
    return data;
}


append :: inline (a: *[..] $T, item: T, allocator: Allocator) {
    append(a, allocator).* = item;
}


alloc_extra_array_capacity :: (allocator: Allocator, array: *[..] $T, new_capacity: s64, zero_init := true) {
    if new_capacity < array.allocated return;
    mem := alloc(allocator, new_capacity * size_of(T), zero_init=false);
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


pop :: (a: *[..] $T) -> bool, T {
    item: T;
    if a.count == 0 return false, item;
    item = a.*[a.count - 1];
    a.count -= 1;
    return true, item;
}


copy_string :: (allocator: Allocator, str: string) -> string {
    mem := alloc(allocator, str.count, zero_init=false);
    memcpy(mem, str.data, str.count);
    return .{str.count, mem};
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
