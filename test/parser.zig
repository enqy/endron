const std = @import("std");
const tokenizer = @import("endron").tokenizer;
const parser = @import("endron").parser;

test "basic parsing" {
    const source =
        \\// comment
        \\@std;$struct,{|import;"std"}
    ;
    const expected =
        \\Decl:
        \\  std <
        \\    {
        \\      Type:
        \\        struct <>
        \\    }
        \\  > =
        \\    {
        \\      Builtin:
        \\        import(
        \\          "std"
        \\        )
        \\    }
        \\
        \\
    ;

    try expectAst(std.testing.allocator, source, expected);
}

test "branch parsing" {
    const source =
        \\// comment
        \\?{#=;:.result,100};{
        \\    !:^print;"Result is 100"
        \\},{
        \\    !:^print;"Result is not 100"
        \\}
    ;
    const expected =
        \\Branch:
        \\  {
        \\    Alu:
        \\      eql(
        \\        ^.::result
        \\        100
        \\      )
        \\  }
        \\    then:
        \\      {
        \\        Call:
        \\          ^::print(
        \\            "Result is 100"
        \\          )
        \\      }
        \\    else:
        \\      {
        \\        Call:
        \\          ^::print(
        \\            "Result is not 100"
        \\          )
        \\      }
        \\
        \\
    ;

    try expectAst(std.testing.allocator, source, expected);
}

fn expectAst(alloc: std.mem.Allocator, source: []const u8, expected: []const u8) !void {
    const tokens = try tokenizer.tokenize(alloc, source);
    defer alloc.free(tokens);
    const tree = try parser.parse(alloc, source, tokens);
    defer tree.deinit();
    var actual = std.ArrayList(u8).init(alloc);
    defer actual.deinit();
    try tree.root.render(actual.writer(), 0);
    try std.testing.expectEqualStrings(expected, actual.items);
}
