Mesh :: struct {
    vertices: [] Vector3; // We store this information on the CPU so we can raycast against it.
    vao: GLuint;
    vbo: GLuint;
}


Cube_Vertex :: enum {
    Z_NEGATIVE :: 0;
    X_POSITIVE :: 6;
    Y_POSITIVE :: 12;
    Y_NEGATIVE :: 18;
    X_NEGATIVE :: 24;
    Z_POSITIVE :: 30;
    COUNT :: 36;
}


cube_vertices : [Cube_Vertex.COUNT] Vector3 : .[
    // Front face
    .{0, 0, 0},
    .{1, 0, 0},
    .{1, 1, 0},
    .{0, 0, 0},
    .{1, 1, 0},
    .{0, 1, 0},
    
    // Right face
    .{1, 0, 0},
    .{1, 0, 1},
    .{1, 1, 1},
    .{1, 0, 0},
    .{1, 1, 1},
    .{1, 1, 0},
    
    // Top face
    .{0, 1, 0},
    .{1, 1, 0},
    .{1, 1, 1},
    .{0, 1, 0},
    .{1, 1, 1},
    .{0, 1, 1},
    
    // Bottom face
    .{1, 0, 0},
    .{0, 0, 0},
    .{0, 0, 1},
    .{1, 0, 0},
    .{0, 0, 1},
    .{1, 0, 1},

    // Left face
    .{0, 0, 1},
    .{0, 0, 0},
    .{0, 1, 0},
    .{0, 0, 1},
    .{0, 1, 0},
    .{0, 1, 1},

    // Back face
    .{1, 0, 1},
    .{0, 0, 1},
    .{0, 1, 1},
    .{1, 0, 1},
    .{0, 1, 1},
    .{1, 1, 1},
];


cube_uvs : [Cube_Vertex.COUNT] Vector2 : .[
    .{0, 0},
    .{1, 0},
    .{1, 1},
    .{0, 0},
    .{1, 1},
    .{0, 1},
    
    // Right face
    .{0, 0},
    .{1, 0},
    .{1, 1},
    .{0, 0},
    .{1, 1},
    .{0, 1},
    
    // Top face
    .{0, 0},
    .{1, 0},
    .{1, 1},
    .{0, 0},
    .{1, 1},
    .{0, 1},
    
    // Bottom face
    .{0, 0},
    .{1, 0},
    .{1, 1},
    .{0, 0},
    .{1, 1},
    .{0, 1},

    // Left face
    .{0, 0},
    .{1, 0},
    .{1, 1},
    .{0, 0},
    .{1, 1},
    .{0, 1},

    // Back face
    .{0, 0},
    .{1, 0},
    .{1, 1},
    .{0, 0},
    .{1, 1},
    .{0, 1},
];


make_cuboid :: (vertices: [] Vector3, begin: Vector3, end: Vector3) -> [] Vector3 { 
    size := end - begin;
    for 0..35 {
        vertices[it] = begin + cube_vertices[it] * size;
    }
    return slice(vertices, 36);
}


free :: (mesh: *Mesh) {
    using context.game_context;
    glDeleteVertexArrays(1, *mesh.vao);
    glDeleteBuffers(1, *mesh.vbo);
}


make_cuboid_vertex_mesh :: (b: Vector3, e: Vector3, arena: *Memory_Arena) -> Mesh {
    using context.game_context;

    vertices := arena_alloc_array(arena, 36, Vector3);
    make_cuboid(vertices, b, e);

    vao, vbo: GLuint;
    
    glGenBuffers(1, *vbo);
    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glBufferData(GL_ARRAY_BUFFER, byte_count(vertices), vertices.data, GL_STATIC_DRAW); // Allocate the buffer

    glGenVertexArrays(1, *vao);
    glBindVertexArray(vao);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, size_of(Vector3), null);

    return .{vertices = vertices, vao = vao, vbo = vbo};
}


Block_Vertex :: struct {
    position: Vector3;
    viewed_offset: Vector3i;
    uv: Vector2;
}


make_block_mesh_data :: (size: Vector3i, filled: [] bool, vbo: GLuint, arena: *Memory_Arena) -> vertices: [] Vector3 {
    using context.game_context;
    
    // @Temporary @TODO: Make it so we can freely resize the topmost allocations of memory arenas!
    
    mark := get_mark(*frame_arena);
    defer restore_mark(*frame_arena, mark);

    vertices := arena_alloc_array(*frame_arena, 10000, Block_Vertex, zero_init=false);
    vertex_count := 0;

    for :iterate_vector3i size {
        if !filled[it_index] continue;
        
        origin := to_vector3(it);

        position: Vector3i;
        success: bool;
        index: s64;
        
        check_cube_face :: (position: Vector3i, face: Cube_Vertex) #expand {
            success, index = get_3d_index(position, size);
            if !success || !filled[index] {
                for 0..5 {
                    vertices[vertex_count] = .{
                       position = origin + cube_vertices[xx face + it],
                       viewed_offset = position,
                       uv = cube_uvs[xx face + it]
                    };
                    vertex_count += 1;
                }
            }
        }
        
        check_cube_face(.{it.x-1, it.y, it.z}, .X_NEGATIVE);
        check_cube_face(.{it.x+1, it.y, it.z}, .X_POSITIVE);
        check_cube_face(.{it.x, it.y-1, it.z}, .Y_NEGATIVE);
        check_cube_face(.{it.x, it.y+1, it.z}, .Y_POSITIVE);
        check_cube_face(.{it.x, it.y, it.z-1}, .Z_NEGATIVE);
        check_cube_face(.{it.x, it.y, it.z+1}, .Z_POSITIVE);
    }
    
    vertex_positions := arena_alloc_array(arena, vertex_count, Vector3);
    for 0..vertex_count-1 {
        vertex_positions[it] = vertices[it].position;
    }

    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glBufferData(GL_ARRAY_BUFFER, vertex_count * size_of(Block_Vertex), vertices.data, GL_STATIC_DRAW);

    return vertex_positions;
}


make_block_mesh :: (size: Vector3i, filled: [] bool, level_arena: *Memory_Arena) -> Mesh {      
    using context.game_context;

    vao, vbo: GLuint;
    glGenBuffers(1, *vbo);

    vertex_positions := make_block_mesh_data(size, filled, vbo, level_arena);

    // @Copypasta Figure out how to use metaprogramming to generate vaos for arbitrary vertex formats.

    glGenVertexArrays(1, *vao);
    glBindVertexArray(vao);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, size_of(Block_Vertex), null);
    glEnableVertexAttribArray(1);
    glVertexAttribIPointer(1, 3, GL_INT, size_of(Block_Vertex), *cast(*Block_Vertex, null).viewed_offset);
    glEnableVertexAttribArray(2);
    glVertexAttribPointer(2, 2, GL_FLOAT, GL_FALSE, size_of(Block_Vertex), *cast(*Block_Vertex, null).uv);

    return .{
        vertices = vertex_positions,
        vao = vao,
        vbo = vbo
    };
}


update_block_mesh :: (mesh: *Mesh, size: Vector3i, filled: [] bool, level_arena: *Memory_Arena) {
    mesh.vertices = make_block_mesh_data(size, filled, mesh.vbo, level_arena);
}


Collision_Texture :: struct {
    vbo: GLuint; // The backing store for the tbo
    tbo: GLuint; // "tbo" = texture buffer object
    size: Vector3i;
}


make_collision_texture :: (size: Vector3i) -> Collision_Texture {
    using context.game_context;
    
    vbo, tbo: GLuint;
    
    glGenBuffers(1, *vbo);
    glBindBuffer(GL_TEXTURE_BUFFER, vbo);
    glBufferData(GL_TEXTURE_BUFFER, size.x * size.y * size.z, null, GL_DYNAMIC_DRAW);

    glGenTextures(1, *tbo);
    glBindTexture(GL_TEXTURE_BUFFER, tbo);

    glTexBuffer(GL_TEXTURE_BUFFER, GL_R8UI, vbo);

    return .{vbo = vbo, tbo = tbo, size = size};
}


free :: (tex: *Collision_Texture) {
    using context.game_context;
    glDeleteBuffers(1, *tex.vbo);
    glDeleteTextures(1, *tex.tbo);
}


update_collision_texture :: (collision: *Collision) {
    using context.game_context;
    
    glBindBuffer(GL_TEXTURE_BUFFER, collision.texture.vbo);
    
    // Should we just resize it when the collision resizes?
    if collision.texture.size != collision.size {
        collision.texture.size = collision.size;
        glBufferData(GL_TEXTURE_BUFFER, collision.size.x * collision.size.y * collision.size.z, collision.viewed.data, GL_DYNAMIC_DRAW);
    } else {
        glBufferSubData(GL_TEXTURE_BUFFER, 0, collision.size.x * collision.size.y * collision.size.z, collision.viewed.data);
    }
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

    glDrawArrays(GL_TRIANGLES, 0, xx mesh.vertices.count);
}


draw_wireframe_mesh :: (mesh: *Mesh, projection: Matrix4, color: Vector4) {
    using context.game_context;

    glUseProgram(wireframe_shader);

    projection_loc := glGetUniformLocation(wireframe_shader, "projection");
    assert(projection_loc >= 0);
    glUniformMatrix4fv(projection_loc, 1, GL_TRUE, *projection._11);

    color_loc := glGetUniformLocation(wireframe_shader, "color");
    assert(color_loc >= 0);
    glUniform4f(color_loc, color.x, color.y, color.z, color.w);
    
    // @TODO: Make sure that we make a VAO where the vertex format matches the input mesh vertex format.
    // The only reason it works right now is because all the vertex formats have position as their first element.

    glBindVertexArray(mesh.vao);
    glBindBuffer(GL_ARRAY_BUFFER, mesh.vbo);
    
    glPolygonMode(GL_FRONT_AND_BACK, GL_LINE); // I don't think this will be set very often so we'll set then unset.
    glDrawArrays(GL_TRIANGLES, 0, xx mesh.vertices.count);
    glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
}


register_shader :: (name: string, text: string) -> GLuint {
    using context.game_context;

    LOG_SIZE :: 1024;

    vertex := glCreateShader(GL_VERTEX_SHADER);
    defer glDeleteShader(vertex);
    
    // You need the "#line 0" directive or else the NVIDIA shader compiler will report the line number including the
    // prefix lines in its compilation errors.

    VERTEX_PREFIX :: #string END
#version 330 core
#define VERTEX_SHADER
#define OUTIN out
#line 0
END
    vertex_lines := *u8.[
        VERTEX_PREFIX,
        text.data
    ];

    vertex_lengths :=  GLint.[
        xx VERTEX_PREFIX.count,
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

        print("Compilation error in vertex shader \"%\"\n%", name, str);
        return 0;
    }
    
    fragment := glCreateShader(GL_FRAGMENT_SHADER);
    defer glDeleteShader(fragment);
    
    FRAGMENT_PREFIX :: #string END
#version 330 core
#define OUTIN in
#line 0
END

    fragment_lines := *u8.[
        FRAGMENT_PREFIX,
        text.data
    ];

    fragment_lengths := GLint.[
        xx FRAGMENT_PREFIX.count,
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
        print("Compilation error in fragment shader \"%\"\n%", name, str);
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
        print("Linking error in shader \"%\"\n%", name, str);
        print(str);
        return 0;
    }

    return program;
}


set_uniform :: (name: *u8, val: $T) {
    using context.game_context;
    
    shader_GLint: GLint;
    glGetIntegerv(GL_CURRENT_PROGRAM, *shader_GLint);
    assert(shader_GLint >= 0);
    shader := cast(GLuint, shader_GLint);

    loc := glGetUniformLocation(shader, name);
    assert(loc >= 0);

    #if T == s32 {
        glUniform1i(loc, val);
    } else #if T == Vector3i {
        glUniform3i(loc, val.x, val.y, val.z);
    } else #if T == Vector4 {
        glUniform4f(loc, val.x, val.y, val.z, val.w);
    } else #if T == *Matrix4 {
        glUniformMatrix4fv(loc, 1, GL_TRUE, *val._11);
    } else #assert false;
}
