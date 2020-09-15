const std = @import("std");
const process = std.process;
const mem = std.mem;

const pa = @import("parser2.zig");

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(!gpa.deinit());
    var allocator = &gpa.allocator;

    var arg_it = process.args();

    _ = arg_it.skip();
    const filename = try (arg_it.next(allocator).?);
    defer allocator.free(filename);

    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();
    const source = try file.reader().readAllAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(source);

    var tree = try pa.parse(allocator, source);
    defer tree.deinit();

    for (tree.nodes) |node| try node.render(std.io.getStdOut().writer(), 0);
}
