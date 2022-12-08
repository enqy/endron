const std = @import("std");
const log = std.log.scoped(.main);

const tokenizer = @import("tokenizer.zig");
const parser = @import("parser.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var args = std.process.args();

    _ = args.skip();
    const filename = args.next() orelse return error.InvalidFilename;

    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    const source = try file.reader().readAllAlloc(alloc, std.math.maxInt(usize));
    defer alloc.free(source);

    const tokens = try tokenizer.tokenize(alloc, source);
    defer alloc.free(tokens);

    var tree = try parser.parse(alloc, source, tokens);
    defer tree.deinit();
    try tree.root.render(std.io.getStdOut().writer(), 0);
}
