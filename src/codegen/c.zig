const std = @import("std");
const Allocator = std.mem.Allocator;

const ast = @import("../ast.zig");
const Tree = ast.Tree;

pub fn generate(alloc: *Allocator, tree: *Tree) anyerror![]const u8 {
    var output = std.ArrayList(u8).init(tree.gpa);
    defer output.deinit();
    const writer = output.writer();

    return output.toOwnedSlice();
}