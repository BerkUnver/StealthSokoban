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
    projection: Matrix4;
    shader: GLuint;
    bitmap: GLuint;
}


register_shader :: (text: string) -> GLuint {
    using context.game_context;

    LOG_SIZE :: 1024;

    vertex := glCreateShader(GL_VERTEX_SHADER);
    defer glDeleteShader(vertex);
    
    VERTEX_L0 :: "#version 330 core\n";
    VERTEX_L1 :: "#define VERTEX_SHADER\n";
    VERTEX_L2 :: "#define OUTIN out\n";

    vertex_lines := *u8.[
        VERTEX_L0,
        VERTEX_L1,
        VERTEX_L2,
        text.data
    ];

    vertex_lengths :=  GLint.[
        xx VERTEX_L0.count,
        xx VERTEX_L1.count,
        xx VERTEX_L2.count,
        xx text.count
    ];

    glShaderSource(vertex, xx vertex_lines.count, vertex_lines.data, vertex_lengths.data);
    glCompileShader(vertex);
    
    vertex_success: GLint;
    glGetShaderiv(vertex, GL_COMPILE_STATUS, *vertex_success);
    if !vertex_success {
        count: GLsizei;
        buffer: [LOG_SIZE] u8 = ---;
        glGetShaderInfoLog(vertex, LOG_SIZE, *count, *buffer[0]);

        str := string.{data=*buffer[0], count=count};

        print("Vertex shader compilation error:\n%", str);
        return 0;
    }
    
    fragment := glCreateShader(GL_FRAGMENT_SHADER);
    defer glDeleteShader(fragment);
    
    FRAGMENT_L0 :: "#version 330 core\n";
    FRAGMENT_L1 :: "#define OUTIN in\n";

    fragment_lines := *u8.[
        FRAGMENT_L0,
        FRAGMENT_L1,
        text.data
    ];

    fragment_lengths := GLint.[
        xx FRAGMENT_L0.count,
        xx FRAGMENT_L1.count,
        xx text.count
    ];

    glShaderSource(fragment, xx fragment_lines.count, fragment_lines.data, fragment_lengths.data);
    glCompileShader(fragment);

    fragment_success: GLint;
    glGetShaderiv(fragment, GL_COMPILE_STATUS, *fragment_success);
    if !fragment_success {
        count: GLsizei;
        buffer: [LOG_SIZE] u8 = ---;
        glGetShaderInfoLog(fragment, LOG_SIZE, *count, *buffer[0]);

        str := string.{data=*buffer[0], count=count};
        print("Fragment shader compilation error:\n%", str);
        return 0;
    }

    program := glCreateProgram();
    glAttachShader(program, vertex);
    glAttachShader(program, fragment);
    glLinkProgram(program);
    
    link_success: GLint;
    glGetProgramiv(program, GL_LINK_STATUS, *link_success);
    if !link_success {
        count: GLsizei;
        buffer: [LOG_SIZE] u8 = ---;
        glGetProgramInfoLog(program, LOG_SIZE, *count, *buffer[0]);

        str := string.{data=*buffer[0], count=count};
        print("Shader linking error:\n");
        print(str);
        return 0;
    }

    return program;
}


imm_init :: () {
    using context.game_context.imm_state;
    using context.game_context;

    glGenBuffers(1, *vbo);
    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
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
    

    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, bitmap);

    if vao != 0 glDeleteVertexArrays(1, *vao);
    glGenVertexArrays(1, *vao);
    glBindVertexArray(vao);
    
    glUseProgram(shader);

    projection_loc := glGetUniformLocation(shader, "projection");
    assert(projection_loc >= 0);
    glUniformMatrix4fv(projection_loc, 1, GL_TRUE, *projection._11);
    
    bitmap_loc := glGetUniformLocation(shader, "bitmap");
    if bitmap_loc >= 0 glUniform1i(bitmap_loc, 0);

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

imm_set_shader :: (shader: GLuint) {
    context.game_context.imm_state.shader = shader; 
}

imm_set_bitmap :: (bitmap: GLuint) {
    context.game_context.imm_state.bitmap = bitmap;
}

imm_set_projection :: (projection: Matrix4) {
    context.game_context.imm_state.projection = projection;
}

imm_get_projection :: () -> Matrix4 {
    return context.game_context.imm_state.projection;
}

imm_vertex :: (position: Vector3, color: Vector4, uv: Vector2) {
    using context.game_context.imm_state;
    if vertex_count == vertices.count imm_flush();
    vertices[vertex_count] = .{
        position=position,
        color=color,
        uv=uv,
    };
    vertex_count += 1;
}


imm_cuboid :: (b: Vector3, e: Vector3, color: Vector4) {
    // @Speed make a different version of this if we're not using the UV coordinates.
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
