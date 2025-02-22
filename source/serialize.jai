serialize :: () {
    using context.game_context;

    buf: [4096] u8 = ---;
    sb := make_string_builder(buf);
    print(*sb, "bruh\n");

    str := get_string(*sb);
    write_file("test_serialize.txt", str);
}
