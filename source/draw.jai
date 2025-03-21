Mesh :: struct {
    vertex_positions: [] Vector3; // We store this information on the CPU so we can raycast against it.
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




// We need a way for shaders with different inputs to work on the same vertex format.
// My idea to handle this right now is to have a defined layout index for each kind of vertex input.
// When we set up the VAO and write the layouts in the shaders, we use these constants instead of 
// putting them in ascending order.

// That way, if a shaders needs, let's say, POSITION and VIEWED_OFFSET, the shader will have locations
// 0 and 2 for those vertex attributes and and the VAO will have vertex attribute indices 0 and 2
// set up to mean position and viewed_offset. As long as the vertex format has what the shader needs,
// the shader will be able to draw that vertex format.

// I don't know enough about rendering to know if this has @Speed considerations, and, quite frankly,
// this isn't something that is appropriate for me to be thinking about in this stage of the project.

//          -berk, 2025 - 2 - 9

// @Volatile :LayoutLocation
Layout_Location :: enum {
    POSITION;
    UV;
    VIEWED_OFFSET;
    COLOR;
    OUTLINE_UV;
}


CUBE_VERTICES : [Cube_Vertex.COUNT] Vector3 : .[
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


CUBE_UVS : [Cube_Vertex.COUNT] Vector2 : .[
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
        vertices[it] = begin + CUBE_VERTICES[it] * size;
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

    vertex_positions := alloc_view(arena, 36, Vector3);
    make_cuboid(vertex_positions, b, e);

    vao, vbo: GLuint;
    
    glGenVertexArrays(1, *vao);
    glBindVertexArray(vao);

    glGenBuffers(1, *vbo);
    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glBufferData(GL_ARRAY_BUFFER, byte_count(vertex_positions), vertex_positions.data, GL_STATIC_DRAW); // Allocate the buffer
    
    using Layout_Location;
    glEnableVertexAttribArray(xx POSITION);
    glVertexAttribPointer(xx POSITION, 3, GL_FLOAT, GL_FALSE, size_of(Vector3), null);

    return .{vertex_positions = vertex_positions, vao = vao, vbo = vbo};
}


Block_Vertex :: struct {
    position: Vector3;
    uv: Vector2;
    viewed_offset: Vector3i;
    outline_uv: Vector2;
}


/*
make_gridlike_mesh_data :: (size: Vector3i, filled: [] bool, vbo: GLuint, arena: *Memory_Arena) -> vertices: [] Vector3 {
    using context.game_context;
    
    mark := get_mark(*frame_arena);
    defer restore_mark(*frame_arena, mark);
    
    vertices: [..] Block_Vertex;

    for :iterate_vector3i size {
        if !filled[it_index] continue;
        
        origin := to_vector3(it);
        
        check_cube_face :: (position: Vector3i, face: Cube_Vertex) #expand {
            success, index := get_3d_index(position, size);
            if !success || !filled[index] {
                for 0..5 {
                    append(*vertices, *frame_arena).* = .{
                       position = origin + CUBE_VERTICES[xx face + it],
                       uv = CUBE_UVS[xx face + it],
                       viewed_offset = position,
                    };
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
    
    vertex_positions := alloc_view(arena, vertices.count, Vector3);

    for * vertices {
        vertex_positions[it_index] = it.position;
    }

    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glBufferData(GL_ARRAY_BUFFER, vertices.count * size_of(Block_Vertex), vertices.data, GL_STATIC_DRAW);


    return vertex_positions;
}
*/


// @CompilerBug doing "enum_flags u8" doesn't actually make it a u8
// when we put it inside of this function.
Gridlike_Edge :: enum_flags u8 {
    XP    ; // :: 1 << 0;
    XP_YP ; // :: 1 << 1;
    YP    ; // :: 1 << 2;
    XN_YP ; // :: 1 << 3;
    XN    ; // :: 1 << 4;
    XN_YN ; // :: 1 << 5;
    YN    ; // :: 1 << 6;
    XP_YN ; // :: 1 << 7;
}


make_gridlike_mesh_data :: (size: Vector3i, filled: [] bool, vbo: GLuint, arena: *Memory_Arena) -> vertices: [] Vector3 {
    using context.game_context;

    mark := get_mark(*frame_arena);
    defer restore_mark(*frame_arena, mark);

    vertices: [..] Block_Vertex;

    for :iterate_vector3i size {
        // This algorithm is a little wacky so I will do my best to explain it here.
        // We want to find the UV coordinates of the part of the texture that corresponds
        // to the combination of edges that this quad has.

        // We represent which sides of the texture have edges on them via the Gridlike_Edge bitflags.
        // We also store which part of the texture corresponds to which combination of 
        // bitflags in the EDGES array.

        // We then just iterate through the array to find the part of the texture that
        // corresponds to our combination of bitflags. We have to do it four times, and rotate
        // the flags each time, which corresponds to the four possible orientations of each
        // square. @Speed many of these are redundant, we could do manual checks instead.

        // We also have to make sure to rotate the coordinates (which is what the PX_N constants
        // are for. They store the value of the uv for each of the four rotations).

        // Then, we just generate the vertex information and append that to the vertices.

        //          -berk, 2025 - 3 - 19



        // @Speed there are probably many ways this algorithm could be sped up tremendously
        // if that becomes a problem.
        
        using Gridlike_Edge;
        EDGES : [4][4] Gridlike_Edge : .[
            .[0,                    0,              XP_YP | XN_YP | XN_YN | XP_YN,      XP_YP | XN_YP | XN_YN],
            .[XP | YP,              0,              XP_YP | XN_YP,                      XP_YP],
            .[XP | YP | XN,         XP,             XP | XN_YP,                         XP | XN_YN], 
            .[XP | YP | XN | YN,    XP | XN,        XP | YP | XN_YN,                    XP | XN_YP | XN_YN],
        ];


        if !filled[it_index] continue;

        success: bool;
        index: int;

        success, index = get_3d_index(.{it.x, it.y + 1, it.z}, size);
        if success && filled[index] continue;

        occupied: Gridlike_Edge;

        success, index = get_3d_index(.{it.x + 1, it.y, it.z}, size);
        if !success || !filled[index] occupied |= XP;

        success, index = get_3d_index(.{it.x - 1, it.y, it.z}, size);
        if !success || !filled[index] occupied |= XN;

        success, index = get_3d_index(.{it.x, it.y, it.z + 1}, size);
        if !success || !filled[index] occupied |= YP;

        success, index = get_3d_index(.{it.x, it.y, it.z - 1}, size);
        if !success || !filled[index] occupied |= YN;

        if (occupied & (XP | YP)) == 0 {
            success, index := get_3d_index(.{it.x + 1, it.y, it.z + 1}, size);
            if !success || !filled[index] occupied |= XP_YP;
        }

        if (occupied & (XN | YP)) == 0 {
            success, index := get_3d_index(.{it.x - 1, it.y, it.z + 1}, size);
            if !success || !filled[index] occupied |= XN_YP;
        }

        if (occupied & (XN | YN)) == 0 {
            success, index := get_3d_index(.{it.x - 1, it.y, it.z - 1}, size);
            if !success || !filled[index] occupied |= XN_YN;
        }

        if (occupied & (XP | YN)) == 0 {
            success, index := get_3d_index(.{it.x + 1, it.y, it.z - 1}, size);
             if !success || !filled[index] occupied |= XP_YN;
        }

        E :: 0.0001;
        // this epsilon value is to correct for when the uvs get rounded
        // incorrectly due to vertex varying interpolation. Because we're
        // doing nearest-neighbor interpolation for the bitmap, this might
        // cause the pixel value from an adjacent part of the bitmap to be
        // read instead. We shrink the coordinates ever so slightly by
        // epsilon to prevent this from happening.

        // Zero and one
        O :: E;
        I :: 1 - E;


        P0_X :: float.[O, I, I, O];
        P0_Y :: float.[O, O, I, I];

        P1_X :: float.[I, I, O, O];
        P1_Y :: float.[O, I, I, O];

        P2_X :: float.[I, O, O, I];
        P2_Y :: float.[I, I, O, O];

        P3_X :: float.[O, O, I, I];
        P3_Y :: float.[I, O, O, I];


        found := false;
        p0_x, p0_y, p1_x, p1_y, p2_x, p2_y, p3_x, p3_y: float;

        occupied_rotated := occupied;
        
        for rotation: 0..3 {
            for y_row, y: EDGES {
                for val, x: y_row {
                    if val == occupied_rotated {
                        found = true;

                        p0_x = (x + P0_X[rotation]) / cast(float, y_row.count);
                        p0_y = (y + P0_Y[rotation]) / cast(float, EDGES.count);

                        p1_x = (x + P1_X[rotation]) / cast(float, y_row.count);
                        p1_y = (y + P1_Y[rotation]) / cast(float, EDGES.count);

                        p2_x = (x + P2_X[rotation]) / cast(float, y_row.count);
                        p2_y = (y + P2_Y[rotation]) / cast(float, EDGES.count);

                        p3_x = (x + P3_X[rotation]) / cast(float, y_row.count);
                        p3_y = (y + P3_Y[rotation]) / cast(float, EDGES.count);

                        break rotation;
                    }
                }
            }

            last_two := occupied_rotated >> 6;
            occupied_rotated <<= 2;
            occupied_rotated |= last_two;
        }
        assert(found);

        origin := to_vector3(it);
        outline_uvs := Vector2.[
            .{p0_x, p0_y},
            .{p1_x, p1_y},
            .{p2_x, p2_y},
            .{p0_x, p0_y},
            .{p2_x, p2_y},
            .{p3_x, p3_y}
        ];

        for i: 0..5 {
            index := xx Cube_Vertex.Y_POSITIVE + i;
            append(*vertices, *frame_arena).* = .{
                position = origin + CUBE_VERTICES[index],
                uv = CUBE_UVS[index],
                viewed_offset = .{it.x, it.y + 1, it.z},
                outline_uv = outline_uvs[i]
            };
        }
    }

    vertex_positions := alloc_view(arena, vertices.count, Vector3);

    for * vertices {
        vertex_positions[it_index] = it.position;
    }

    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glBufferData(GL_ARRAY_BUFFER, vertices.count * size_of(Block_Vertex), vertices.data, GL_STATIC_DRAW);


    return vertex_positions;
}


make_gridlike_mesh :: (size: Vector3i, filled: [] bool, level_arena: *Memory_Arena) -> Mesh {      
    using context.game_context;

    vao, vbo: GLuint;

    glGenVertexArrays(1, *vao);
    glGenBuffers(1, *vbo);

    glBindVertexArray(vao);
    glBindBuffer(GL_ARRAY_BUFFER, vbo);

    using Layout_Location;

    glEnableVertexAttribArray(xx POSITION);
    glVertexAttribPointer(xx POSITION, 3, GL_FLOAT, GL_FALSE, size_of(Block_Vertex), null);

    glEnableVertexAttribArray(xx UV);
    glVertexAttribPointer(xx UV, 2, GL_FLOAT, GL_FALSE, size_of(Block_Vertex), *cast(*Block_Vertex, null).uv);

    glEnableVertexAttribArray(xx VIEWED_OFFSET);
    glVertexAttribIPointer(xx VIEWED_OFFSET, 3, GL_INT, size_of(Block_Vertex), *cast(*Block_Vertex, null).viewed_offset);

    glEnableVertexAttribArray(xx OUTLINE_UV);
    glVertexAttribPointer(xx OUTLINE_UV, 2, GL_FLOAT, GL_FALSE, size_of(Block_Vertex), *cast(*Block_Vertex, null).outline_uv);



    vertex_positions := make_gridlike_mesh_data(size, filled, vbo, level_arena);

    // @TODO Store vertex buffers in SOA form!
    return .{
        vertex_positions = vertex_positions,
        vao = vao,
        vbo = vbo
    };
}


update_gridlike_mesh :: (e: *$T, arena: *Memory_Arena) {
    e.mesh.vertex_positions = make_gridlike_mesh_data(e.size, e.filled, e.mesh.vbo, arena);
}


View_Texture :: struct {
    vbo: GLuint; // The backing store for the tbo
    tbo: GLuint; // "tbo" = texture buffer object
    size: Vector3i;
}


make_view_texture :: (size: Vector3i) -> View_Texture {
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


free :: (tex: *View_Texture) {
    using context.game_context;
    glDeleteBuffers(1, *tex.vbo);
    glDeleteTextures(1, *tex.tbo);
}


update_view_texture :: (tex: *View_Texture, size: Vector3i, data: [] View_State) {
    using context.game_context;
    
    glBindBuffer(GL_TEXTURE_BUFFER, tex.vbo);
    
    if tex.size != size {
        tex.size = size;
        glBufferData(GL_TEXTURE_BUFFER, byte_count(data), data.data, GL_DYNAMIC_DRAW);
    } else {
        glBufferSubData(GL_TEXTURE_BUFFER, 0, byte_count(data), data.data);
    }
    
    // @Investigate

    // For some reason, RenderDoc believes that the vbo gets set to zero size when I call
    // glBufferSubData. It's like it's "forgetting" where the buffer is located. This causes
    // none of the level geometry to render when I inspect it in RenderDoc (but it shows up
    // in the game). If I re-bind the texture buffer it works again for some reason.
    
    // I don't know if this is because RenderDoc is bugged or because I'm subtly using OpenGL
    // incorrectly and it's not telling me why.

    glBindTexture(GL_TEXTURE_BUFFER, tex.tbo);
    glTexBuffer(GL_TEXTURE_BUFFER, GL_R8UI, tex.vbo);
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
    glDrawArrays(GL_TRIANGLES, 0, xx mesh.vertex_positions.count);
    glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
}


load_bitmap :: (file_name: string) -> GLuint {
    using context.game_context;

    mark := get_mark(*frame_arena);
    defer restore_mark(*frame_arena, mark);

    success, str := read_file(file_name, *frame_arena);
    if !success {
        log(.ERROR, "Failed to load the file for bitmap \"%\"\n", file_name);
        assert(false);
    }
    
    w, h, channels: s32;
    data := stbi_load_from_memory(str.data, xx str.count, *w, *h, *channels, 0);
    defer stbi_image_free(data);
    assert(channels == 4);

    bitmap: GLuint;
    glGenTextures(1, *bitmap);
    glBindTexture(GL_TEXTURE_2D, bitmap);
    glTexImage2D(
        GL_TEXTURE_2D,
        0,
        GL_RGBA8,
        xx w,
        xx h,
        0,
        GL_RGBA,
        GL_UNSIGNED_BYTE,
        data
    );

    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST); 
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

    return bitmap;
}


load_shader :: (file_name: string, prefix := "") -> GLuint {
    using context.game_context;
    
    mark := get_mark(*frame_arena);
    defer restore_mark(*frame_arena, mark);

    success, str := read_file(file_name, *frame_arena);
    if !success {
        log(.ERROR, "Failed to load the file for shader \"%\"\n", file_name);
        assert(false);
    }

    return load_shader(file_name, str, prefix);
}


load_shader :: (name: string, text: string, prefix: string) -> GLuint {
    using context.game_context;

    LOG_SIZE :: 1024;
    

    // I started to do the complicated version of shader includes but then I realized it would probably
    // be best just to load everything from one file for now.

    /*
    mark := get_mark(*frame_arena);
    defer restore_mark(*frame_arena, mark);
    include_paths: [..] string;
    
    shader_text := text;
    // Parse include strings
    if begins_with(text, "include") {
        include := advance(text, "include".count);
        index := 0;
        while include_parse := index < include.count {
            if include[index] == #char " " continue;
            if include[index] == #char "\n" break;
            
            start := index;

            while true {
                index += 1;

                if index >= include.count {
                    assert(false);
                    // There should be more than just an include line in a shader!
                }

                if index[include] == #char "\n" {
                    length := index - start;
                    append(*include_paths, .{length, include.data + start}, *frame_arena);
                    break include_parse;
                }

                if include[index] == #char " " {
                    length := index - start;
                    append(*include_paths, .{length, include.data + start}, *frame_arena);
                    break;
                }
            }
        }

        index += 1; // Advance past the newline
        shader_text = advance(include, index);
    }
    
    // @TODO @Speed: Cache the shader include text!
    includes := alloc_view(*frame_arena, string, include_paths.count);
    for include_paths {
        success, str := read_file(it, *frame_arena);
        assert(success);
        includes[it_index] = str;
    }
    */



    make_string_arrays :: (strings: [$N] string) -> [N] *u8, [N] GLint #expand {
        lines: [N] *u8;
        lengths: [N] GLint;

        for strings {
            lines[it_index] = it.data;
            lengths[it_index] = xx it.count;
        }

        return lines, lengths;
    }

    vertex := glCreateShader(GL_VERTEX_SHADER);
    defer glDeleteShader(vertex);

    // You need the "#line 1" directive or else the NVIDIA shader compiler will report the line number including the
    // prefix lines in its compilation errors.
    vertex_strings := string.[
        "#version 330 core\n",
        shader_include,
        "#define VERTEX_SHADER\n#define OUTIN out\n",
        prefix,
        "#line 1\n",
        text
    ];
    vertex_lines, vertex_lengths := make_string_arrays(vertex_strings);

    glShaderSource(vertex, xx vertex_lines.count, vertex_lines.data, vertex_lengths.data);
    glCompileShader(vertex);
    
    vertex_success: GLint;
    glGetShaderiv(vertex, GL_COMPILE_STATUS, *vertex_success);
    if !vertex_success {
        count: GLsizei;
        buffer: [LOG_SIZE] u8 = ---;
        glGetShaderInfoLog(vertex, LOG_SIZE, *count, *buffer[0]);

        str := string.{data=*buffer[0], count=count};

        log(.ERROR, "Compilation error in vertex shader \"%\"\n%", name, str);
        assert(false);
    }
    
    fragment := glCreateShader(GL_FRAGMENT_SHADER);
    defer glDeleteShader(fragment);
    
    fragment_strings := string.[
        "#version 330 core\n",
        shader_include,
        "#define OUTIN in\n",
        prefix,
        "#line 1\n",
        text
    ];
    fragment_lines, fragment_lengths := make_string_arrays(fragment_strings);

    glShaderSource(fragment, xx fragment_lines.count, fragment_lines.data, fragment_lengths.data);
    glCompileShader(fragment);

    fragment_success: GLint;
    glGetShaderiv(fragment, GL_COMPILE_STATUS, *fragment_success);
    if !fragment_success {
        count: GLsizei;
        buffer: [LOG_SIZE] u8 = ---;
        glGetShaderInfoLog(fragment, LOG_SIZE, *count, *buffer[0]);

        str := string.{data=*buffer[0], count=count};
        log(.ERROR, "Compilation error in fragment shader \"%\"\n%", name, str);
        assert(false);
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
        log(.ERROR, "Linking error in shader \"%\"\n%", name, str);
        assert(false);
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
    } else #if T == float {
        glUniform1f(loc, val);
    } else #if T == Vector3i {
        glUniform3i(loc, val.x, val.y, val.z);
    } else #if T == Vector3 {
        glUniform3f(loc, val.x, val.y, val.z);
    } else #if T == Vector4 {
        glUniform4f(loc, val.x, val.y, val.z, val.w);
    } else #if T == Matrix4 {
        glUniformMatrix4fv(loc, 1, GL_TRUE, *val._11);
    } else #assert false;
}


set_uniform_bitmap :: (name: *u8, unit_index: int, bitmap: GLuint, type: GLenum = GL_TEXTURE_2D) {
    using context.game_context;
    glActiveTexture(GL_TEXTURE0 + cast(GLenum, unit_index));
    glBindTexture(type, bitmap);
    set_uniform(name, cast(s32, unit_index));
}


bind_and_draw :: (mesh: *Mesh) {
    using context.game_context;
    glBindVertexArray(mesh.vao);
    glDrawArrays(GL_TRIANGLES, 0, xx mesh.vertex_positions.count);
}
