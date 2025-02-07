Vertex :: struct {
    position: Vector3;
    color: Vector4;
    uv: Vector2;
}

Imm_State :: struct {
    vao: GLuint;
    vbo: GLuint;
    vertices: [2400] Vertex;
    vertex_count: u32;

    // @TODO: Should we store the shader on here instead of setting it explicitly with OpenGL?
    // I don't want to do premature stuff, and right now the most explicit thing to do seems to be
    // setting everything directly and only putting vertices here. I will keep it the way it is
    // for now.
}

imm_init :: () {
    using context.game_context.imm_state;
    using context.game_context;

    glGenBuffers(1, *vbo);
    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glBufferData(GL_ARRAY_BUFFER, size_of(Vertex) * vertices.count, null, GL_STREAM_DRAW); // Allocate the buffer
    glGenVertexArrays(1, *vao);
    
    glBindVertexArray(vao);
    
    // Apparently you need to enable all the attribs on the vao before you compile the shaders,
    // or else OpenGL will recompile your shader when you enable them.

    vertex_type_info := type_info(Vertex);
    for 0..vertex_type_info.members.count-1 {
        glEnableVertexAttribArray(xx it);
    }
}


imm_flush :: () {
    using context.game_context.imm_state;
    using context.game_context;
    
    shader_GLint: GLint;
    glGetIntegerv(GL_CURRENT_PROGRAM, *shader_GLint);
    assert(shader_GLint >= 0);
    shader := cast(GLuint, shader_GLint);

    glBindBuffer(GL_ARRAY_BUFFER, vbo);

    glBindVertexArray(vao);
    
    position_loc := glGetAttribLocation(shader, "vertex_position");
    if position_loc >= 0 {
        glVertexAttribPointer(xx position_loc, 3, GL_FLOAT, GL_FALSE, size_of(Vertex), *cast(*Vertex, null).position);
        glEnableVertexAttribArray(xx position_loc);
    }

    color_loc := glGetAttribLocation(shader, "vertex_color");
    if color_loc >= 0 {
        glVertexAttribPointer(xx color_loc, 4, GL_FLOAT, GL_FALSE, size_of(Vertex), *cast(*Vertex, null).color);
        glEnableVertexAttribArray(xx color_loc);
    }

    uv_loc := glGetAttribLocation(shader, "vertex_uv");
    if uv_loc >= 0 {
        glVertexAttribPointer(xx uv_loc, 2, GL_FLOAT, GL_FALSE, size_of(Vertex), *cast(*Vertex, null).uv);
        glEnableVertexAttribArray(xx uv_loc);
    }


    glBufferSubData(GL_ARRAY_BUFFER, 0, size_of(Vertex) * vertex_count, vertices.data);
    glDrawArrays(GL_TRIANGLES, 0, vertex_count);
    vertex_count = 0;
}


imm_vertex_ptr :: () -> *Vertex {
    using context.game_context.imm_state;
    if vertex_count == vertices.count imm_flush();
    v := *vertices[vertex_count];
    vertex_count += 1;
    return v;
}


imm_vertex :: (position: Vector3, color: Vector4, uv: Vector2) {
    v := imm_vertex_ptr();
    v.position = position;
    v.color = color;
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


imm_quad_y :: (y: float, begin_x: float, begin_z: float, end_x: float, end_z: float) {
    imm_vertex(.{begin_x, y, begin_z});
    imm_vertex(.{end_x,   y, begin_z});
    imm_vertex(.{end_x,   y, end_z});
    imm_vertex(.{begin_x, y, begin_z});
    imm_vertex(.{end_x,   y, end_z});
    imm_vertex(.{begin_x, y, end_z});
}


imm_cuboid :: (b: Vector3, e: Vector3, color: Vector4) {
    // b: beginning, the bottom corner of the cuboid
    // e: end, the top corner of the cuboid

    // Front face
    imm_vertex(.{b.x, b.y, b.z}, color);
    imm_vertex(.{e.x, b.y, b.z}, color);
    imm_vertex(.{e.x, e.y, b.z}, color);
    imm_vertex(.{b.x, b.y, b.z}, color);
    imm_vertex(.{e.x, e.y, b.z}, color);
    imm_vertex(.{b.x, e.y, b.z}, color);
    
    // Right face
    imm_vertex(.{e.x, b.y, b.z}, color);
    imm_vertex(.{e.x, b.y, e.z}, color);
    imm_vertex(.{e.x, e.y, e.z}, color);
    imm_vertex(.{e.x, b.y, b.z}, color);
    imm_vertex(.{e.x, e.y, e.z}, color);
    imm_vertex(.{e.x, e.y, b.z}, color);
    
    // Top face
    imm_vertex(.{b.x, e.y, b.z}, color);
    imm_vertex(.{e.x, e.y, b.z}, color);
    imm_vertex(.{e.x, e.y, e.z}, color);
    imm_vertex(.{b.x, e.y, b.z}, color);
    imm_vertex(.{e.x, e.y, e.z}, color);
    imm_vertex(.{b.x, e.y, e.z}, color);
    
    // Bottom face
    imm_vertex(.{e.x, b.y, b.z}, color);
    imm_vertex(.{b.x, b.y, b.z}, color);
    imm_vertex(.{b.x, b.y, e.z}, color);
    imm_vertex(.{e.x, b.y, b.z}, color);
    imm_vertex(.{b.x, b.y, e.z}, color);
    imm_vertex(.{e.x, b.y, e.z}, color);

    // Left face
    imm_vertex(.{b.x, b.y, e.z}, color);
    imm_vertex(.{b.x, b.y, b.z}, color);
    imm_vertex(.{b.x, e.y, b.z}, color);
    imm_vertex(.{b.x, b.y, e.z}, color);
    imm_vertex(.{b.x, e.y, b.z}, color);
    imm_vertex(.{b.x, e.y, e.z}, color);

    // Back face
    imm_vertex(.{e.x, b.y, e.z}, color);
    imm_vertex(.{b.x, b.y, e.z}, color);
    imm_vertex(.{b.x, e.y, e.z}, color);
    imm_vertex(.{e.x, b.y, e.z}, color);
    imm_vertex(.{b.x, e.y, e.z}, color);
    imm_vertex(.{e.x, e.y, e.z}, color);
}


imm_cuboid_with_uvs :: (b: Vector3, e: Vector3, color: Vector4) {
    // @Copypasta imm_cuboid but with uvs
    // b: beginning, the bottom corner of the cuboid
    // e: end, the top corner of the cuboid

    // Front face
    imm_vertex(.{b.x, b.y, b.z}, color, .{0, 0});
    imm_vertex(.{e.x, b.y, b.z}, color, .{1, 0});
    imm_vertex(.{e.x, e.y, b.z}, color, .{1, 1});
    imm_vertex(.{b.x, b.y, b.z}, color, .{0, 0});
    imm_vertex(.{e.x, e.y, b.z}, color, .{1, 1});
    imm_vertex(.{b.x, e.y, b.z}, color, .{0, 1});
    
    // Right face
    imm_vertex(.{e.x, b.y, b.z}, color, .{0, 0});
    imm_vertex(.{e.x, b.y, e.z}, color, .{1, 0});
    imm_vertex(.{e.x, e.y, e.z}, color, .{1, 1});
    imm_vertex(.{e.x, b.y, b.z}, color, .{0, 0});
    imm_vertex(.{e.x, e.y, e.z}, color, .{1, 1});
    imm_vertex(.{e.x, e.y, b.z}, color, .{0, 1});
    
    // Top face
    imm_vertex(.{b.x, e.y, b.z}, color, .{0, 0});
    imm_vertex(.{e.x, e.y, b.z}, color, .{1, 0});
    imm_vertex(.{e.x, e.y, e.z}, color, .{1, 1});
    imm_vertex(.{b.x, e.y, b.z}, color, .{0, 0});
    imm_vertex(.{e.x, e.y, e.z}, color, .{1, 1});
    imm_vertex(.{b.x, e.y, e.z}, color, .{0, 1});
    
    // Bottom face
    imm_vertex(.{e.x, b.y, b.z}, color, .{0, 0});
    imm_vertex(.{b.x, b.y, b.z}, color, .{1, 0});
    imm_vertex(.{b.x, b.y, e.z}, color, .{1, 1});
    imm_vertex(.{e.x, b.y, b.z}, color, .{0, 0});
    imm_vertex(.{b.x, b.y, e.z}, color, .{1, 1});
    imm_vertex(.{e.x, b.y, e.z}, color, .{0, 1});

    // Left face
    imm_vertex(.{b.x, b.y, e.z}, color, .{0, 0});
    imm_vertex(.{b.x, b.y, b.z}, color, .{1, 0});
    imm_vertex(.{b.x, e.y, b.z}, color, .{1, 1});
    imm_vertex(.{b.x, b.y, e.z}, color, .{0, 0});
    imm_vertex(.{b.x, e.y, b.z}, color, .{1, 1});
    imm_vertex(.{b.x, e.y, e.z}, color, .{0, 1});

    // Back face
    imm_vertex(.{e.x, b.y, e.z}, color, .{0, 0});
    imm_vertex(.{b.x, b.y, e.z}, color, .{1, 0});
    imm_vertex(.{b.x, e.y, e.z}, color, .{1, 1});
    imm_vertex(.{e.x, b.y, e.z}, color, .{0, 0});
    imm_vertex(.{b.x, e.y, e.z}, color, .{1, 1});
    imm_vertex(.{e.x, e.y, e.z}, color, .{0, 1});
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


// @TODO Make a version of imm_vertex that doesn't require uvs!
draw_arrow :: (start: Vector3, end: Vector3, color: Vector4, projection: *Matrix4,  radius := 0.03) {
    using context.game_context;
    difference := end - start;
    rot_quaternion := make_quaternion(Vector3.{1, 0, 0}, difference);
    rot_matrix := rotation_matrix(Matrix4, rot_quaternion);
    offset_matrix := make_translation_matrix4(start);
   

    glUseProgram(color_shader);
    projection_matrix := projection * multiply(offset_matrix, rot_matrix);
    set_uniform("projection", *projection_matrix);
    
    cuboid_start := Vector3.{0, -radius, -radius};

    arrow_length := length(difference);
    arrow_head_radius := radius * 3;
    arrow_head_length := radius * 6;
    cuboid_end_x := arrow_length - arrow_head_length;
    cuboid_end := Vector3.{cuboid_end_x, radius, radius};

    imm_cuboid(cuboid_start, cuboid_end, color);

    // arrow head
    imm_vertex(.{cuboid_end_x, -arrow_head_radius, -arrow_head_radius}, color, .{});
    imm_vertex(.{arrow_length, 0, 0}, color, .{});
    imm_vertex(.{cuboid_end_x, arrow_head_radius, -arrow_head_radius}, color, .{});
    
    imm_vertex(.{cuboid_end_x, arrow_head_radius, -arrow_head_radius}, color, .{});
    imm_vertex(.{arrow_length, 0, 0}, color, .{});
    imm_vertex(.{cuboid_end_x, arrow_head_radius, arrow_head_radius}, color, .{});

    imm_vertex(.{cuboid_end_x, arrow_head_radius, arrow_head_radius}, color, .{});
    imm_vertex(.{arrow_length, 0, 0}, color, .{});
    imm_vertex(.{cuboid_end_x, -arrow_head_radius, arrow_head_radius}, color, .{});

    imm_vertex(.{cuboid_end_x, -arrow_head_radius, arrow_head_radius}, color, .{});
    imm_vertex(.{arrow_length, 0, 0}, color, .{});
    imm_vertex(.{cuboid_end_x, -arrow_head_radius, -arrow_head_radius}, color, .{});
    
    // Face behind arrow head

    imm_vertex(.{cuboid_end_x, -arrow_head_radius, -arrow_head_radius}, color, .{});
    imm_vertex(.{cuboid_end_x, arrow_head_radius, -arrow_head_radius}, color, .{});
    imm_vertex(.{cuboid_end_x, -arrow_head_radius, arrow_head_radius}, color, .{});

    imm_vertex(.{cuboid_end_x, -arrow_head_radius, arrow_head_radius}, color, .{});
    imm_vertex(.{cuboid_end_x, arrow_head_radius, -arrow_head_radius}, color, .{});
    imm_vertex(.{cuboid_end_x, arrow_head_radius, arrow_head_radius}, color, .{});

    imm_flush();
}
