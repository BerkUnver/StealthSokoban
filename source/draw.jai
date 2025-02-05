Mesh :: struct {
    vao: GLuint;
    vbo: GLuint;
    vertex_count: u32;
}


make_cuboid_mesh :: (b: Vector3, e: Vector3, arena: *Memory_Arena) -> Mesh {
    using context.game_context;

    mark := get_mark(*frame_arena);
    defer restore_mark(*frame_arena, mark);
    
    Player_Vertex :: Vector3;

    v := arena_alloc_array(*frame_arena, 36, Player_Vertex);
    
    v[0]  = .{b.x, b.y, b.z}; // .{.{b.x, b.y, b.z}, color, .{0, 0}};
    v[1]  = .{e.x, b.y, b.z}; // .{.{e.x, b.y, b.z}, color, .{1, 0}};
    v[2]  = .{e.x, e.y, b.z}; // .{.{e.x, e.y, b.z}, color, .{1, 1}};
    v[3]  = .{b.x, b.y, b.z}; // .{.{b.x, b.y, b.z}, color, .{0, 0}};
    v[4]  = .{e.x, e.y, b.z}; // .{.{e.x, e.y, b.z}, color, .{1, 1}};
    v[5]  = .{b.x, e.y, b.z}; // .{.{b.x, e.y, b.z}, color, .{0, 1}};
    v[6]  = .{e.x, b.y, b.z}; // .{.{e.x, b.y, b.z}, color, .{0, 0}};
    v[7]  = .{e.x, b.y, e.z}; // .{.{e.x, b.y, e.z}, color, .{1, 0}};
    v[8]  = .{e.x, e.y, e.z}; // .{.{e.x, e.y, e.z}, color, .{1, 1}};
    v[9]  = .{e.x, b.y, b.z}; // .{.{e.x, b.y, b.z}, color, .{0, 0}};
    v[10] = .{e.x, e.y, e.z}; // .{.{e.x, e.y, e.z}, color, .{1, 1}};
    v[11] = .{e.x, e.y, b.z}; // .{.{e.x, e.y, b.z}, color, .{0, 1}};
    v[12] = .{b.x, e.y, b.z}; // .{.{b.x, e.y, b.z}, color, .{0, 0}};
    v[13] = .{e.x, e.y, b.z}; // .{.{e.x, e.y, b.z}, color, .{1, 0}};
    v[14] = .{e.x, e.y, e.z}; // .{.{e.x, e.y, e.z}, color, .{1, 1}};
    v[15] = .{b.x, e.y, b.z}; // .{.{b.x, e.y, b.z}, color, .{0, 0}};
    v[16] = .{e.x, e.y, e.z}; // .{.{e.x, e.y, e.z}, color, .{1, 1}};
    v[17] = .{b.x, e.y, e.z}; // .{.{b.x, e.y, e.z}, color, .{0, 1}};
    v[18] = .{e.x, b.y, b.z}; // .{.{e.x, b.y, b.z}, color, .{0, 0}};
    v[19] = .{b.x, b.y, b.z}; // .{.{b.x, b.y, b.z}, color, .{1, 0}};
    v[20] = .{b.x, b.y, e.z}; // .{.{b.x, b.y, e.z}, color, .{1, 1}};
    v[21] = .{e.x, b.y, b.z}; // .{.{e.x, b.y, b.z}, color, .{0, 0}};
    v[22] = .{b.x, b.y, e.z}; // .{.{b.x, b.y, e.z}, color, .{1, 1}};
    v[23] = .{e.x, b.y, e.z}; // .{.{e.x, b.y, e.z}, color, .{0, 1}};
    v[24] = .{b.x, b.y, e.z}; // .{.{b.x, b.y, e.z}, color, .{0, 0}};
    v[25] = .{b.x, b.y, b.z}; // .{.{b.x, b.y, b.z}, color, .{1, 0}};
    v[26] = .{b.x, e.y, b.z}; // .{.{b.x, e.y, b.z}, color, .{1, 1}};
    v[27] = .{b.x, b.y, e.z}; // .{.{b.x, b.y, e.z}, color, .{0, 0}};
    v[28] = .{b.x, e.y, b.z}; // .{.{b.x, e.y, b.z}, color, .{1, 1}};
    v[29] = .{b.x, e.y, e.z}; // .{.{b.x, e.y, e.z}, color, .{0, 1}};
    v[30] = .{e.x, b.y, e.z}; // .{.{e.x, b.y, e.z}, color, .{0, 0}};
    v[31] = .{b.x, b.y, e.z}; // .{.{b.x, b.y, e.z}, color, .{1, 0}};
    v[32] = .{b.x, e.y, e.z}; // .{.{b.x, e.y, e.z}, color, .{1, 1}};
    v[33] = .{e.x, b.y, e.z}; // .{.{e.x, b.y, e.z}, color, .{0, 0}};
    v[34] = .{b.x, e.y, e.z}; // .{.{b.x, e.y, e.z}, color, .{1, 1}};
    v[35] = .{e.x, e.y, e.z}; // .{.{e.x, e.y, e.z}, color, .{0, 1}};

    vao, vbo: GLuint;
    
    glGenBuffers(1, *vbo);
    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glBufferData(GL_ARRAY_BUFFER, size_of(Player_Vertex) * v.count, v.data, GL_STREAM_DRAW); // Allocate the buffer

    glGenVertexArrays(1, *vao);
    glBindVertexArray(vao);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, size_of(Player_Vertex), null);

    return .{vao = vao, vbo = vbo, vertex_count = xx v.count};
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
