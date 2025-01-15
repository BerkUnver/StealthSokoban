
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

imm_init :: () -> Imm_State {
    using s: Imm_State;

    glGenVertexArrays(1, *vao);
    // The vao (vertex attribute object) just is a data structure that stores how the vertex information is structured.
    // We specifiy this by calling glBindVertexArray(vao), then calling glVertexAttribPointer to describe how an
    // attribute is stored before finally calling glEnableVertexAttribArray to use that attribute.

    glGenBuffers(1, *vbo);

    glBindVertexArray(vao);
    
    // Tell OpenGL how to use the current 
    POSITION_UNIFORM_LOC :: 0;
    glVertexAttribPointer(POSITION_UNIFORM_LOC, 3, GL_FLOAT, GL_FALSE, size_of(Vertex), *cast(*Vertex, null).position);
    glEnableVertexAttribArray(POSITION_UNIFORM_LOC); 

    COLOR_UNIFORM_LOC :: 1;
    glEnableVertexAttribArray(COLOR_UNIFORM_LOC);
    glVertexAttribPointer(COLOR_UNIFORM_LOC, 4, GL_FLOAT, GL_TRUE, size_of(Vertex), xx *cast(*Vertex, null).color);


    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0); 
    // This indicates an array of the indices of vertices if we are using indices instead of the vertex directly.
    // We aren't, so this is 0 to indicate that.

    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glBufferData(GL_ARRAY_BUFFER, size_of(Vertex) * vertices.count, null, GL_STREAM_DRAW); // Allocate the buffer

    
    //
    // Initialize shaders
    //

    register_shader :: (type: GLenum, text: string) -> GLuint {
        shader := glCreateShader(type);
        text_count := cast(GLint)text.count;
        glShaderSource(shader, 1, *text.data, *text_count);
        glCompileShader(shader);

        success: GLint;
        glGetShaderiv(shader, GL_COMPILE_STATUS, *success);
        // @TODO: Log shader parsing errors.
        if !success return 0;
        return shader;
    }

    vertex   := register_shader(GL_VERTEX_SHADER,   VERTEX_SOURCE);
    fragment := register_shader(GL_FRAGMENT_SHADER, FRAGMENT_SOURCE);
    // :Assert Make sure these are nonzero, meaning they parsed correctly.

    program := glCreateProgram();
    glAttachShader(program, vertex);
    glAttachShader(program, fragment);
    glLinkProgram(program);

    success: GLint;
    glGetProgramiv(program, GL_LINK_STATUS, *success);
    // :Assert Make sure this is nonzero, meaning the default program linked correctly

    glDeleteShader(fragment);
    glDeleteShader(vertex);
    glUseProgram(program);

    return s;
}

imm_begin :: (using s: *Imm_State) {
    // :Assert make sure that we aren't submitting vertices!
    submitting_vertices = true;
}

imm_end :: (using s: *Imm_State) {
    // :Assert make sure we are submitting vertices!
    upload_vertices_to_gpu(s);
    submitting_vertices = false;    
}

imm_vertex :: (using s: *Imm_State, position: Vector3, color: Vector4) {
    // :Assert make sure we are submitting vertices!
    if vertex_count == vertices.count upload_vertices_to_gpu(s);
    vertices[vertex_count] = .{
        position=position,
        color=color
    };
    vertex_count += 1;
}

imm_rect :: (s: *Imm_State, x: float, y: float, w: float, h: float, color: Vector4) {
    x_end := x + w;
    y_end := y + h;
    p1 := Vector3.{x, y, 0};
    p2 := Vector3.{x_end, y, 0};
    p3 := Vector3.{x_end, y_end, 0};
    p4 := Vector3.{x, y_end, 0};

    imm_vertex(s, p1, color);
    imm_vertex(s, p2, color);
    imm_vertex(s, p3, color);
    imm_vertex(s, p1, color);
    imm_vertex(s, p4, color);
    imm_vertex(s, p2, color);
}




#scope_file
upload_vertices_to_gpu :: (using s: *Imm_State) {
    glBufferSubData(GL_ARRAY_BUFFER, 0, size_of(Vertex) * vertex_count, vertices.data);
    glDrawArrays(GL_TRIANGLES, 0, vertex_count);
    vertex_count = 0;
}


VERTEX_SOURCE :: #string END
#version 330 core
layout(location=0) in vec4 vertex_position;
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
