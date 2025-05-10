Asset_Info :: struct { type, proc: string; needs_permanent_arena: bool; }
ASSET_INFOS :: Asset_Info.[
    .{"Shader", "load_shader", false},
    .{"Sound", "load_sound", true},
    .{"Mesh", "load_mesh", true},
    .{"Bitmap", "load_bitmap", false},
];


Asset :: struct {
    #insert -> string {
        buf: [4096] u8 = ---;
        sb := make_string_builder(buf);

        print(*sb, "Type :: enum u8 {\n");
        for ASSET_INFOS {
            print(*sb, "    %;\n", it.type);
        }
        print(*sb, "}\n\n");
       
        print(*sb, "type: Type;\n\n");

        print(*sb, "union {\n");
        for ASSET_INFOS {
            print(*sb, "    _%: %;\n", it.type, it.type);
        }
        print(*sb, "}\n");

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
            str := ifx ASSET_INFO.needs_permanent_arena then ", permanent_arena" else "";
            print(*sb, "asset.* = .{ type = .%, _% = %(name%) };\n", ASSET_INFO.type, ASSET_INFO.type, ASSET_INFO.proc, str);
            return get_string(*sb);
        }
    } else {
        #insert -> string {
            buf: [4096] u8 = ---;
            sb := make_string_builder(buf);
            print(*sb, "assert(asset.type == .%);\n", ASSET_INFO.type);
            return get_string(*sb);
        }
    }

    #insert -> string {
        buf: [4096] u8 = ---;
        sb := make_string_builder(buf);
        print(*sb, "return *asset._%;\n", ASSET_INFO.type);
        return get_string(*sb);
    }
}


reload_assets :: (table: *Asset_Table, changed_file_names: [] string) {
    using context.game_context;

    // @Hack:
    // In the shipping game, asset hot-reloading will be disabled so we
    // don't need to worry about this. When we hotload an asset that
    // takes up CPU space, we just append the new one onto the 
    // permanent_arena. That means the old version is still in memory
    // even though it doesn't need to be.

    // We could clean up the GPU resources instead of loading new ones
    // but until the CPU stuff is fixed let's just leave it.

    for changed_file_names {
        asset := get(table, it);
        if !asset continue;
        log(.OK, "Hotloading asset \"%\"\n", it);
        #insert -> string {
            buf: [4096] u8 = ---;
            sb := make_string_builder(buf);
            print(*sb, "if asset.type == {\n");
            for ASSET_INFOS {
                print(*sb, "    case .%;\n", it.type);
                str := ifx it.needs_permanent_arena then ", permanent_arena" else "";
                print(*sb, "        asset._% = %(it%);\n", it.type, it.proc, str);
            }
            print(*sb, "    case; assert(false);\n");
            print(*sb, "}\n");
            return get_string(*sb);
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
