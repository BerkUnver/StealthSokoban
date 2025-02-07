Mesh :: struct {
    vertices: [] Vector3; // We store this information on the CPU so we can raycast against it.
    vao: GLuint;
    vbo: GLuint;
}


make_cuboid_macro :: (b: Vector3, e: Vector3, vertices: [] Vector3, uvs: [] Vector2, has_uvs: bool) #expand {
    index := 0;
    vertex :: (v: Vector3, uv: Vector2) #expand {
         vertices[index] = v;
         #if has_uvs uvs[index] = uv;
         index += 1;
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
}


make_cuboid :: (vertices: [] Vector3, uvs: [] Vector2, begin: Vector3, end: Vector3) -> vertices: [] Vector3, uvs: [] Vector2 {
    make_cuboid_macro(begin, end, vertices, uvs, has_uvs=true);
    return slice(vertices, 36), slice(uvs, 36);
}


make_cuboid :: (vertices: [] Vector3, begin: Vector3, end: Vector3) -> [] Vector3 { 
    make_cuboid_macro(begin, end, vertices, .{}, has_uvs=false);
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
    uv: Vector2;
}


make_block_mesh_data :: (size: Vector3i, filled: [] bool, vbo: GLuint, arena: *Memory_Arena) -> vertices: [] Vector3 {
    using context.game_context;

    // @TODO @Speed @Memory: Optimize how many vertices this is to be only the faces of the cubes on the surface.
    // @TODO @Speed: Add reallocing from the top of the temporary buffer

    filled_count := 0;
    for :iterate_vector3i size {
        if filled[it_index] filled_count += 1;
    }

    vertices := arena_alloc_array(arena, 36 * filled_count, Vector3);

    mark := get_mark(*frame_arena);
    defer restore_mark(*frame_arena, mark);

    uvs := arena_alloc_array(*frame_arena, 36 * filled_count, Vector2);
    i_vertices := vertices;
    i_uvs := uvs;

    for :iterate_vector3i size {
        if filled[it_index] i_vertices, i_uvs = make_cuboid(i_vertices, i_uvs, to_vector3(it), to_vector3(it + Vector3i.{1, 1, 1}));
    }

    // @Temporary? Figure out if we want to store vertices in AOS or SOA form.
    buf := arena_alloc_array(*frame_arena, size_of(Block_Vertex) * uvs.count, u8);

    for 0..uvs.count-1 {
        cast(*Vector3, *buf[it * size_of(Block_Vertex)]).* = vertices[it];
        cast(*Vector2, *buf[it * size_of(Block_Vertex) + xx *cast(*Block_Vertex, null).uv]).* = uvs[it];
    }

    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glBufferData(GL_ARRAY_BUFFER, buf.count, buf.data, GL_STATIC_DRAW);

    return vertices;
}


make_block_mesh :: (size: Vector3i, filled: [] bool, level_arena: *Memory_Arena) -> Mesh {      
    using context.game_context;

    vao, vbo: GLuint;
    glGenBuffers(1, *vbo);

    vertices := make_block_mesh_data(size, filled, vbo, level_arena);

    // @Copypasta Figure out how to use metaprogramming to generate vaos for arbitrary vertex formats.

    glGenVertexArrays(1, *vao);
    glBindVertexArray(vao);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, size_of(Block_Vertex), null);
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, size_of(Block_Vertex), *cast(*Block_Vertex, null).uv);

    return .{
        vertices = vertices,
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


set_uniform :: (name: *u8, val: $T) {
    using context.game_context;
    
    shader_GLint: GLint;
    glGetIntegerv(GL_CURRENT_PROGRAM, *shader_GLint);
    assert(shader_GLint >= 0);
    shader := cast(GLuint, shader_GLint);

    loc := glGetUniformLocation(shader, name);
    assert(loc >= 0);
    #if T == *Matrix4 {
        glUniformMatrix4fv(loc, 1, GL_TRUE, *val._11);
    } else #if T == s32 {
        glUniform1i(loc, val);
    } else #if T == Vector3i {
        glUniform3i(loc, val.x, val.y, val.z);
    } else #assert false;
}
