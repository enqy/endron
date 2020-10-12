const std = @import("std");
const Allocator = std.mem.Allocator;

const ast = @import("ast.zig");
const Tree = ast.Tree;
const Node = ast.Node;

const Pass = fn (*Allocator, *Tree, *State) anyerror!void;
const Passes = [_]Pass{};

pub fn analyze(tree: *Tree) !void {
    var arena = std.heap.ArenaAllocator.init(tree.gpa);
    defer arena.deinit();

    var state = State{};

    for (Passes) |pass| {
        try pass(&arena.allocator, tree, &state);
    }
}

pub const State = struct {
    pub const TypeInfo = struct {};
    types: std.ArrayList(TypeInfo),
    type_map: std.StringHashMap(usize),
};
