Wav :: struct {
    base: *void;
    // Most of the WAV file is just uncompressed data. It's probably good just to
    // store a pointer directly into the WAV for our data. Let's keep the base
    // pointer around, though, in case we decide to use a normal allocator on this.
    data: [] s16;
}


Playing_Sound :: struct {
    wav: *Wav;
    current_sample: int;

    type: enum u8 {
        SIMPLE;
        POSITIONAL;
    }

    union {
        positional: struct {
            position: Vector3;
        }
    }
}


load_wav :: (path: string, arena: *Memory_Arena) -> Wav {
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
    samples: string;

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
                assert(format.nBlockAlign == AUDIO_BYTES_PER_SAMPLE);
                assert(format.wBitsPerSample == AUDIO_BYTES_PER_SAMPLE * 8);
            case "fact";
                assert(false);
                // The documentation states that PCM wav files _might_ have this.
                // We might just want to do nothing if we encounter this chunk.
            case "data";
                assert(!has_samples);
                has_samples = true;
                data_size:, str = get(str, u32);
                samples.count = data_size;
                samples.data = str.data;
                padded_data_size := data_size;
                if padded_data_size % 2 == 1 padded_data_size += 1;
                assert(str.count >= padded_data_size);
                str = advance(str, padded_data_size);
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
        data = .{samples.count / AUDIO_BYTES_PER_SAMPLE, xx samples.data}
    };
}
