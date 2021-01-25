const std = @import("std");
const Allocator = std.mem.Allocator;

const ast = @import("ast.zig");
const Tree = ast.Tree;

const Pass = fn (*Allocator, *Tree) anyerror!void;
const Passes = [_]Pass{
    @import("analysis/0_typing.zig").pass,
    @import("analysis/1_builtin_types.zig").pass,
};

pub fn analyze(tree: *Tree) !void {
    var arena = std.heap.ArenaAllocator.init(tree.gpa);
    defer arena.deinit();

    for (Passes) |pass| {
        try pass(&arena.allocator, tree);
    }
}
