Mesh :: struct {
    vertex_positions: [] Vector3; // :CpuVertices
    vao: GLuint;
    vbo: GLuint;
    
    indices_exist: bool;
    index_ebo: GLuint;
    index_count: u32;
}


Cube_Face :: enum u8 {
    Z_NEGATIVE;
    X_POSITIVE;
    Y_POSITIVE;
    Y_NEGATIVE;
    X_NEGATIVE;
    Z_POSITIVE;
    COUNT;
}


Bitmap :: struct {
    // This only accounts for 2D textures right now.
    handle: GLuint;
}


Shader :: struct {
    program: GLuint;
}



// We need a way for shaders with different inputs to work on the same vertex format.
// My idea to handle this right now is to have a defined layout index for each kind of vertex input.
// When we set up the VAO and write the layouts in the shaders, we use these constants instead of 
// putting them in ascending order.

// That way, if a shaders needs, let's say, POSITION and FILLED_NORMAL, the shader will have locations
// 0 and 2 for those vertex attributes and and the VAO will have vertex attribute indices 0 and 2
// set up to mean position and filled_offset. As long as the vertex format has what the shader needs,
// the shader will be able to draw that vertex format.

// I don't know enough about rendering to know if this has @Speed considerations, and, quite frankly,
// this isn't something that is appropriate for me to be thinking about in this stage of the project.

//          -berk, 2025 - 2 - 9

// @Volatile :LayoutLocation
Layout_Location :: enum {
    POSITION;
    UV;
    COLOR;
    FILLED_POSITION;
    FILLED_NORMAL;
    OUTLINE_UV;
}

CUBE_VERTICES : [Cube_Face.COUNT][6] Vector3 : .[
    .[ 
        // Front face
        .{0, 0, 0},
        .{1, 0, 0},
        .{1, 1, 0},
        .{0, 0, 0},
        .{1, 1, 0},
        .{0, 1, 0},
    ],
    .[
        // Right face
        .{1, 0, 0},
        .{1, 0, 1},
        .{1, 1, 1},
        .{1, 0, 0},
        .{1, 1, 1},
        .{1, 1, 0},
    ],
    .[
        // Top face
        .{0, 1, 0},
        .{1, 1, 0},
        .{1, 1, 1},
        .{0, 1, 0},
        .{1, 1, 1},
        .{0, 1, 1},
    ],
    .[
        // Bottom face
        .{1, 0, 0},
        .{0, 0, 0},
        .{0, 0, 1},
        .{1, 0, 0},
        .{0, 0, 1},
        .{1, 0, 1},
    ],
    .[
        // Left face
        .{0, 0, 1},
        .{0, 0, 0},
        .{0, 1, 0},
        .{0, 0, 1},
        .{0, 1, 0},
        .{0, 1, 1},
    ],
    .[
        // Back face
        .{1, 0, 1},
        .{0, 0, 1},
        .{0, 1, 1},
        .{1, 0, 1},
        .{0, 1, 1},
        .{1, 1, 1},
    ],
];


CUBE_UVS : [Cube_Face.COUNT][6] Vector2 : .[
    .[
         // Front face
        .{0, 0},
        .{1, 0},
        .{1, 1},
        .{0, 0},
        .{1, 1},
        .{0, 1},
    ],
    .[
        // Right face
        .{0, 0},
        .{1, 0},
        .{1, 1},
        .{0, 0},
        .{1, 1},
        .{0, 1},
    ],
    .[
        // Top face
        .{0, 0},
        .{1, 0},
        .{1, 1},
        .{0, 0},
        .{1, 1},
        .{0, 1},
    ],
    .[
        // Bottom face
        .{0, 0},
        .{1, 0},
        .{1, 1},
        .{0, 0},
        .{1, 1},
        .{0, 1},
    ],
    .[ 
        // Left face
        .{0, 0},
        .{1, 0},
        .{1, 1},
        .{0, 0},
        .{1, 1},
        .{0, 1},
    ],
    .[
        // Back face
        .{0, 0},
        .{1, 0},
        .{1, 1},
        .{0, 0},
        .{1, 1},
        .{0, 1},
    ],
];


Imm_Vertex :: struct {
    position: Vector3;
    uv: Vector2;
    color: Vector4;
} #no_padding


Gridlike_Vertex :: struct {
    position: Vector3;
    uv: Vector2;
    filled_position: Vector3i; // Position of the grid cell the vertex belongs to in the "filled" array on the gridlike
    filled_normal: Vector3i;
    outline_uv: Vector2;
} #no_padding


// This is the vertex format for the blender exporter mesh
// file format. In the future, it might have certain sections
// that are optional depending on what the mesh uses.
My_Mesh_Vertex :: struct {
    position: Vector3;
    uv: Vector2;
} #no_padding


load_mesh :: (path: string, arena: *Memory_Arena) -> Mesh {
    using context.game_context;
    Mesh_Header :: struct {
        index_count: u32;
        vertex_count: u32;
    }

    scope_mark(frame_arena);

    success, str := read_file(path, frame_arena);
    assert(success);

    header:, str = get(str, Mesh_Header);
    
    index_chunk_size := header.index_count * size_of(u32);
    vertex_chunk_size := header.vertex_count * size_of(My_Mesh_Vertex);

    file_data_size := index_chunk_size + vertex_chunk_size;
    assert(xx str.count == file_data_size);

    index_chunk_ptr := str.data;
    vertex_chunk_ptr := index_chunk_ptr + index_chunk_size;


    vao, vbo, ebo: GLuint;
    glGenVertexArrays(1, *vao);
    glGenBuffers(1, *vbo);
    glGenBuffers(1, *ebo);

    glBindVertexArray(vao);
    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glBufferData(GL_ARRAY_BUFFER, vertex_chunk_size, vertex_chunk_ptr, GL_STATIC_DRAW);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, index_chunk_size, index_chunk_ptr, GL_STATIC_DRAW);

    using Layout_Location;
    glEnableVertexAttribArray(xx POSITION);
    glVertexAttribPointer(xx POSITION, 3, GL_FLOAT, GL_FALSE, size_of(My_Mesh_Vertex), null);
    glEnableVertexAttribArray(xx UV);
    glVertexAttribPointer(xx UV, 2, GL_FLOAT, GL_FALSE, size_of(My_Mesh_Vertex), *cast(*My_Mesh_Vertex, null).uv);
    
    // @TODO: Get mesh picking to work in a SANE WAY.
    vertex_positions := alloc_view(arena, header.index_count, Vector3);
    for * vertex_positions {
        it.* = cast(*My_Mesh_Vertex, vertex_chunk_ptr)[cast(*u32, index_chunk_ptr)[it_index]].position;
    }

    return .{
        vertex_positions = vertex_positions,
        vao = vao,
        vbo = vbo,
        indices_exist = true,
        index_ebo = ebo,
        index_count = header.index_count
    };
}


free :: (mesh: *Mesh) {
    using context.game_context;
    glDeleteVertexArrays(1, *mesh.vao);
    if mesh.indices_exist {
        buffers := GLuint.[mesh.vbo, mesh.index_ebo];
        glDeleteBuffers(2, buffers.data);
    } else {
        glDeleteBuffers(1, *mesh.vbo);
    }
}


make_cuboid_vertex_mesh :: (b: Vector3, e: Vector3, arena: *Memory_Arena) -> Mesh {
    using context.game_context;

    vertex_positions := alloc_view(arena, 36, Vector3);
    for face: CUBE_VERTICES {
        offset := it_index * face.count;
        for face {
            index := offset + it_index;
            vertex_positions[index] = it;
        }
    }

    vao, vbo: GLuint;
    
    glGenVertexArrays(1, *vao);
    glBindVertexArray(vao);

    glGenBuffers(1, *vbo);
    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glBufferData(GL_ARRAY_BUFFER, byte_count(vertex_positions), vertex_positions.data, GL_STATIC_DRAW); // Allocate the buffer
    
    using Layout_Location;
    glEnableVertexAttribArray(xx POSITION);
    glVertexAttribPointer(xx POSITION, 3, GL_FLOAT, GL_FALSE, size_of(Vector3), null);

    glEnableVertexAttribArray(xx UV);
    glVertexAttribPointer(xx UV, 2, GL_FLOAT, GL_FALSE, size_of(Gridlike_Vertex), *cast(*Gridlike_Vertex, null).uv);

    return .{vertex_positions = vertex_positions, vao = vao, vbo = vbo};
}


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
    
    scope_mark(frame_arena);

    vertices: [..] Gridlike_Vertex;

    for :iterate_vector3i size {
        if !filled[it_index] continue;

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

        // 2023 - 3 - 20 Addendum:
        // @Speed This is taking 8ms on the larger levels. Though this is related to surface area
        // rather than volume, and half of it comes from OpenGL allocating memory internally,
        // this is still worth keeping an eye on.


        using Gridlike_Edge;
        EDGES : [4][4] Gridlike_Edge : .[
            .[0,                    XP_YP | XN_YN,      XP_YP | XN_YP | XN_YN | XP_YN,      XP_YP | XN_YP | XN_YN],
            .[XP | YP,              0,                  XP_YP | XN_YP,                      XP_YP],
            .[XP | YP | XN,         XP,                 XP | XN_YP,                         XP | XN_YN], 
            .[XP | YP | XN | YN,    XP | XN,            XP | YP | XN_YN,                    XP | XN_YP | XN_YN],
        ];


        // Hopefully the optimizer takes the hint from all these constants.
        check :: ($face: Cube_Face) #expand {
            #if face == {
                case .X_POSITIVE;
                    NORMAL :: Vector3i.{1, 0, 0};
                    X_AXIS_INDEX :: 2;
                    X_AXIS :: 1;
                    Y_AXIS_INDEX :: 1;
                    Y_AXIS :: 1;
                case .X_NEGATIVE;
                    NORMAL :: Vector3i.{-1, 0, 0};
                    X_AXIS_INDEX :: 2;
                    X_AXIS :: -1;
                    Y_AXIS_INDEX :: 1;
                    Y_AXIS :: 1;
                case .Y_POSITIVE;
                    NORMAL :: Vector3i.{0, 1, 0};
                    X_AXIS_INDEX :: 0;
                    X_AXIS :: 1;
                    Y_AXIS_INDEX :: 2;
                    Y_AXIS :: 1;
                case .Y_NEGATIVE;
                    NORMAL :: Vector3i.{0, -1, 0};
                    X_AXIS_INDEX :: 0;
                    X_AXIS :: -1;
                    Y_AXIS_INDEX :: 2;
                    Y_AXIS :: 1;
                case .Z_POSITIVE;
                    NORMAL :: Vector3i.{0, 0, 1};
                    X_AXIS_INDEX :: 0;
                    X_AXIS :: -1;
                    Y_AXIS_INDEX :: 1;
                    Y_AXIS :: 1;
                case .Z_NEGATIVE;
                    NORMAL :: Vector3i.{0, 0, -1};
                    X_AXIS_INDEX :: 0;
                    X_AXIS :: 1;
                    Y_AXIS_INDEX :: 1;
                    Y_AXIS :: 1;
                case;
                    #assert false;
            }

            
            success, index := get_3d_index(it + NORMAL, size);
            if success && filled[index] return;

            occupied: Gridlike_Edge;

            check_edge :: ($x_offset: s32, $y_offset: s32, $edge: Gridlike_Edge) #expand {
                position := it;
                position.component[X_AXIS_INDEX] += x_offset * X_AXIS;
                position.component[Y_AXIS_INDEX] += y_offset * Y_AXIS;
                success, index := get_3d_index(position, size);
                if !success || !filled[index] {
                    occupied |= edge;
                } else {
                    position += NORMAL;
                    success, index := get_3d_index(position, size);
                    if success && filled[index] occupied |= edge;
                }
            }

            check_edge( 1,  0, XP);
            check_edge(-1,  0, XN);
            check_edge( 0,  1, YP);
            check_edge( 0, -1, YN);

            check_corner :: ($x_offset: s32, $y_offset: s32, $edges: Gridlike_Edge, $corner: Gridlike_Edge) #expand {
                if occupied & edges return;
                position := it;
                position.component[X_AXIS_INDEX] += x_offset * X_AXIS;
                position.component[Y_AXIS_INDEX] += y_offset * Y_AXIS;
                success, index := get_3d_index(position, size);
                if !success || !filled[index] {
                    occupied |= corner;
                } else {
                    position += NORMAL;
                    success, index := get_3d_index(position, size);
                    if success && filled[index] occupied |= corner;
                }
            }

            check_corner( 1,  1, XP | YP, XP_YP);
            check_corner(-1,  1, XN | YP, XN_YP);
            check_corner(-1, -1, XN | YN, XN_YN);
            check_corner( 1, -1, XP | YN, XP_YN);

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

            face_vertices: [] Vector3 = CUBE_VERTICES[face];
            face_uvs:      [] Vector2 = CUBE_UVS[face];

            for i: 0..5 {
                append(*vertices, frame_arena).* = .{
                    position = origin + face_vertices[i],
                    uv = face_uvs[i],
                    filled_position = it,
                    filled_normal = NORMAL,
                    outline_uv = outline_uvs[i]
                };
            }
        }


        check(.X_POSITIVE);
        check(.X_NEGATIVE);

        check(.Y_POSITIVE);
        check(.Y_NEGATIVE);

        check(.Z_POSITIVE);
        check(.Z_NEGATIVE);
    }

    vertex_positions := alloc_view(arena, vertices.count, Vector3);

    for * vertices {
        vertex_positions[it_index] = it.position;
    }

    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glBufferData(GL_ARRAY_BUFFER, vertices.count * size_of(Gridlike_Vertex), vertices.data, GL_STATIC_DRAW);


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
    glVertexAttribPointer(xx POSITION, 3, GL_FLOAT, GL_FALSE, size_of(Gridlike_Vertex), null);

    glEnableVertexAttribArray(xx UV);
    glVertexAttribPointer(xx UV, 2, GL_FLOAT, GL_FALSE, size_of(Gridlike_Vertex), *cast(*Gridlike_Vertex, null).uv);

    glEnableVertexAttribArray(xx FILLED_POSITION);
    glVertexAttribIPointer(xx FILLED_POSITION, 3, GL_INT, size_of(Gridlike_Vertex), *cast(*Gridlike_Vertex, null).filled_position);

    glEnableVertexAttribArray(xx FILLED_NORMAL);
    glVertexAttribIPointer(xx FILLED_NORMAL, 3, GL_INT, size_of(Gridlike_Vertex), *cast(*Gridlike_Vertex, null).filled_normal);

    glEnableVertexAttribArray(xx OUTLINE_UV);
    glVertexAttribPointer(xx OUTLINE_UV, 2, GL_FLOAT, GL_FALSE, size_of(Gridlike_Vertex), *cast(*Gridlike_Vertex, null).outline_uv);



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


free :: (tex: *View_Texture) {
    using context.game_context;
    glDeleteBuffers(1, *tex.vbo);
    glDeleteTextures(1, *tex.tbo);
}


make_view_mesh :: (position: Vector3i, size: Vector3i) {
    using context.game_context;

    scope_mark(frame_arena);
}


load_bitmap :: (file_name: string) -> Bitmap {
    using context.game_context;
    
    scope_mark(frame_arena);

    success, str := read_file(file_name, frame_arena);
    if !success {
        log(.ERROR, "Failed to load the file for bitmap \"%\"\n", file_name);
        assert(false);
    }
    
    w, h, channels: s32;
    data := stbi_load_from_memory(str.data, xx str.count, *w, *h, *channels, 0);
    defer stbi_image_free(data);
    
    internal_format: GLint;
    format: GLenum;

    if channels == 3 {
        internal_format = GL_RGB8;
        format = GL_RGB;
    } else if channels == 4 {
        internal_format = GL_RGBA8;
        format = GL_RGBA;
    } else {
        assert(false);
    }

    handle: GLuint;
    glGenTextures(1, *handle);
    glBindTexture(GL_TEXTURE_2D, handle);
    glTexImage2D(
        GL_TEXTURE_2D,
        0,
        internal_format,
        xx w,
        xx h,
        0,
        format,
        GL_UNSIGNED_BYTE,
        data
    );

    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST); 
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    
    return .{handle = handle};
}


free_bitmap :: (bitmap: *Bitmap) {
    using context.game_context;
    glDeleteTextures(1, *bitmap.handle);
}


load_shader :: (file_name: string) -> Shader {
    using context.game_context;
    
    scope_mark(frame_arena);

    success, str := read_file(file_name, frame_arena);
    if !success {
        log(.ERROR, "Failed to load the file for shader \"%\"\n", file_name);
        assert(false);
    }

    return load_shader(file_name, str);
}


load_shader :: (name: string, text: string) -> Shader {
    using context.game_context;

    LOG_SIZE :: 1024;
    

    // I started to do the complicated version of shader includes but then I realized it would probably
    // be best just to load everything from one file for now.

    /*
    scope_mark(frame_arena);
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
    // stuff that comes before.
    vertex_strings := string.[
        "#version 330 core\n",
        shader_include,
        "#define VERTEX_SHADER\n#define OUTIN out\n",
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

    return .{program = program};
}


Pipeline :: struct {
    flags: enum_flags u8 {
        BLEND;
        DEPTH_TEST;
        CULL_FACE;
        STENCIL_TEST;
    }
    mode: enum u8 { 
        TRIANGLE;
        LINE;
    }
    triangle_mode: enum u8 {    
        FILL;
        LINE;
    }
    depth_func: enum u8 {
        // These are the only two we use right now
        LESS;
        GREATER;
    }
}


set_shader :: (shader: *Shader, using pipeline := Pipeline.{flags = .DEPTH_TEST | .CULL_FACE}) {
    using context.game_context;

    current_shader = shader;
    current_pipeline = pipeline;

    glUseProgram(shader.program);

    if flags & .BLEND glEnable(GL_BLEND);
    else              glDisable(GL_BLEND);

    if flags & .DEPTH_TEST glEnable(GL_DEPTH_TEST);
    else                   glDisable(GL_DEPTH_TEST);

    if flags & .CULL_FACE glEnable(GL_CULL_FACE);
    else                  glDisable(GL_CULL_FACE);

    if flags & .STENCIL_TEST glEnable(GL_STENCIL_TEST);
    else                     glDisable(GL_STENCIL_TEST);
    
    if #complete mode == {
        case .TRIANGLE;
            if #complete triangle_mode == {
                case .FILL; glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
                case .LINE; glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);
            }
        case .LINE;
    }

    if #complete depth_func == {
        case .LESS;    glDepthFunc(GL_LESS);
        case .GREATER; glDepthFunc(GL_GREATER);
    }
}


set_uniform :: (name: *u8, val: $T) {
    using context.game_context;
    
    loc := glGetUniformLocation(current_shader.program, name);
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


set_uniform_bitmap :: (name: *u8, unit_index: int, bitmap: *Bitmap) {
    using context.game_context;
    glActiveTexture(GL_TEXTURE0 + cast(GLenum, unit_index));
    glBindTexture(GL_TEXTURE_2D, bitmap.handle);
    set_uniform(name, cast(s32, unit_index));
}


set_uniform_view_texture :: (name: *u8, unit_index: int, texture: *View_Texture) {
    using context.game_context;
    glActiveTexture(GL_TEXTURE0 + cast(GLenum, unit_index));
    glBindTexture(GL_TEXTURE_BUFFER, texture.tbo);
    set_uniform(name, cast(s32, unit_index));
}


bind_and_draw :: (mesh: *Mesh) {
    using context.game_context;
    glBindVertexArray(mesh.vao);

    mode: GLenum;
    if #complete current_pipeline.mode == {
        case .TRIANGLE; mode = GL_TRIANGLES;
        case .LINE;     mode = GL_LINES;
    }

    if mesh.indices_exist {
        glDrawElements(mode, mesh.index_count, GL_UNSIGNED_INT, null);
    } else {
        glDrawArrays(mode, 0, xx mesh.vertex_positions.count);
    }
}
