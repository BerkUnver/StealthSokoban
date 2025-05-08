Imm_State :: struct {
    vao: GLuint;
    vbo: GLuint;
    vertices: [7200] Imm_Vertex;
    vertex_count: u32;

    // @TODO: Should we store the shader on here instead of setting it explicitly with OpenGL?
    // I don't want to do premature stuff, and right now the most explicit thing to do seems to be
    // setting everything directly and only putting vertices here. I will keep it the way it is
    // for now.
}

imm_init :: () -> Imm_State {
    using context.game_context.gl_procs;
    
    using imm_state: Imm_State;

    glGenVertexArrays(1, *vao);
    glBindVertexArray(vao);

    glGenBuffers(1, *vbo);
    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glBufferData(GL_ARRAY_BUFFER, byte_count(vertices), null, GL_STREAM_DRAW); // Allocate the buffer
    
    v: *Imm_Vertex;

    // @Speed make this SOA
    using Layout_Location;
    glEnableVertexAttribArray(xx POSITION);
    glVertexAttribPointer(xx POSITION, 3, GL_FLOAT, GL_FALSE, size_of(Imm_Vertex), *v.position);

    glEnableVertexAttribArray(xx UV);
    glVertexAttribPointer(xx UV, 2, GL_FLOAT, GL_FALSE, size_of(Imm_Vertex), *v.uv);

    glEnableVertexAttribArray(xx COLOR);
    glVertexAttribPointer(xx COLOR, 4, GL_FLOAT, GL_FALSE, size_of(Imm_Vertex), *v.color);

    return imm_state;
}


imm_flush :: () {
    using context.game_context.imm_state;
    using context.game_context;
    
    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glBufferSubData(GL_ARRAY_BUFFER, 0, size_of(Imm_Vertex) * vertex_count, vertices.data);

    glBindVertexArray(vao);
    glDrawArrays(GL_TRIANGLES, 0, vertex_count);
    vertex_count = 0;
}


imm_vertex_ptr :: () -> *Imm_Vertex {
    using context.game_context.imm_state;
    if vertex_count == vertices.count imm_flush();
    v := *vertices[vertex_count];
    vertex_count += 1;
    return v;
}


imm_vertex :: (position: Vector3, uv: Vector2, color: Vector4) {
    v := imm_vertex_ptr();
    v.position = position;
    v.color = color;
    v.uv = uv;
}


imm_vertex :: (position: Vector3, uv: Vector2) {
    v := imm_vertex_ptr();
    v.position = position;
    v.uv = uv;
}


imm_vertex :: (position: Vector3, color: Vector4) {
    v := imm_vertex_ptr();
    v.position = position;
    v.color = color;
}


imm_vertex :: (position: Vector3) {
    v := imm_vertex_ptr();
    v.position = position;
}


imm_quad :: (position: Vector2, size: Vector2, color: Vector4) {
    x0 := position.x;
    y0 := position.y;
    x1 := position.x + size.x;
    y1 := position.y + size.y;

    imm_vertex(.{x0, y0, 0}, color);
    imm_vertex(.{x1, y0, 0}, color);
    imm_vertex(.{x1, y1, 0}, color);
    imm_vertex(.{x0, y0, 0}, color);
    imm_vertex(.{x1, y1, 0}, color);
    imm_vertex(.{x0, y1, 0}, color);
}


imm_quad :: (position: Vector2, size: Vector2) {
    x0 := position.x;
    y0 := position.y;
    x1 := position.x + size.x;
    y1 := position.y + size.y;

    imm_vertex(.{x0, y0, 0});
    imm_vertex(.{x1, y0, 0});
    imm_vertex(.{x1, y1, 0});
    imm_vertex(.{x0, y0, 0});
    imm_vertex(.{x1, y1, 0});
    imm_vertex(.{x0, y1, 0});
}


imm_cuboid :: (begin: Vector3, end: Vector3, color: Vector4) {
    size := end - begin;
    for 0..35 {
        imm_vertex(begin + CUBE_VERTICES[it] * size, color);
    }
}


imm_cuboid_with_uvs :: (begin: Vector3, end: Vector3, color: Vector4) {
    size := end - begin;
    for 0..35 {
        imm_vertex(begin + CUBE_VERTICES[it] * size, CUBE_UVS[it], color);
    }
}


imm_cuboid_outline :: (start: Vector3, end: Vector3, width: float, color: Vector4) {
    // @Speed reduce the number of duplicate vertices.
    s0 := start;
    s3 := end;

    s10 := Vector3.{s3.x, s0.y, s0.z};
    s11 := Vector3.{s0.x, s3.y, s0.z};
    s12 := Vector3.{s0.x, s0.y, s3.z};

    s20 := Vector3.{s0.x, s3.y, s3.z};
    s21 := Vector3.{s3.x, s0.y, s3.z};
    s22 := Vector3.{s3.x, s3.y, s0.z};

    offset := Vector3.{width, width, width};

    b0 := s0 - offset;

    e10 := s10 + offset;
    e11 := s11 + offset;
    e12 := s12 + offset;

    b10 := s10 - offset;
    b11 := s11 - offset;
    b12 := s12 - offset;

    e20 := s20 + offset;
    e21 := s21 + offset;
    e22 := s22 + offset;

    b20 := s20 - offset;
    b21 := s21 - offset;
    b22 := s22 - offset;

    e3 := s3 + offset;

    imm_cuboid(b0, e10, color);
    imm_cuboid(b0, e11, color);
    imm_cuboid(b0, e12, color);

    imm_cuboid(b10, e21, color);
    imm_cuboid(b10, e22, color);
    imm_cuboid(b11, e20, color);
    imm_cuboid(b11, e22, color);
    imm_cuboid(b12, e20, color);
    imm_cuboid(b12, e21, color);

    imm_cuboid(b20, e3, color);
    imm_cuboid(b21, e3, color);
    imm_cuboid(b22, e3, color);
}


draw_arrow :: (start: Vector3, end: Vector3, color: Vector4, projection: Matrix4,  radius := 0.03) {
    using context.game_context;
    difference := end - start;
    rot_quaternion := make_quaternion(Vector3.{1, 0, 0}, difference);
    rot_matrix := rotation_matrix(Matrix4, rot_quaternion);
    offset_matrix := make_translation_matrix4(start);
   
    
    set_shader(imm_color_shader);
    projection_matrix := projection * multiply(offset_matrix, rot_matrix);
    set_uniform("projection", projection_matrix);
    
    cuboid_start := Vector3.{0, -radius, -radius};

    arrow_length := length(difference);
    arrow_head_radius := radius * 3;
    arrow_head_length := radius * 6;
    cuboid_end_x := arrow_length - arrow_head_length;
    cuboid_end := Vector3.{cuboid_end_x, radius, radius};

    imm_cuboid(cuboid_start, cuboid_end, color);

    // arrow head
    imm_vertex(.{cuboid_end_x, -arrow_head_radius, -arrow_head_radius}, color);
    imm_vertex(.{arrow_length, 0, 0}, color);
    imm_vertex(.{cuboid_end_x, arrow_head_radius, -arrow_head_radius}, color);
    
    imm_vertex(.{cuboid_end_x, arrow_head_radius, -arrow_head_radius}, color);
    imm_vertex(.{arrow_length, 0, 0}, color);
    imm_vertex(.{cuboid_end_x, arrow_head_radius, arrow_head_radius}, color);

    imm_vertex(.{cuboid_end_x, arrow_head_radius, arrow_head_radius}, color);
    imm_vertex(.{arrow_length, 0, 0}, color);
    imm_vertex(.{cuboid_end_x, -arrow_head_radius, arrow_head_radius}, color);

    imm_vertex(.{cuboid_end_x, -arrow_head_radius, arrow_head_radius}, color);
    imm_vertex(.{arrow_length, 0, 0}, color);
    imm_vertex(.{cuboid_end_x, -arrow_head_radius, -arrow_head_radius}, color);
    
    // Face behind arrow head

    imm_vertex(.{cuboid_end_x, -arrow_head_radius, -arrow_head_radius}, color);
    imm_vertex(.{cuboid_end_x, arrow_head_radius, -arrow_head_radius}, color);
    imm_vertex(.{cuboid_end_x, -arrow_head_radius, arrow_head_radius}, color);

    imm_vertex(.{cuboid_end_x, -arrow_head_radius, arrow_head_radius}, color);
    imm_vertex(.{cuboid_end_x, arrow_head_radius, -arrow_head_radius}, color);
    imm_vertex(.{cuboid_end_x, arrow_head_radius, arrow_head_radius}, color);

    imm_flush();
}


draw_text :: (str: string, position: Vector2, font: *Font, color: Vector4) -> end_x: float {
    using context.game_context;
    
    set_shader(imm_text_shader, .{flags = .BLEND});
    set_uniform_bitmap("bitmap", 0, *font.bitmap);
    set_uniform("projection", ui_to_camera);
    
    x := round(position.x);
    y := round(position.y);

    for str {
        if it == #char " " {
            x += font.space_advance;
        } else {
            assert(VALID_ASCII_START <= it && it <= VALID_ASCII_END);
            using glyph := *font.glyphs[it - VALID_ASCII_START];

            x0 := x + bearing.x;
            y0 := y - bearing.y;
            x1 := x0 + size.x;
            y1 := y0 + size.y;

            imm_vertex(.{x0, y0, 0}, .{uv_x0, uv_y0}, color);
            imm_vertex(.{x1, y0, 0}, .{uv_x1, uv_y0}, color);
            imm_vertex(.{x1, y1, 0}, .{uv_x1, uv_y1}, color);

            imm_vertex(.{x0, y0, 0}, .{uv_x0, uv_y0}, color);
            imm_vertex(.{x1, y1, 0}, .{uv_x1, uv_y1}, color);
            imm_vertex(.{x0, y1, 0}, .{uv_x0, uv_y1}, color);

            x += advance;
        }
    }

    imm_flush();

    return x;
}

