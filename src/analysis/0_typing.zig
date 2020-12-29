const std = @import("std");
const Allocator = std.mem.Allocator;

const Tree = @import("../ast.zig").Tree;

pub fn pass(arena: *Allocator, tree: *Tree) !void {}
