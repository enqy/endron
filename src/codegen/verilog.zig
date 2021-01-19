const std = @import("std");
const Allocator = std.mem.Allocator;

const ast = @import("../ast.zig");
const Tree = ast.Tree;

pub fn generate(alloc: *Allocator, tree: *Tree) ![]const u8 {
    return "";
}
