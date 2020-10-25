const std = @import("std");
const Allocator = std.mem.Allocator;

const ast = @import("ast.zig");
const Tree = ast.Tree;
const Node = ast.Node;

const tast = @import("typed_ast.zig");
const TypedTree = tast.TypedTree;

const Pass = fn (*Allocator, *const Tree, *TypedTree) anyerror!void;
const Passes = [_]Pass{};

pub fn analyze(tree: *const Tree) !void {
    var arena = std.heap.ArenaAllocator.init(tree.gpa);
    defer arena.deinit();

    var ttree = try TypedTree.transform(&arena.allocator, tree);

    for (Passes) |pass| {
        try pass(&arena.allocator, tree, &ttree);
    }
}
