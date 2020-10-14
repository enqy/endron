const std = @import("std");
const Allocator = std.mem.Allocator;

const ast = @import("ast.zig");
const Tree = ast.Tree;
const Node = ast.Node;

const tast = @import("typed_ast.zig");

const Pass = fn (*Allocator, *Tree, *State) anyerror!void;
const Passes = [_]Pass{};

pub fn analyze(tree: *Tree) !void {
    var arena = std.heap.ArenaAllocator.init(tree.gpa);
    defer arena.deinit();

    var state = try State.transform(&arena.allocator, tree);

    for (Passes) |pass| {
        try pass(&arena.allocator, tree, &state);
    }
}

pub const State = struct {
    pub const TypeInfo = struct {};

    types: std.ArrayList(TypeInfo),
    type_map: std.StringHashMap(tast.TypeId),

    root: *tast.Module,

    pub fn transform(arena: *Allocator, tree: *Tree) !State {
        var state = State{
            .types = std.ArrayList(TypeInfo).init(arena),
            .type_map = std.StringHashMap(tast.TypeId).init(arena),

            .root = try tast.Module.init(arena),
        };

        if (tree.root.kind != .Block) @panic("Expected Block Node");
        var troot = @fieldParentPtr(Node.Block, "base", tree.root);
        for (troot.nodes) |node| {
            switch (node.kind) {
                .Decl => {
                    const n = @fieldParentPtr(Node.Decl, "base", node);
                    if (n.cap.kind != .Ident) @panic("Expected Ident Node for Decl Node Cap");
                    const cap = @fieldParentPtr(Node.Ident, "base", n.cap);
                    try state.root.decls.put(tree.getTokSource(cap.tok), tast.Decl{
                        .cap = tree.getTokSource(cap.tok),
                        .mods = 0,
                        .type_id = 0,

                        .value = null,
                    });
                },
                .Assign => {
                    const n = @fieldParentPtr(Node.Assign, "base", node);
                    if (n.cap.kind != .Ident) @panic("Expected Ident Node for Decl Node Cap");
                    const cap = @fieldParentPtr(Node.Ident, "base", n.cap);
                    try state.root.decls.put(tree.getTokSource(cap.tok), tast.Decl{
                        .cap = tree.getTokSource(cap.tok),
                        .mods = 0,
                        .type_id = 0,

                        .value = null,
                    });
                },
                else => @panic("Expected Decl or Assign Node"),
            }
        }

        var iter = state.root.decls.iterator();
        while (iter.next()) |entry| {
            std.debug.print("{}\n", .{entry.value});
        }

        return state;
    }
};
