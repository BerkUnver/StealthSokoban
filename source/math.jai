// I really would like to take the time to deeply understand all of the math that goes
// into a 3D game, especially considering that math is currently my weakest point.
// However, I have a tight deadline to get a functional demo of this game ready.
// So, for the time being, we will bite the bullet and use the Jai standard math library.
// All of the commented-out stuff is stuff I implemented before I decided to just use
// the Jai standard library.

//          -berk, 25 - 1 - 2025

Vector3i :: struct {
    x, y, z: s32;
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

to_vector3i :: (v: Vector3) -> Vector3i {
    return .{xx v.x, xx v.y, xx v.z};
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


convert_3d_coordinate_to_index :: (coord: Vector3i, size: Vector3i) -> s64 {
    return coord.y * size.z * size.x + coord.z * size.x + coord.x;
}


inside_positive_bounding_box :: (v: Vector3i, bbox: Vector3i) -> bool {
    return
        0 <= v.x && v.x < bbox.x &&
        0 <= v.y && v.y < bbox.y &&
        0 <= v.z && v.z < bbox.z;
}

make_y_rotation_matrix4 :: (r: float) -> Matrix4 {
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


make_x_rotation_matrix4 :: (r: float) -> Matrix4 {
    sin_r := sin(r);
    cos_r := cos(r);

    return .{
        1, 0,      0,     0,
        0, cos_r,  sin_r, 0,
        0, -sin_r, cos_r, 0,
        0, 0,      0,     1
    };
}


make_left_handed_frustum_matrix :: (l: float, b: float, n: float, r: float, t: float, f: float) -> Matrix4 {
    return .{
        (2*n)/(r-l), 0,           -(r+l)/(r-l), 0,
        0,           (2*n)/(t-b), -(t+b)/(t-b), 0,
        0,           0,           (f+n)/(f-n),  -(2*f*n)/(f-n), 
        0,           0,           1,            0
    };
}


get_angle :: (start: Vector3, end: Vector3) -> float {
    return acos(dot(start, end) / (length(start) * length(end)));
}


sign :: (t: $T) -> T {
    // @TODO: Do we want to use funny branchless bit tricks for this?
    if t < 0 return -1;
    return 1;
}


multiply_homogeneous :: (m: Matrix4, v_: Vector3) -> Vector3 {
    v := Vector4.{v_.x, v_.y, v_.z, 1};
    result_4 := m * v;
    return result_4.xyz / result_4.w;
}


min :: (a: $T, b: T) -> T {
    return ifx a < b then a else b;
}

max :: (a: $T, b: T) -> T {
    return ifx a > b then a else b;
}

inverse :: (using q: Quaternion) -> Quaternion {
    return .{x=-x, y=-y, z=-z, w=w};
}


/*
PI :: 3.141592653689793238;

Vector2 :: struct {
    x, y: float;
} 

Vector3 :: struct {
    x, y, z: float;
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


matrix4_translate :: (v: Vector3) -> Matrix4 {
    return .{x_x=1, y_y=1, z_z=1, w_x=v.x, w_y=v.y, w_z=v.z, w_w=1};
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


Rotor :: struct {
    s := 1.0;
    xy, yz, zx: float;
}


make_rotor :: (v: Vector3, angle: float) -> Rotor {
    // Your axis is actually a bivector describing the plane you wish to rotate along.
    // I'm pretty sure x -> yz, y -> zx, z -> xy

    half := angle / 2;
    cos_half := cos(half);
    neg_sin_half := -sin(half);

    return .{
        s = cos_half,
        xy = neg_sin_half * v.z,
        yz = neg_sin_half * v.x,
        zx = neg_sin_half * v.y
    };
}


rotate :: (r: Rotor, v: Vector3) -> Vector3 {
    x := r.s*v.x + r.xy*v.y - r.zx*v.z;
    y := r.s*v.y - r.xy*v.x + r.yz*v.z;
    z := r.s*v.z - r.yz*v.y + r.zx*v.x;

    xyz := r.xy*v.z + r.yz*v.x + r.zx*v.y;
    
    return .{
        x*r.s + y*r.xy - z*r.zx + xyz*r.yz,
       -x*r.xy + y*r.s + z*r.yz + xyz*r.zx,
        x*r.zx - y*r.yz + z*r.s + xyz*r.xy,
    };
}

to_matrix4 :: (r: Rotor) -> Matrix4 {
    // @Speed See if inlining this gets rid of the multiplies by zero?
    x := rotate(r, .{1, 0, 0});
    y := rotate(r, .{0, 1, 0});
    z := rotate(r, .{0, 0, 1});

    return .{
        x.x, y.x, z.x, 0,
        x.y, y.y, z.y, 0,
        x.z, y.z, z.z, 0,
        0,   0,   0,   1
    };
}

inverse :: (r: Rotor) -> Rotor {
    return .{s=r.s, xy=-r.xy, yz=-r.yz, zx=-r.zx};
}
*/
