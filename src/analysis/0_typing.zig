const std = @import("std");
const Allocator = std.mem.Allocator;

const Tree = @import("../ast.zig").Tree;
const TypedTree = @import("../typed_ast.zig").TypedTree;

pub fn pass(arena: *Allocator, tree: *const Tree, ttree: *TypedTree) !void {}
