Vertex :: struct {
    position: Vector3;
    color: Vector4;
    uv: Vector2;
}

Imm_State :: struct {
    vao: GLuint;
    vbo: GLuint;
    vertices: [4096] Vertex;
    vertex_count: u32;
    shader: GLuint;
    bitmap: GLuint;
}


register_shader :: (using gl_procs: GL_Procedures, text: string) -> GLuint {
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
        print("Vertex shader compilation error:\n");
        print(str);
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
        print("Fragment shader compilation error:\n");
        print(str);
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


imm_init :: (using g: *Game) {
    using g.imm_state;

    glGenBuffers(1, *vbo);
    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
    glBufferData(GL_ARRAY_BUFFER, size_of(Vertex) * vertices.count, null, GL_STREAM_DRAW); // Allocate the buffer
    glGenVertexArrays(1, *vao);
}

imm_flush :: (using g: *Game) {
    using g.imm_state;
    
    glUseProgram(shader);

    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, bitmap);

    if vao != 0 glDeleteVertexArrays(1, *vao);
    glGenVertexArrays(1, *vao);
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

imm_set_shader :: (using g: *Game, shader: GLuint) {
    imm_state.shader = shader; 
}

imm_set_bitmap :: (using g: *Game, bitmap: GLuint) {
    imm_state.bitmap = bitmap;
}

imm_vertex :: (g: *Game, position: Vector3, color: Vector4, uv: Vector2) {
    using g.imm_state;
    if vertex_count == vertices.count imm_flush(g);
    vertices[vertex_count] = .{
        position=position,
        color=color,
        uv=uv,
    };
    vertex_count += 1;
}

/*
imm_vertex :: (using g: *Game) -> *Vertex {
    using g.imm_state;
    if vertex_count >= vertices.count {
        imm_flush();
        vertex_count = 1;
        return *vertices[0];
    }
    
    v := *vertices[vertex_count];
    vertex_count += 1;
    return v;
}
*/

imm_cuboid :: (g: *Game, b: Vector3, e: Vector3, color: Vector4) {
    // b: beginning, the bottom corner of the cuboid
    // e: end, the top corner of the cuboid

    // Front face
    imm_vertex(g, .{b.x, b.y, b.z}, color, .{0, 0});
    imm_vertex(g, .{e.x, b.y, b.z}, color, .{1, 0});
    imm_vertex(g, .{e.x, e.y, b.z}, color, .{1, 1});
    imm_vertex(g, .{b.x, b.y, b.z}, color, .{0, 0});
    imm_vertex(g, .{e.x, e.y, b.z}, color, .{1, 1});
    imm_vertex(g, .{b.x, e.y, b.z}, color, .{0, 1});
    
    // Right face
    imm_vertex(g, .{e.x, b.y, b.z}, color, .{0, 0});
    imm_vertex(g, .{e.x, b.y, e.z}, color, .{1, 0});
    imm_vertex(g, .{e.x, e.y, e.z}, color, .{1, 1});
    imm_vertex(g, .{e.x, b.y, b.z}, color, .{0, 0});
    imm_vertex(g, .{e.x, e.y, e.z}, color, .{1, 1});
    imm_vertex(g, .{e.x, e.y, b.z}, color, .{0, 1});
    
    // Top face
    imm_vertex(g, .{b.x, e.y, b.z}, color, .{0, 0});
    imm_vertex(g, .{e.x, e.y, b.z}, color, .{1, 0});
    imm_vertex(g, .{e.x, e.y, e.z}, color, .{1, 1});
    imm_vertex(g, .{b.x, e.y, b.z}, color, .{0, 0});
    imm_vertex(g, .{e.x, e.y, e.z}, color, .{1, 1});
    imm_vertex(g, .{b.x, e.y, e.z}, color, .{0, 1});
    
    // Bottom face
    imm_vertex(g, .{e.x, b.y, b.z}, color, .{0, 0});
    imm_vertex(g, .{b.x, b.y, b.z}, color, .{1, 0});
    imm_vertex(g, .{b.x, b.y, e.z}, color, .{1, 1});
    imm_vertex(g, .{e.x, b.y, b.z}, color, .{0, 0});
    imm_vertex(g, .{b.x, b.y, e.z}, color, .{1, 1});
    imm_vertex(g, .{e.x, b.y, e.z}, color, .{0, 1});

    // Left face
    imm_vertex(g, .{b.x, b.y, e.z}, color, .{0, 0});
    imm_vertex(g, .{b.x, b.y, b.z}, color, .{1, 0});
    imm_vertex(g, .{b.x, e.y, b.z}, color, .{1, 1});
    imm_vertex(g, .{b.x, b.y, e.z}, color, .{0, 0});
    imm_vertex(g, .{b.x, e.y, b.z}, color, .{1, 1});
    imm_vertex(g, .{b.x, e.y, e.z}, color, .{0, 1});

    // Back face
    imm_vertex(g, .{e.x, b.y, e.z}, .{1, 0, 0, 1}, .{0, 0});
    imm_vertex(g, .{b.x, b.y, e.z}, .{0, 1, 0, 1}, .{1, 0});
    imm_vertex(g, .{b.x, e.y, e.z}, .{0, 0, 1, 1}, .{1, 1});
    imm_vertex(g, .{e.x, b.y, e.z}, .{1, 0, 0, 1}, .{0, 0});
    imm_vertex(g, .{b.x, e.y, e.z}, .{0, 0, 1, 1}, .{1, 1});
    imm_vertex(g, .{e.x, e.y, e.z}, .{0, 1, 0, 1}, .{0, 1});

}


// @TODO: Replace this with dynamically generating a mesh for the cubemap
// cubes are x-major.
imm_cube_map :: (g: *Game, cubes: [] bool, x_count: u32, y_count: u32, corner: Vector3, color: Vector4) {
    assert(cubes.count == cast(s64, x_count * y_count));

    x_begin_map := corner.x;
    
    y_begin := corner.y;
    y_end := corner.y + 1;

    z_begin_map := corner.z;
    

    // The "y axis" of the cubes is equivalent to the z-axis of the coordinate system
    for y_index: 0..y_count-1 {
        offset := y_index * x_count;
        z_begin := z_begin_map + cast(float, y_index);
        z_end := z_begin + 1;
        for x_index: 0..x_count-1 {
            has_cube := cubes[offset + x_index];
            if !has_cube continue;
            x_begin := x_begin_map + cast(float, x_index);
            x_end := x_begin + 1;
            imm_cuboid(g, .{x_begin, y_begin, z_begin}, .{x_end, y_end, z_end}, color);
        }
    }
}
