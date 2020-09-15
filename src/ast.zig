const std = @import("std");
const Allocator = std.mem.Allocator;

const Token = @import("tokenizer.zig").Token;

pub const Tree = struct {
    nodes: []const *Node,

    tokens: []const Token,
    source: []const u8,

    arena: std.heap.ArenaAllocator.State,
    gpa: *Allocator,

    pub fn deinit(self: *Tree) void {
        self.gpa.free(self.tokens);
        self.arena.promote(self.gpa).deinit();
    }
};

pub const Node = struct {
    kind: Kind,

    pub const Kind = enum {
        Decl,
        Call,
        Ident,
    };

    pub const Decl = struct {
        base: Node = .{ .kind = .Decl },

        tok: usize,
        cap: *Node,
        colon: usize,
    };

    pub const Call = struct {
        base: Node = .{ .kind = .Call },
    };

    pub const Ident = struct {
        base: Node = .{ .kind = .Ident },
        tok: usize,
    };

    pub fn render(node: *Node, writer: anytype, level: u16) anyerror!void {
        var i: u16 = 0;
        while (i < level) : (i += 1) _ = try writer.writeAll("-");
        switch (node.kind) {
            .Decl => {
                const n = @fieldParentPtr(Decl, "base", node);

                _ = try writer.writeAll("Decl");
                _ = try writer.writeAll("\n");
                try n.cap.render(writer, level + 1);
            },
            .Call => {
                _ = try writer.writeAll("Call");
            },
            .Ident => {
                _ = try writer.writeAll("Ident");
            },
        }

        _ = try writer.writeAll("\n");
    }
};
