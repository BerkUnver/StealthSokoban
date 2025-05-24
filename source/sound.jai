Sound :: struct {
    base: *void;
    // Most of the WAV file is just uncompressed data. It's probably good just to
    // store a pointer directly into the WAV for our data. Let's keep the base
    // pointer around, though, in case we decide to use a normal allocator on this.
    data: [] s16;
}


Playing_Sound :: struct {
    wav: *Sound;
    current_sample: int;
    
    flags: enum_flags u8 {
        POSITIONAL;
        NEW;
    }

    positional: struct {
        position: Vector3;
    }
}


// I really don't know that much about audio engineering so I am doing my best
// with what I know. We are aiming to mix sfx around -18 dbfs. I have decided to
// export sfx with -1dbfs of headroom, and then do the volume reduction in the 
// audio mixer. This seems like the accepted way to do it.

//              -berk, 2025 - 5 - 14
SFX_VOLUME_REDUCTION :: #run pow(10, -17.0 / 20.0);


load_sound :: (path: string, arena: *Memory_Arena) -> Sound {
    success, base := read_file(path, arena);
    assert(success);

    get_chunk_id :: (str: string) -> id: string, str: string {
        assert(str.count >= 4);
        id := string.{4, str.data};
        return id, .{str.count - 4, str.data + 4};
    }

    str := base;
    
    assert(str.count >= 12);
    
    riff_id:, str = get_chunk_id(str);
    assert(riff_id == "RIFF");

    rest_of_file_size:, str = get(str, u32);
    assert(rest_of_file_size == str.count);
    
    wave_id:, str = get_chunk_id(str);
    assert(wave_id == "WAVE");

    has_format := false;
    has_samples := false;

    samples: [] s16;

    while str.count != 0 {
        chunk_id:, str = get_chunk_id(str);
        if chunk_id == {
            case "fmt ";
                assert(!has_format);
                has_format = true;
                format: WAVEFORMATEX = ---;
                format_size:, str = get(str, u32);
                assert(str.count >= format_size);
                if format_size == 16 {
                    memcpy(*format, str.data, format_size);
                    format.cbSize = 0;
                } else if format_size == 18 {
                    memcpy(*format, str.data, format_size);
                    assert(format.cbSize == 0);
                } else if format_size == 40 {
                    assert(false);
                    // We don't accept WAV files that use the current,
                    // extended format right now.
                } else {
                    assert(false); // These WAV files are poorly-formed.
                }
                str = advance(str, format_size);
                
                // We only accept single-channel PCM data for now.

                assert(format.nChannels == 1);
                assert(format.wFormatTag == WAVE_FORMAT_PCM);
                assert(format.nSamplesPerSec == AUDIO_SAMPLES_PER_SECOND);
                assert(format.nBlockAlign == size_of(s16));
                assert(format.wBitsPerSample == size_of(s16) * 8);
            case "fact";
                assert(false);
                // The documentation states that PCM wav files _might_ have this.
                // We might just want to do nothing if we encounter this chunk.
            case "data";
                assert(!has_samples);
                has_samples = true;
                data_size:, str = get(str, u32);
                samples = .{data_size / size_of(s16), xx str.data};
                str = advance(str, data_size);
            case "junk";
                // Used for byte alignment
                size:, str = get(str, u32);
                if size % 2 == 1 size += 1;
                str = advance(str, size);
            case;
                assert(false);
        }
    }
    
    assert(has_format);
    assert(has_samples);

    return .{
        base = base.data,
        data = samples
    };
}
