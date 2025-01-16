Vector2 :: struct {
    x, y: float;
}

Vector3 :: struct {
    x, y, z: float;
}

Vector4 :: struct {
    x, y, z, w: float;
}


Matrix4 :: struct {
    x_x, y_x, z_x, w_x,
    x_y, y_y, z_y, w_y,
    x_z, y_z, z_z, w_z,
    x_w, y_w, z_w, w_w: float;
}

MATRIX4_IDENTITY :: Matrix4.{ x_x=1, y_y=1, z_z=1, w_w=1};
