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
    submitting_vertices: bool;
}

imm_init :: (using g: *Game) {
    using g.imm_state;


    glGenBuffers(1, *vbo);
    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
    glBufferData(GL_ARRAY_BUFFER, size_of(Vertex) * vertices.count, null, GL_STREAM_DRAW); // Allocate the buffer
    glGenVertexArrays(1, *vao);


    // The vao (vertex attribute object) just is a data structure that stores how the vertex information is structured.
    // We specifiy this by calling glBindVertexArray(vao), then calling glVertexAttribPointer to describe how an
    // attribute is stored before finally calling glEnableVertexAttribArray to use that attribute.

    glBindVertexArray(vao);
    
    // Consider getting this information from the Vertex struct with metaprogramming.
    POSITION_UNIFORM_LOC :: 0;
    glVertexAttribPointer(POSITION_UNIFORM_LOC, 3, GL_FLOAT, GL_FALSE, size_of(Vertex), *cast(*Vertex, null).position);
    glEnableVertexAttribArray(POSITION_UNIFORM_LOC); 

    COLOR_UNIFORM_LOC :: 1;
    glVertexAttribPointer(COLOR_UNIFORM_LOC, 4, GL_FLOAT, GL_FALSE, size_of(Vertex), *cast(*Vertex, null).color);
    glEnableVertexAttribArray(COLOR_UNIFORM_LOC);

    UV_UNIFORM_LOC :: 2;
    glVertexAttribPointer(UV_UNIFORM_LOC, 2, GL_FLOAT, GL_FALSE, size_of(Vertex), *cast(*Vertex, null).uv);
    glEnableVertexAttribArray(UV_UNIFORM_LOC);
    
    
    //
    // Initialize shaders
    //

    register_shader :: (using procs: GL_Procedures, type: GLenum, text: string) -> GLuint {
        shader := glCreateShader(type);
        text_count := cast(GLint)text.count;
        glShaderSource(shader, 1, *text.data, *text_count);
        glCompileShader(shader);

        success: GLint;
        glGetShaderiv(shader, GL_COMPILE_STATUS, *success);
        if !success {
            count: GLsizei;
            buffer: [1024] u8 = ---;
            glGetShaderInfoLog(shader, 1024, *count, *buffer[0]);

            str := string.{data=*buffer[0], count=count};
            print(str);

        }
        return shader;
    }

    vertex   := register_shader(g.gl_procs, GL_VERTEX_SHADER,   VERTEX_SOURCE);
    fragment := register_shader(g.gl_procs, GL_FRAGMENT_SHADER, FRAGMENT_SOURCE);
    assert(vertex != 0);
    assert(fragment != 0);

    program := glCreateProgram();
    glAttachShader(program, vertex);
    glAttachShader(program, fragment);
    glLinkProgram(program);

    success: GLint;
    glGetProgramiv(program, GL_LINK_STATUS, *success);
    assert(success != 0);

    glDeleteShader(fragment);
    glDeleteShader(vertex);
    glUseProgram(program);
    
    
    FOV :: PI / 3;
    NEAR :: 0.1;

    right := cast(float, NEAR * tan(FOV / 2));
    top := right * cast(float, INNER_WINDOW_H) / cast(float, INNER_WINDOW_W);
    

    camera_projection := frustum(-right, -top, NEAR, right, top, 1000);
    rotate_camera_down := matrix4_rotate_x(cast(float, PI/3));
    world_to_camera := matrix4_translate(0, -8, 4);

    matrix := matmul(camera_projection, matmul(rotate_camera_down, world_to_camera));
    
    projection_loc := glGetUniformLocation(program, "projection");
    glUniformMatrix4fv(projection_loc, 1, GL_TRUE, *matrix.x_x);

    // @TODO: Get actual bitmap loading to work, this is just temporary for testing.
    f := cast(u8, 255);
    bitmap_data := u8.[ 
        0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 
        0,0,0, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, 0,0,0,
        0,0,0, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, 0,0,0,
        0,0,0, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, 0,0,0,
        0,0,0, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, 0,0,0,
        0,0,0, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, 0,0,0,
        0,0,0, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, 0,0,0,
        0,0,0, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, 0,0,0,
        0,0,0, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, 0,0,0,
        0,0,0, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, 0,0,0,
        0,0,0, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, 0,0,0,
        0,0,0, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, 0,0,0,
        0,0,0, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, 0,0,0,
        0,0,0, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, 0,0,0,
        0,0,0, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, f,f,f, 0,0,0,
        0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0
    ];
    
    bitmap: GLuint;
    glGenTextures(1, *bitmap);
    assert(bitmap != 0);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, bitmap);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, 16, 16, 0, GL_RGB, GL_UNSIGNED_BYTE, *bitmap_data[0]);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    
    bitmap_loc := glGetUniformLocation(program, "bitmap");
    glUniform1i(bitmap_loc, 0);
}

imm_begin :: (g: *Game) {
    using g.imm_state;
    assert(!submitting_vertices);
    submitting_vertices = true;
}

imm_end :: (g: *Game) {
    using g.imm_state;
    assert(submitting_vertices);
    upload_vertices_to_gpu(g);
    submitting_vertices = false;    
}

imm_vertex :: (g: *Game, position: Vector3, color: Vector4, uv: Vector2) {
    using g.imm_state;
    assert(submitting_vertices);
    if vertex_count == vertices.count upload_vertices_to_gpu(g);
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
        upload_vertices_to_gpu();
        vertex_count = 1;
        return *vertices[0];
    }
    
    v := *vertices[vertex_count];
    vertex_count += 1;
    return v;
}
*/

imm_cuboid :: (g: *Game, b: Vector3, e: Vector3) {
    // b: beginning, the bottom corner of the cuboid
    // e: end, the top corner of the cuboid

    // Front face
    imm_vertex(g, .{b.x, b.y, b.z}, .{1, 0, 0, 1}, .{0, 0});
    imm_vertex(g, .{e.x, b.y, b.z}, .{0, 1, 0, 1}, .{1, 0});
    imm_vertex(g, .{e.x, e.y, b.z}, .{0, 0, 1, 1}, .{1, 1});
    imm_vertex(g, .{b.x, b.y, b.z}, .{1, 0, 0, 1}, .{0, 0});
    imm_vertex(g, .{e.x, e.y, b.z}, .{0, 0, 1, 1}, .{1, 1});
    imm_vertex(g, .{b.x, e.y, b.z}, .{0, 1, 0, 1}, .{0, 1});
    
    // Right face
    imm_vertex(g, .{e.x, b.y, b.z}, .{1, 0, 0, 1}, .{0, 0});
    imm_vertex(g, .{e.x, b.y, e.z}, .{0, 1, 0, 1}, .{1, 0});
    imm_vertex(g, .{e.x, e.y, e.z}, .{0, 0, 1, 1}, .{1, 1});
    imm_vertex(g, .{e.x, b.y, b.z}, .{1, 0, 0, 1}, .{0, 0});
    imm_vertex(g, .{e.x, e.y, e.z}, .{0, 0, 1, 1}, .{1, 1});
    imm_vertex(g, .{e.x, e.y, b.z}, .{0, 1, 0, 1}, .{0, 1});
    
    // Top face
    imm_vertex(g, .{b.x, e.y, b.z}, .{1, 0, 0, 1}, .{0, 0});
    imm_vertex(g, .{e.x, e.y, b.z}, .{0, 1, 0, 1}, .{1, 0});
    imm_vertex(g, .{e.x, e.y, e.z}, .{0, 0, 1, 1}, .{1, 1});
    imm_vertex(g, .{b.x, e.y, b.z}, .{1, 0, 0, 1}, .{0, 0});
    imm_vertex(g, .{e.x, e.y, e.z}, .{0, 0, 1, 1}, .{1, 1});
    imm_vertex(g, .{b.x, e.y, e.z}, .{0, 1, 0, 1}, .{0, 1});
    
    // Bottom face
    imm_vertex(g, .{e.x, b.y, b.z}, .{1, 0, 0, 1}, .{0, 0});
    imm_vertex(g, .{b.x, b.y, b.z}, .{0, 1, 0, 1}, .{1, 0});
    imm_vertex(g, .{b.x, b.y, e.z}, .{0, 0, 1, 1}, .{1, 1});
    imm_vertex(g, .{e.x, b.y, b.z}, .{1, 0, 0, 1}, .{0, 0});
    imm_vertex(g, .{b.x, b.y, e.z}, .{0, 0, 1, 1}, .{1, 1});
    imm_vertex(g, .{e.x, b.y, e.z}, .{0, 1, 0, 1}, .{0, 1});

    // Left face
    imm_vertex(g, .{b.x, b.y, e.z}, .{1, 0, 0, 1}, .{0, 0});
    imm_vertex(g, .{b.x, b.y, b.z}, .{0, 1, 0, 1}, .{1, 0});
    imm_vertex(g, .{b.x, e.y, b.z}, .{0, 0, 1, 1}, .{1, 1});
    imm_vertex(g, .{b.x, b.y, e.z}, .{1, 0, 0, 1}, .{0, 0});
    imm_vertex(g, .{b.x, e.y, b.z}, .{0, 0, 1, 1}, .{1, 1});
    imm_vertex(g, .{b.x, e.y, e.z}, .{0, 1, 0, 1}, .{0, 1});

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
imm_cube_map :: (g: *Game, cubes: [] bool, x_count: u64, y_count: u64, corner: Vector3) {
    assert(cubes.count == cast(s64, x_count * y_count));

    x_begin_map := corner.x - 0.5;
    
    y_begin := corner.y - 0.5;
    y_end := corner.y + 0.5;

    z_begin_map := corner.z - 0.5;
    

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
            imm_cuboid(g, .{x_begin, y_begin, z_begin}, .{x_end, y_end, z_end});
        }
    }
}


#scope_file
upload_vertices_to_gpu :: (using g: *Game) {
    using g.imm_state;
    glBufferSubData(GL_ARRAY_BUFFER, 0, size_of(Vertex) * vertex_count, vertices.data);
    glDrawArrays(GL_TRIANGLES, 0, vertex_count);
    vertex_count = 0;
}

VERTEX_SOURCE :: #string END
#version 330 core
layout(location=0) in vec3 vertex_position;
layout(location=1) in vec4 vertex_color;
layout(location=2) in vec2 vertex_uv;

uniform mat4 projection;
uniform sampler2D bitmap;

out vec4 fragment_color;
out vec2 fragment_uv;

void main() {
    gl_Position = projection * vec4(vertex_position, 1.0);
    fragment_color = vertex_color;
    fragment_uv = vertex_uv;
}
END


FRAGMENT_SOURCE :: #string END
#version 330 core
in vec4 fragment_color;
in vec2 fragment_uv;

uniform mat4 projection;
uniform sampler2D bitmap;

layout(location=0) out vec4 color;

void main() {
    color = fragment_color * texture(bitmap, fragment_uv);
}
END


// @TODO: Experiment with combining vertex and fragment shaders with #ifdefs.
/*
#version 330 core
#ifdef VERTEX_SHADER
layout(location=0) in vec3 vertex_position;
layout(location=1) in vec4 vertex_color;
layout(location=2) in vec2 vertex_uv;
#endif

uniform mat4 projection;

INOUT vec4 fragment_color;
INOUT vec2 fragment_uv;

void main()
*/
