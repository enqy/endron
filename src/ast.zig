const std = @import("std");
const Allocator = std.mem.Allocator;

const Token = @import("tokenizer.zig").Token;

pub const Tree = struct {
    root: *Node,

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
        // ops
        Decl,
        Assign,
        Call,
        BuiltinCall,
        Ret,

        // exprs
        Ident,
        Literal,
        Tuple,
        Map,
        MapItem,

        Discard,

        Scope,
        Block,
    };

    pub const Decl = struct {
        base: Node = .{ .kind = .Decl },

        cap: *Node,
        mods: *Node,
        value: ?*Node,

        dollar_tok: usize,
        colon_tok: usize,
        eql_tok: ?usize,
    };

    pub const Assign = struct {
        base: Node = .{ .kind = .Assign },

        cap: *Node,
        value: *Node,

        dollar_tok: usize,
        eql_tok: usize,
    };

    pub const Call = struct {
        base: Node = .{ .kind = .Call },

        cap: *Node,
        args: ?*Node,

        bang_tok: usize,
        colon_tok: ?usize,
    };

    pub const BuiltinCall = struct {
        base: Node = .{ .kind = .BuiltinCall },

        builtin: *Node,
        args: *Node,

        at_tok: usize,
        colon_tok: usize,
    };

    pub const Ret = struct {
        base: Node = .{ .kind = .Ret },

        cap: *Node,

        tilde_tok: usize,
    };

    pub const Ident = struct {
        base: Node = .{ .kind = .Ident },

        tok: usize,
    };

    pub const Literal = struct {
        base: Node = .{ .kind = .Literal },

        tok: usize,
    };

    pub const Tuple = struct {
        base: Node = .{ .kind = .Tuple },

        nodes: []*Node,
    };

    pub const Map = struct {
        base: Node = .{ .kind = .Map },

        nodes: []*Node,
    };

    pub const MapItem = struct {
        base: Node = .{ .kind = .MapItem },

        key: *Node,
        value: *Node,

        colon_tok: usize,
    };

    pub const Discard = struct {
        base: Node = .{ .kind = .Discard },

        tok: usize,
    };

    pub const Scope = struct {
        base: Node = .{ .kind = .Scope },

        lhs: ?*Node,
        rhs: *Node,

        period_tok: usize,
    };

    pub const Block = struct {
        base: Node = .{ .kind = .Block },

        nodes: []*Node,
    };

    pub fn render(node: *Node, writer: anytype, level: u8, source: []const u8, tokens: []const Token) anyerror!void {
        switch (node.kind) {
            // ops
            .Decl => {
                const n = @fieldParentPtr(Decl, "base", node);

                _ = try writer.writeAll("$");
                try n.cap.render(writer, level, source, tokens);
                _ = try writer.writeAll(": ");
                try n.mods.render(writer, level, source, tokens);
                if (n.value) |value| {
                    _ = try writer.writeAll(" = ");
                    try value.render(writer, level, source, tokens);
                }
            },
            .Assign => {
                const n = @fieldParentPtr(Assign, "base", node);

                _ = try writer.writeAll("$");
                try n.cap.render(writer, level, source, tokens);
                _ = try writer.writeAll(" = ");
                try n.value.render(writer, level, source, tokens);
            },
            .Call => {
                const n = @fieldParentPtr(Call, "base", node);

                _ = try writer.writeAll("!");
                try n.cap.render(writer, level, source, tokens);
                if (n.args) |args| {
                    _ = try writer.writeAll(":");
                    try args.render(writer, level, source, tokens);
                }
            },
            .BuiltinCall => {
                const n = @fieldParentPtr(BuiltinCall, "base", node);
                _ = try writer.writeAll("@");
                try n.builtin.render(writer, level, source, tokens);
                _ = try writer.writeAll(": ");
                try n.args.render(writer, level, source, tokens);
            },
            .Ret => {
                const n = @fieldParentPtr(Ret, "base", node);

                _ = try writer.writeAll("~");
                try n.cap.render(writer, level, source, tokens);
            },

            // exprs
            .Ident => {
                const n = @fieldParentPtr(Ident, "base", node);

                _ = try writer.print("{}", .{source[tokens[n.tok].start..tokens[n.tok].end]});
            },

            .Literal => {
                const n = @fieldParentPtr(Literal, "base", node);

                _ = try writer.print("{}", .{source[tokens[n.tok].start..tokens[n.tok].end]});
            },
            .Tuple => {
                const n = @fieldParentPtr(Tuple, "base", node);

                _ = try writer.writeAll("(");
                for (n.nodes) |expr, j| {
                    if (j != 0) _ = try writer.writeAll(", ");
                    try expr.render(writer, level, source, tokens);
                }
                _ = try writer.writeAll(")");
            },
            .Map => {
                const n = @fieldParentPtr(Map, "base", node);

                _ = try writer.writeAll("<");
                for (n.nodes) |expr, j| {
                    if (j != 0) _ = try writer.writeAll(", ");
                    try expr.render(writer, level, source, tokens);
                }
                _ = try writer.writeAll(">");
            },
            .MapItem => {
                const n = @fieldParentPtr(MapItem, "base", node);

                try n.key.render(writer, level, source, tokens);
                _ = try writer.writeAll(":");
                try n.value.render(writer, level, source, tokens);
            },

            .Discard => {
                _ = try writer.writeAll("_");
            },

            .Scope => {
                const n = @fieldParentPtr(Scope, "base", node);

                if (n.lhs) |lhs| {
                    try lhs.render(writer, level, source, tokens);
                }
                _ = try writer.writeAll(".");
                try n.rhs.render(writer, level, source, tokens);
            },
            .Block => {
                const n = @fieldParentPtr(Block, "base", node);

                if (level != 0) _ = try writer.writeAll("{\n");
                for (n.nodes) |nod| {
                    var i: u8 = 0;
                    while (i < level) : (i += 1) _ = try writer.writeAll("  ");
                    try nod.render(writer, level + 1, source, tokens);
                    _ = try writer.writeAll("\n");
                }
                if (level != 0) {
                    var i: u8 = 0;
                    while (i + 1 < level) : (i += 1) _ = try writer.writeAll("  ");
                    _ = try writer.writeAll("}");
                }
            },
        }
    }
};
