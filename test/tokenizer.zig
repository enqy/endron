const std = @import("std");
const tokenizer = @import("endron").tokenizer;

test "basic tokenization" {
    try expectTokens(
        \\aksjdflkjasdf
        \\_asldkjasld
        \\asd009123__asdlkj
        \\091230
        \\012931.12039
        \\"asldkjasldk aslkdjalskdj102398123..ddr*@$(!*@)"
        \\"\""
        \\"
        \\
        \\"
        \\{}()
        \\,;
        \\^:._
        \\_.
        \\@!$|?~
        \\#
        \\+
        \\-
        \\-12039
        \\-154239.102397
        \\*
        \\**
        \\/
        \\><=
        \\//123098 // / // /// / /// / / /////\\////\/\/\//\//192387""_"JSD_J_D!@#(*&$)"
        \\///123098 // / // /// / /// / / /////\\////\/\/\//\//192387""_"JSD_J_D!@#(*&$)"
    , &[_]tokenizer.Token.Kind{
        .ident,
        .ident,
        .ident,
        .literal_number,
        .literal_decimal,
        .literal_string,
        .literal_string,
        .literal_string,
        .lbrace,
        .rbrace,
        .lparen,
        .rparen,
        .comma,
        .semicolon,
        .caret,
        .colon,
        .period,
        .underscore,
        .underscore,
        .period,
        .at,
        .bang,
        .dollar,
        .pipe,
        .question_mark,
        .tilde,
        .number_sign,
        .plus,
        .minus,
        .literal_number,
        .literal_decimal,
        .asterisk,
        .double_asterisk,
        .slash,
        .greater_than,
        .less_than,
        .equal,
        .line_comment,
        .doc_comment,
    });
}

fn expectTokens(source: []const u8, tokens: []const tokenizer.Token.Kind) !void {
    var t = tokenizer.Tokenizer{
        .source = source,
        .tokens = undefined,
    };
    for (tokens) |et| try std.testing.expectEqual(et, t.next().kind);
    try std.testing.expect(t.next().kind == .eof);
}

test "tokenizer.detokenize is inverse of tokenizer.tokenize" {
    const alloc = std.testing.allocator;

    const source = @embedFile("basic.edr");

    const tokens = try tokenizer.tokenize(alloc, source);
    defer alloc.free(tokens);

    const detokenized = try tokenizer.detokenize(alloc, source, tokens);
    defer alloc.free(detokenized);

    try std.testing.expectEqualBytes(source, detokenized);
}
