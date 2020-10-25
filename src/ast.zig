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

    pub fn getTokSource(self: *const Tree, tok: usize) []const u8 {
        return self.source[self.tokens[tok].start..self.tokens[tok].end];
    }
};

pub const Node = struct {
    kind: Kind,

    pub const Kind = enum {
        // ops
        Decl,
        Set,
        Call,
        Builtin,
        CompCall,
        Ret,
        MathAdd,
        MathSub,
        MathMul,
        MathDiv,

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

    // ops
    pub const Decl = struct {
        base: Node = .{ .kind = .Decl },

        cap: *Node,
        mods: ?*Node,
        value: ?*Node,

        dollar_tok: usize,
        colon_tok: ?usize,
        eql_tok: ?usize,
    };

    pub const Set = struct {
        base: Node = .{ .kind = .Set },

        cap: *Node,
        value: *Node,

        tilde_tok: usize,
        eql_tok: usize,
    };

    pub const Call = struct {
        base: Node = .{ .kind = .Call },

        cap: *Node,
        args: ?*Node,

        bang_tok: usize,
    };

    pub const Builtin = struct {
        base: Node = .{ .kind = .Builtin },

        cap: *Node,
        args: ?*Node,

        at_tok: usize,
    };

    pub const CompCall = struct {
        base: Node = .{ .kind = .CompCall },

        cap: *Node,
        args: ?*Node,

        percent_tok: usize,
    };

    pub const Ret = struct {
        base: Node = .{ .kind = .Ret },

        cap: *Node,

        caret_tok: usize,
    };

    pub const MathAdd = struct {
        base: Node = .{ .kind = .MathAdd },

        args: *Node,

        mtok: usize,
    };

    pub const MathSub = struct {
        base: Node = .{ .kind = .MathSub },

        args: *Node,

        mtok: usize,
    };

    pub const MathMul = struct {
        base: Node = .{ .kind = .MathMul },

        args: *Node,

        mtok: usize,
    };

    pub const MathDiv = struct {
        base: Node = .{ .kind = .MathDiv },

        args: *Node,

        mtok: usize,
    };

    // exprs
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
                if (n.mods) |mods| {
                    _ = try writer.writeAll(": ");
                    try mods.render(writer, level, source, tokens);
                }
                if (n.value) |value| {
                    _ = try writer.writeAll(" = ");
                    try value.render(writer, level, source, tokens);
                }
            },
            .Set => {
                const n = @fieldParentPtr(Set, "base", node);

                _ = try writer.writeAll("~");
                try n.cap.render(writer, level, source, tokens);
                _ = try writer.writeAll(" = ");
                try n.value.render(writer, level, source, tokens);
            },
            .Call => {
                const n = @fieldParentPtr(Call, "base", node);

                _ = try writer.writeAll("!");
                try n.cap.render(writer, level, source, tokens);
                if (n.args) |args| try args.render(writer, level, source, tokens);
            },
            .Builtin => {
                const n = @fieldParentPtr(Builtin, "base", node);
                _ = try writer.writeAll("@");
                try n.cap.render(writer, level, source, tokens);
                if (n.args) |args| try args.render(writer, level, source, tokens);
            },
            .CompCall => {
                const n = @fieldParentPtr(CompCall, "base", node);
                _ = try writer.writeAll("%");
                try n.cap.render(writer, level, source, tokens);
                if (n.args) |args| try args.render(writer, level, source, tokens);
            },
            .Ret => {
                const n = @fieldParentPtr(Ret, "base", node);

                _ = try writer.writeAll("^");
                try n.cap.render(writer, level, source, tokens);
            },
            .MathAdd => {
                const n = @fieldParentPtr(MathAdd, "base", node);

                _ = try writer.writeAll("#+");
                try n.args.render(writer, level, source, tokens);
            },
            .MathSub => {
                const n = @fieldParentPtr(MathSub, "base", node);

                _ = try writer.writeAll("#-");
                try n.args.render(writer, level, source, tokens);
            },
            .MathMul => {
                const n = @fieldParentPtr(MathMul, "base", node);

                _ = try writer.writeAll("#*");
                try n.args.render(writer, level, source, tokens);
            },
            .MathDiv => {
                const n = @fieldParentPtr(MathDiv, "base", node);

                _ = try writer.writeAll("#/");
                try n.args.render(writer, level, source, tokens);
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
