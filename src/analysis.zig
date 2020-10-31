const std = @import("std");
const Allocator = std.mem.Allocator;

const ast = @import("ast.zig");
const Tree = ast.Tree;
const Node = ast.Node;

const Pass = fn (*Allocator, *const Tree) anyerror!void;
const Passes = [_]Pass{};

pub fn analyze(tree: *const Tree) !void {
    var arena = std.heap.ArenaAllocator.init(tree.gpa);
    defer arena.deinit();

    for (Passes) |pass| {
        try pass(&arena.allocator, tree);
    }
}

pub const State = struct {
    pub const Type = struct {};
    pub const TypeId = usize;

    types: std.ArrayList(Type),
    type_mad: std.StringHashMap(TypeId),
};
