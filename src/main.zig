const std = @import("std");
const process = std.process;
const mem = std.mem;

const pa = @import("parser.zig");
const an = @import("analysis.zig");
const gn = @import("codegen.zig");

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var allocator = &gpa.allocator;

    var arg_it = process.args();

    _ = arg_it.skip();
    const filename = try (arg_it.next(allocator) orelse @panic("invalid filename"));
    defer allocator.free(filename);

    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();
    const source = try file.reader().readAllAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(source);

    var tree = try pa.parse(allocator, source);
    defer tree.deinit();

    try an.analyze(tree);

    const output = try gn.generate(tree, .endron);
    defer tree.gpa.free(output);
    try std.io.getStdOut().writeAll(output);
}
