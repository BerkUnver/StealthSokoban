Mesh :: struct {
    vao: GLuint;
    vbo: GLuint;
    vertex_count: u32;
}


make_cuboid :: (buf: [] u8, b: Vector3, e: Vector3, $has_uv: bool) -> [] u8 {
    buf_size := size_of(Vector3) + #ifx has_uv then size_of(Vector2) else 0;
    buf_size *= 36;

    assert(buf.count >= buf_size);
    
    d := buf.data;
    

    vertex :: (v: Vector3, uv: Vector2) #expand {
        cast(*Vector3, `d).* = v;
        d += size_of(Vector3);
        #if `has_uv {
            cast(*Vector2, d).* = uv;
            d += size_of(Vector2);
        }
    }
    
    vertex(.{b.x, b.y, b.z}, .{0, 0});
    vertex(.{e.x, b.y, b.z}, .{1, 0});
    vertex(.{e.x, e.y, b.z}, .{1, 1});
    vertex(.{b.x, b.y, b.z}, .{0, 0});
    vertex(.{e.x, e.y, b.z}, .{1, 1});
    vertex(.{b.x, e.y, b.z}, .{0, 1});
    vertex(.{e.x, b.y, b.z}, .{0, 0});
    vertex(.{e.x, b.y, e.z}, .{1, 0});
    vertex(.{e.x, e.y, e.z}, .{1, 1});
    vertex(.{e.x, b.y, b.z}, .{0, 0});
    vertex(.{e.x, e.y, e.z}, .{1, 1});
    vertex(.{e.x, e.y, b.z}, .{0, 1});
    vertex(.{b.x, e.y, b.z}, .{0, 0});
    vertex(.{e.x, e.y, b.z}, .{1, 0});
    vertex(.{e.x, e.y, e.z}, .{1, 1});
    vertex(.{b.x, e.y, b.z}, .{0, 0});
    vertex(.{e.x, e.y, e.z}, .{1, 1});
    vertex(.{b.x, e.y, e.z}, .{0, 1});
    vertex(.{e.x, b.y, b.z}, .{0, 0});
    vertex(.{b.x, b.y, b.z}, .{1, 0});
    vertex(.{b.x, b.y, e.z}, .{1, 1});
    vertex(.{e.x, b.y, b.z}, .{0, 0});
    vertex(.{b.x, b.y, e.z}, .{1, 1});
    vertex(.{e.x, b.y, e.z}, .{0, 1});
    vertex(.{b.x, b.y, e.z}, .{0, 0});
    vertex(.{b.x, b.y, b.z}, .{1, 0});
    vertex(.{b.x, e.y, b.z}, .{1, 1});
    vertex(.{b.x, b.y, e.z}, .{0, 0});
    vertex(.{b.x, e.y, b.z}, .{1, 1});
    vertex(.{b.x, e.y, e.z}, .{0, 1});
    vertex(.{e.x, b.y, e.z}, .{0, 0});
    vertex(.{b.x, b.y, e.z}, .{1, 0});
    vertex(.{b.x, e.y, e.z}, .{1, 1});
    vertex(.{e.x, b.y, e.z}, .{0, 0});
    vertex(.{b.x, e.y, e.z}, .{1, 1});
    vertex(.{e.x, e.y, e.z}, .{0, 1});

    return .{count = buf.count - buf_size, data = d};
}


make_cuboid_vertex_mesh :: (b: Vector3, e: Vector3) -> Mesh {
    using context.game_context;

    VERTEX_COUNT :: 36;
    v: [VERTEX_COUNT * size_of(Vector3)] u8 = ---;

    make_cuboid(v, b, e, has_uv = false);

    vao, vbo: GLuint;
    
    glGenBuffers(1, *vbo);
    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glBufferData(GL_ARRAY_BUFFER, v.count, v.data, GL_STATIC_DRAW); // Allocate the buffer

    glGenVertexArrays(1, *vao);
    glBindVertexArray(vao);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, size_of(Vector3), null);

    return .{vao = vao, vbo = vbo, vertex_count = VERTEX_COUNT};
}


make_block_mesh :: (size: Vector3i, filled: [] bool) -> Mesh {    
    using context.game_context;
    // @TODO @Speed @Memory: Optimize how many vertices this is to be only the faces of the cubes on the surface.
    // @TODO @Speed: Add reallocing from the top of the temporary buffer

    filled_count := 0;
    for :iterate_vector3i size {
        if filled[it_index] filled_count += 1;
    }

    Block_Vertex :: struct {
        position: Vector3;
        uv: Vector2;
    }
    

    mark := get_mark(*frame_arena);
    defer restore_mark(*frame_arena, mark);

    vertex_count := 36 * filled_count;
    vertices := arena_alloc_array(*frame_arena, size_of(Block_Vertex) * vertex_count, u8, zero_init = true);
    v := vertices;
    for :iterate_vector3i size {
        if filled[it_index] v = make_cuboid(v, to_vector3(it), to_vector3(it + Vector3i.{1, 1, 1}), has_uv = true);
    }

    vao, vbo: GLuint;
    
    glGenBuffers(1, *vbo);
    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glBufferData(GL_ARRAY_BUFFER, vertices.count, vertices.data, GL_STATIC_DRAW); // Allocate the buffer

    // @Copypasta Figure out how to use metaprogramming to generate vaos for arbitrary vertex formats.

    glGenVertexArrays(1, *vao);
    glBindVertexArray(vao);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, size_of(Block_Vertex), null);
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, size_of(Block_Vertex), *cast(*Block_Vertex, null).uv);

    return .{vao = vao, vbo = vbo, vertex_count = xx vertex_count};
}


draw_vertex_mesh :: (mesh: *Mesh, projection: Matrix4, color: Vector4) {
    using context.game_context;

    glUseProgram(color_shader);

    projection_loc := glGetUniformLocation(color_shader, "projection");
    assert(projection_loc >= 0);
    glUniformMatrix4fv(projection_loc, 1, GL_TRUE, *projection._11);

    color_loc := glGetUniformLocation(color_shader, "color");
    assert(color_loc >= 0);
    glUniform4f(color_loc, color.x, color.y, color.z, color.w);

    glBindVertexArray(mesh.vao);
    glBindBuffer(GL_ARRAY_BUFFER, mesh.vbo);

    glDrawArrays(GL_TRIANGLES, 0, mesh.vertex_count);
}


draw_block_mesh :: (mesh: *Mesh, projection: Matrix4, color: Vector4) {
    using context.game_context;

    glUseProgram(block_shader);
   
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, block_bitmap);
    bitmap_loc := glGetUniformLocation(block_shader, "bitmap");
    assert(bitmap_loc >= 0);
    glUniform1i(bitmap_loc, 0);


    projection_loc := glGetUniformLocation(block_shader, "projection");
    assert(projection_loc >= 0);
    glUniformMatrix4fv(projection_loc, 1, GL_TRUE, *projection._11);

    color_loc := glGetUniformLocation(block_shader, "color");
    assert(color_loc >= 0);
    glUniform4f(color_loc, color.x, color.y, color.z, color.w);


    glBindVertexArray(mesh.vao);
    glBindBuffer(GL_ARRAY_BUFFER, mesh.vbo);

    glDrawArrays(GL_TRIANGLES, 0, mesh.vertex_count);
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
