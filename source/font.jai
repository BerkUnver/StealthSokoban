Font :: struct {
    bitmap: Bitmap;
    space_advance: float;
    glyphs: [VALID_ASCII_END + 1 - VALID_ASCII_START] Glyph;
    ascender: float;
    em: float;
}


Glyph :: struct {
    uv_x0, uv_y0, uv_x1, uv_y1: float;
    size: Vector2;
    bearing: Vector2;
    advance: float;
}


VALID_ASCII_START :: 33;
VALID_ASCII_END :: 126;


load_font :: (file_name: string, height: int) -> Font {
    using context.game_context;
    
    
    // The font data pointer needs to remain valid for the lifetime of the face.
    // We construct the bitmap for the face from data in the face.
    // Therefore, both the font file allocation and the bitmap allocation need
    // to remain valid at the same time, which is why we only call get_mark and
    // restore_mark once.

    scope_mark(frame_arena);

    success, str := read_file(file_name, frame_arena);
    assert(success);

    face: FT_Face;
    assert(FT_New_Memory_Face(freetype, str.data, xx str.count, 0, *face) == 0);
    defer FT_Done_Face(face);


    FT_Set_Pixel_Sizes(face, 0, xx height);


    font: Font;
    font.ascender = cast(float, face.size.metrics.ascender) / 64;
    font.em = xx face.size.metrics.x_ppem;
    bitmap_max_height := height + 1;
    // @Hack if the font is really small sometimes the max height is one larger.
    
    // @TODO: Make the font texture the exact size we need
    BITMAP_WIDTH :: 1024;
    BITMAP_HEIGHT :: 1024;

    x := 0;
    y := 0;

    assert(FT_Load_Char(face, #char " ", FT_LOAD_RENDER) == 0);
    assert(face.glyph.bitmap.width == 0);
    assert(face.glyph.bitmap.rows == 0);
    font.space_advance = xx face.glyph.advance.x / 64.0;


    bitmap_data := alloc(frame_arena, BITMAP_WIDTH * BITMAP_HEIGHT);

    
    for VALID_ASCII_START..VALID_ASCII_END {
        assert(FT_Load_Char(face, xx it, FT_LOAD_RENDER) == 0);
        
        glyph_width := face.glyph.bitmap.width;
        glyph_height := face.glyph.bitmap.rows;

        assert(glyph_height <= bitmap_max_height);
        assert(glyph_width <= BITMAP_WIDTH);
        if x + glyph_width > BITMAP_WIDTH {
            x = 0;
            y += bitmap_max_height;
            assert(y + bitmap_max_height < BITMAP_HEIGHT);
        }

        // @TODO @Speed @Memory: Is there a way to give FreeType a pointer
        // to where we want it to load out of along with a stride instead of
        // copying it?
        
        for 0..glyph_height-1 {
            src := it * glyph_width;
            dest := (y + it) * BITMAP_WIDTH + x;
            memcpy(bitmap_data + dest, face.glyph.bitmap.buffer + src, glyph_width);
        }

        font.glyphs[it - VALID_ASCII_START] = .{
            uv_x0 = cast(float, x) / BITMAP_WIDTH,
            uv_y0 = cast(float, y) / BITMAP_HEIGHT,
            uv_x1 = cast(float, x + glyph_width) / BITMAP_WIDTH,
            uv_y1 = cast(float, y + glyph_height) / BITMAP_HEIGHT,
            size = .{
                xx glyph_width,
                xx glyph_height,
            },
            bearing = .{
                xx face.glyph.bitmap_left,
                xx face.glyph.bitmap_top,
            },
            advance = xx face.glyph.advance.x / 64.0 // Advance is stored in 1/64ths pixels.
        };

        x += glyph_width;
    }

    handle: GLuint;

    glGenTextures(1, *handle);
    glBindTexture(GL_TEXTURE_2D, handle);
    glTexImage2D(
        GL_TEXTURE_2D,
        0,
        GL_RED,
        BITMAP_WIDTH,
        BITMAP_HEIGHT,
        0,
        GL_RED,
        GL_UNSIGNED_BYTE,
        bitmap_data
    );

    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

    font.bitmap = .{handle = handle};

    return font;
}


free_font :: (font: *Font) {
    free_bitmap(*font.bitmap);
}


text_length :: (str: string, font: *Font) -> float {
    length := 0.0;
    for str {
        if it == #char " " {
            length += font.space_advance;
        } else {
            glyph := *font.glyphs[it - VALID_ASCII_START];
            length += glyph.advance;
        }
    }

    return length;
}

