Font :: struct {
    bitmap: GLuint;
    glyph_uvs: [VALID_ASCII_END + 1 - VALID_ASCII_START] Rect;
}


VALID_ASCII_START :: 33;
VALID_ASCII_END :: 126;


make_font :: () -> Font {    
    using context.game_context; // We might call this when the game_context isn't fully initialized. Be careful of this!

    // @Incomplete Make this use a simple bump allocator and then
    // free everything when we are done.

    ft: FT_Library;
    assert(FT_Init_FreeType(*ft) == 0);

    face: FT_Face;
    assert(FT_New_Face(ft, "consolas.ttf", 0, *face) == 0);
    
    FONT_HEIGHT :: 64;
    FT_Set_Pixel_Sizes(face, 0, FONT_HEIGHT);

    font: Font;

    FONT_BITMAP_WIDTH :: 1024;
    FONT_BITMAP_HEIGHT :: 1024;

    mark := get_mark(*frame_arena);
    defer restore_mark(*frame_arena, mark);
    bitmap_data := alloc(*frame_arena, FONT_BITMAP_WIDTH * FONT_BITMAP_HEIGHT);
    
    x := 0;
    y := 0;
    for VALID_ASCII_START..VALID_ASCII_END {
        assert(FT_Load_Char(face, xx it, FT_LOAD_RENDER) == 0);
        
        glyph_width := face.glyph.bitmap.width;
        glyph_height := face.glyph.bitmap.rows;

        assert(glyph_height <= FONT_HEIGHT);
        assert(glyph_width <= FONT_BITMAP_WIDTH);
        if x + glyph_width > FONT_BITMAP_WIDTH {
            x = 0;
            y += FONT_HEIGHT;
            assert(y + FONT_HEIGHT < FONT_BITMAP_HEIGHT);
        }

        for 0..glyph_height-1 {
            src := it * glyph_width;
            dest := (y + it) * FONT_BITMAP_WIDTH + x;
            memcpy(bitmap_data + dest, face.glyph.bitmap.buffer + src, glyph_width);
        }

        x += glyph_width;

        font.glyph_uvs[it - VALID_ASCII_START] = .{xx x, xx y, xx glyph_width, xx glyph_height};
    }

    bitmap: GLuint;

    glGenTextures(1, *bitmap);
    glBindTexture(GL_TEXTURE_2D, bitmap);
    glTexImage2D(
        GL_TEXTURE_2D,
        0,
        GL_RED,
        FONT_BITMAP_WIDTH,
        FONT_BITMAP_HEIGHT,
        0,
        GL_RED,
        GL_UNSIGNED_BYTE,
        bitmap_data
    );
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

    font.bitmap = bitmap;

    FT_Done_Face(face);
    FT_Done_FreeType(ft);

    return font;
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
    x1 := 1024.0;
    y1 := 1024.0;
    
    COLOR :: Vector4.{1,1,1,1};
    imm_vertex(.{x0, y0, 0}, .{0, 0}, COLOR);
    imm_vertex(.{x1, y0, 0}, .{1, 0}, COLOR);
    imm_vertex(.{x1, y1, 0}, .{1, 1}, COLOR);
    imm_vertex(.{x0, y0, 0}, .{0, 0}, COLOR);
    imm_vertex(.{x1, y1, 0}, .{1, 1}, COLOR);
    imm_vertex(.{x0, y1, 0}, .{0, 1}, COLOR);

    imm_flush();
}
