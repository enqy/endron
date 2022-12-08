const std = @import("std");
const tokenizer = @import("endron").tokenizer;

test "tokenizer.detokenize is inverse of tokenizer.tokenize" {
    const alloc = std.testing.allocator;

    const source = @embedFile("basic.edr");

    const tokens = try tokenizer.tokenize(alloc, source);
    defer alloc.free(tokens);

    const detokenized = try tokenizer.detokenize(alloc, source, tokens);
    defer alloc.free(detokenized);

    try std.testing.expectEqualBytes(source, detokenized);
}
