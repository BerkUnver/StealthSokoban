Font :: struct {
    bitmap: GLuint;
}

make_font :: () -> Font {    
    using context.game_context.gl_procs;

    // @Incomplete Make this use a simple bump allocator and then
    // free everything when we are done.

    ft: FT_Library;
    assert(FT_Init_FreeType(*ft) == 0);

    face: FT_Face;
    assert(FT_New_Face(ft, "consolas.ttf", 0, *face) == 0);

    FT_Set_Pixel_Sizes(face, 0, 48);
    
    assert(FT_Load_Char(face, #char "X", FT_LOAD_RENDER) == 0);

    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);  

    bitmap: GLuint;
    glGenTextures(1, *bitmap);
    glBindTexture(GL_TEXTURE_2D, bitmap);
    glTexImage2D(
        GL_TEXTURE_2D,
        0,
        GL_RED,
        face.glyph.bitmap.width,
        face.glyph.bitmap.rows,
        0,
        GL_RED,
        GL_UNSIGNED_BYTE,
        face.glyph.bitmap.buffer
    );
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

    FT_Done_Face(face);
    FT_Done_FreeType(ft);

    return .{bitmap=bitmap};
}


draw_text :: (font: * Font, projection: Matrix4) {
    using context.game_context;

    glUseProgram(imm_text_shader);

    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, font.bitmap);
    
    set_uniform("projection", projection);
    set_uniform("bitmap", cast(s32, 0));
    
    x0 := 0.0;
    y0 := 0.0;
    x1 := 100.0;
    y1 := 100.0;
    
    COLOR :: Vector4.{1,1,1,1};
    imm_vertex(.{x0, y0, 0}, .{0, 0}, COLOR);
    imm_vertex(.{x1, y0, 0}, .{1, 0}, COLOR);
    imm_vertex(.{x1, y1, 0}, .{1, 1}, COLOR);
    imm_vertex(.{x0, y0, 0}, .{0, 0}, COLOR);
    imm_vertex(.{x1, y1, 0}, .{1, 1}, COLOR);
    imm_vertex(.{x0, y1, 0}, .{0, 1}, COLOR);

    imm_flush();
}
