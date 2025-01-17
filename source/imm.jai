Vertex :: struct {
    position: Vector3;
    color: Vector4;
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
    
    POSITION_UNIFORM_LOC :: 0;
    glVertexAttribPointer(POSITION_UNIFORM_LOC, 3, GL_FLOAT, GL_FALSE, size_of(Vertex), *cast(*Vertex, null).position);
    glEnableVertexAttribArray(POSITION_UNIFORM_LOC); 

    COLOR_UNIFORM_LOC :: 1;
    glVertexAttribPointer(COLOR_UNIFORM_LOC, 4, GL_FLOAT, GL_FALSE, size_of(Vertex), *cast(*Vertex, null).color);
    glEnableVertexAttribArray(COLOR_UNIFORM_LOC);




    
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
        if !success return 0;
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
    
    matrix := MATRIX4_IDENTITY;
    glUniformMatrix4fv(0, 1, GL_TRUE, *matrix.x_x);
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

imm_vertex :: (g: *Game, position: Vector3, color: Vector4) {
    using g.imm_state;
    assert(submitting_vertices);
    if vertex_count == vertices.count upload_vertices_to_gpu(g);
    vertices[vertex_count] = .{
        position=position,
        color=color
    };
    vertex_count += 1;
}

imm_rect :: (g: *Game, x: float, y: float, w: float, h: float, color: Vector4) {
    x_end := x + w;
    y_end := y + h;
    p1 := Vector3.{x, y, 0};
    p2 := Vector3.{x_end, y, 0};
    p3 := Vector3.{x_end, y_end, 0};
    p4 := Vector3.{x, y_end, 0};

    imm_vertex(g, p1, color);
    imm_vertex(g, p2, color);
    imm_vertex(g, p3, color);
    imm_vertex(g, p1, color);
    imm_vertex(g, p3, color);
    imm_vertex(g, p4, color);
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

uniform mat4 projection;
out vec4 fragment_color;

void main() {
    gl_Position = projection * vec4(vertex_position.xyz, 1.0);
    fragment_color = vertex_color;
}
END


FRAGMENT_SOURCE :: #string END
#version 330 core
in vec4 fragment_color;
layout(location=0) out vec4 color;

void main() {
    color = fragment_color;
}
END
