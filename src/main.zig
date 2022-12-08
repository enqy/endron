const std = @import("std");
const log = std.log.scoped(.main);

const tokenizer = @import("tokenizer.zig");
const parser = @import("parser.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = std.process.args();

    _ = args.skip();
    const filename = args.next() orelse return error.InvalidFilename;

    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    const source = try file.reader().readAllAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(source);

    const tokens = try tokenizer.tokenize(allocator, source);
    defer allocator.free(tokens);

    const detokenized = try tokenizer.detokenize(allocator, source, tokens);
    defer allocator.free(detokenized);

    log.info("tokenized: {any}", .{tokens});
    log.info("detokenized: {s}", .{detokenized});

    var tree = try parser.parse(allocator, source, tokens);
    defer tree.deinit();
    try tree.root.render(std.io.getStdOut().writer(), 0);
}

comptime {
    _ = @import("tokenizer.zig");
}
