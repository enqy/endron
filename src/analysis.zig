const std = @import("std");
const Allocator = std.mem.Allocator;

const ast = @import("ast.zig");
const Tree = ast.Tree;
const Node = ast.Node;

const tast = @import("typed_ast.zig");
const Module = tast.Module;

const Pass = fn (*Allocator, *const Tree, *Module) anyerror!void;
const Passes = [_]Pass{};

pub fn analyze(tree: *const Tree) !void {
    var arena = std.heap.ArenaAllocator.init(tree.gpa);
    defer arena.deinit();

    var mod = try Module.transform(&arena.allocator, tree);

    for (Passes) |pass| {
        try pass(&arena.allocator, tree, &mod);
    }
}
