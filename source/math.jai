PI :: 3.141592653689793238;

Vector2 :: struct {
    x, y: float;
} 

Vector3 :: struct {
    x, y, z: float;
}

Vector3i :: struct {
    x, y, z: s32;
}

Vector4 :: struct {
    x, y, z, w: float;
}

normalize :: (v: Vector3) -> Vector3 {
    length := sqrt(v.x*v.x + v.y*v.y + v.z*v.z);
    return .{v.x/length, v.y/length, v.y/length};
}

operator - :: (v: Vector3) -> Vector3 {
    return .{-v.x, -v.y, -v.z};
}

operator + :: (a: Vector3, b: Vector3) -> Vector3 {
    return .{a.x + b.x, a.y + b.y, a.z + b.z};
}

operator - :: (a: Vector3, b: Vector3) -> Vector3 {
    return .{a.x - b.x, a.y - b.y, a.z - b.z};
}

operator + :: (a: Vector3i, b: Vector3i) -> Vector3i {
    return .{a.x + b.x, a.y + b.y, a.z + b.z};
}

operator - :: (a: Vector3i, b: Vector3i) -> Vector3i {
    return .{a.x - b.x, a.y - b.y, a.z - b.z};
}

operator == :: (a: Vector3i, b: Vector3i) -> bool {
    return a.x == b.x && a.y == b.y && a.z == b.z;
}

to_vector3 :: (v: Vector3i) -> Vector3 {
    return .{xx v.x, xx v.y, xx v.z};
}

iterate_vector3i :: (v: Vector3i, body: Code, for_flags: For_Flags) #expand {
    #assert for_flags == 0;

    y_chunk := v.x * v.y;
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

convert_3d_coordinate_to_index :: inline (coord: Vector3i, size: Vector3i) -> s64 {
    return coord.y * size.z * size.x + coord.z * size.x + coord.x;
}


Matrix4 :: struct {
    x_x, y_x, z_x, w_x,
    x_y, y_y, z_y, w_y,
    x_z, y_z, z_z, w_z,
    x_w, y_w, z_w, w_w: float;
}

MATRIX4_IDENTITY :: Matrix4.{ x_x=1, y_y=1, z_z=1, w_w=1};

matmul :: (a: Matrix4, b: Matrix4) -> Matrix4 {
    return .{
        a.x_x*b.x_x + a.y_x*b.x_y + a.z_x*b.x_z + a.w_x*b.x_w,
        a.x_x*b.y_x + a.y_x*b.y_y + a.z_x*b.y_z + a.w_x*b.y_w,
        a.x_x*b.z_x + a.y_x*b.z_y + a.z_x*b.z_z + a.w_x*b.z_w,
        a.x_x*b.w_x + a.y_x*b.w_y + a.z_x*b.w_z + a.w_x*b.w_w,
        
        a.x_y*b.x_x + a.y_y*b.x_y + a.z_y*b.x_z + a.w_y*b.x_w,
        a.x_y*b.y_x + a.y_y*b.y_y + a.z_y*b.y_z + a.w_y*b.y_w,
        a.x_y*b.z_x + a.y_y*b.z_y + a.z_y*b.z_z + a.w_y*b.z_w,
        a.x_y*b.w_x + a.y_y*b.w_y + a.z_y*b.w_z + a.w_y*b.w_w,

        a.x_z*b.x_x + a.y_z*b.x_y + a.z_z*b.x_z + a.w_z*b.x_w,
        a.x_z*b.y_x + a.y_z*b.y_y + a.z_z*b.y_z + a.w_z*b.y_w,
        a.x_z*b.z_x + a.y_z*b.z_y + a.z_z*b.z_z + a.w_z*b.z_w,
        a.x_z*b.w_x + a.y_z*b.w_y + a.z_z*b.w_z + a.w_z*b.w_w,

        a.x_w*b.x_x + a.y_w*b.x_y + a.z_w*b.x_z + a.w_w*b.x_w,
        a.x_w*b.y_x + a.y_w*b.y_y + a.z_w*b.y_z + a.w_w*b.y_w,
        a.x_w*b.z_x + a.y_w*b.z_y + a.z_w*b.z_z + a.w_w*b.z_w,
        a.x_w*b.w_x + a.y_w*b.w_y + a.z_w*b.w_z + a.w_w*b.w_w,
    };
}

// This assumes the input and output are opengl-style coorinate systems.
// X right
// Y up
// Z away
frustum :: (l: float, b: float, n: float, r: float, t: float, f: float) -> Matrix4 {
    return .{
        (2*n)/(r-l), 0,           -(r+l)/(r-l), 0,
        0,           (2*n)/(t-b), -(t+b)/(t-b), 0,
        0,           0,           (f+n)/(f-n),  -(2*f*n)/(f-n), 
        0,           0,           1,            0
    };
}

matrix4_translate :: (x: float, y: float, z: float) -> Matrix4 {
    return .{x_x=1, y_y=1, z_z=1, w_x=x, w_y=y, w_z=z, w_w=1};
}


// :Quaternion @TODO: Replace this with quaternion stuff
matrix4_rotate_y :: (r: float) -> Matrix4 {
    // Rotate about the y-axis
    sin_r := sin(r);
    cos_r := cos(r);
    return .{
        cos_r, 0, -sin_r, 0,
        0,     1, 0,      0,
        sin_r, 0, cos_r,  0,
        0,     0, 0,      1
    };
}

// :Quaternion
matrix4_rotate_x :: (r: float) -> Matrix4 {
    sin_r := sin(r);
    cos_r := cos(r);

    return .{
        1, 0,      0,     0,
        0, cos_r,  sin_r, 0,
        0, -sin_r, cos_r, 0,
        0, 0,      0,     1
    };
}
