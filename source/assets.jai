// @Cleanup You currently need to do five (!) things to register a new asset.
// Let's turn that into one.

Asset_Info :: struct { name, type, proc: string; }
ASSET_INFOS :: Asset_Info.[
    .{"Sound", "Wav", "load_wav"},
    .{"Mesh", "Mesh", "load_mesh"},
    // .{"Bitmap", "GLuint", "load_bitmap"},
];


Asset :: struct {
    #insert -> string {
        buf: [4096] u8 = ---;
        sb := make_string_builder(buf);

        print(*sb, "    Type :: enum u8 {\n");
        for ASSET_INFOS {
            print(*sb, "        %;\n", it.name);
        }
        print(*sb, "    }\n\n");
       
        print(*sb, "    type: Type;\n\n");

        print(*sb, "    union {\n");
        for ASSET_INFOS {
            print(*sb, "        _%: %;\n", it.name, it.type);
        }
        print(*sb, "    }\n");

        return get_string(*sb);
    }
}


load_asset :: ($T: Type, table: *Asset_Table, name: string) -> *T {
    using context.game_context;
    ASSET_INFO :: #run -> Asset_Info {
        type_name := type_info(T).name;
        for ASSET_INFOS {
            if it.type == type_name {
                return it;
            }
        }
        assert(false);
        return .{};
    }

    asset := get(table, name);
    if !asset {
        asset = add(table, name);
        #insert -> string {
            buf: [4096] u8 = ---;
            sb := make_string_builder(buf);
            print(*sb, "asset.* = .{ type = .%, _% = %(name, permanent_arena) };\n", ASSET_INFO.name, ASSET_INFO.name, ASSET_INFO.proc);
            return get_string(*sb);
        }
    } else {
        #insert -> string {
            buf: [4096] u8 = ---;
            sb := make_string_builder(buf);
            print(*sb, "assert(asset.type == .%);\n", ASSET_INFO.name);
            return get_string(*sb);
        }
    }

    #insert -> string {
        buf: [4096] u8 = ---;
        sb := make_string_builder(buf);
        print(*sb, "return *asset._%;\n", ASSET_INFO.name);
        return get_string(*sb);
    }
}


reload_assets :: (table: *Asset_Table, names: [] string) {
    using context.game_context;

    // @Hack:
    // In the shipping game, asset hot-reloading will be disabled so we
    // don't need to worry about this. When we hotload an asset that
    // takes up CPU space, we just append the new one onto the 
    // permanent_arena. That means the old version is still in memory
    // even though it doesn't need to be.

    // We could clean up the GPU resources instead of loading new ones
    // but until the CPU stuff is fixed let's just leave it.

    for names {
        asset := get(table, it);
        if !asset continue;
        print("Asset name: %\n", it);
        if asset.type == {
            case .Sound;
                asset._Sound = load_wav(it, permanent_arena);
            case .Mesh;
                asset._Mesh = load_mesh(it, permanent_arena);
            // case .Bitmap;
            //     asset._Bitmap = load_bitmap(it);
        }
    }
}


asset_table_hash :: (any: Any) -> u32 {
    assert(any.type == type_info(string));
    return djb2_hash(cast(*string, any.value_pointer).*);
}

Asset_Table :: Table(string, Asset, asset_table_hash);


// Let's make the table at startup so it's pointer-stabilized.
make_asset_table :: () -> Asset_Table {
    using context.game_context;
    return make_table(permanent_arena, 1024, string, Asset, asset_table_hash);
}
