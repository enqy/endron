const std = @import("std");
const Allocator = std.mem.Allocator;

const ast = @import("ast.zig");
const Tree = ast.Tree;
const Node = ast.Node;

pub const TypedTree = struct {
    arena: *Allocator,

    types: std.ArrayList(Type),
    type_map: std.StringHashMap(TypeId),

    root: Block,

    pub fn transform(arena: *Allocator, tree: *const Tree) !TypedTree {
        var ttree = TypedTree{
            .arena = arena,

            .types = std.ArrayList(Type).init(arena),
            .type_map = std.StringHashMap(TypeId).init(arena),

            .root = undefined,
        };

        ttree.root = try ttree.transBlock(tree, tree.root);

        try ttree.root.render(std.io.getStdOut().writer());

        return ttree;
    }

    fn transBlock(ttree: *TypedTree, tree: *const Tree, node: *Node) anyerror!Block {
        var block = Block{
            .ops = std.ArrayList(Op).init(ttree.arena),
        };

        if (node.kind != .Block) @panic("expected block node");
        const n = @fieldParentPtr(Node.Block, "base", node);
        for (n.nodes) |nn| {
            switch (nn.kind) {
                .Decl => try block.ops.append(.{ .Decl = try ttree.transDecl(tree, nn) }),
                .Set => try block.ops.append(.{ .Set = try ttree.transSet(tree, nn) }),
                .Builtin => try block.ops.append(.{ .Call = try ttree.transCall(tree, nn) }),
                else => @panic("expected an inst node"),
            }
        }

        return block;
    }

    fn transDecl(ttree: *TypedTree, tree: *const Tree, node: *Node) anyerror!Op.Decl {
        const n = @fieldParentPtr(Node.Decl, "base", node);
        if (n.cap.kind != .Ident) @panic("expected Ident Node for Decl Node Cap");
        const cap = @fieldParentPtr(Node.Ident, "base", n.cap);

        if (n.mods) |mods| {
            const value = if (n.value) |val| try ttree.transExpr(tree, val) else null;

            return Op.Decl{
                .cap = tree.getTokSource(cap.tok),
                .mods = 0,
                .type_id = 0,

                .value = value,
            };
        } else {
            const value = if (n.value) |val| try ttree.transExpr(tree, val) else unreachable;

            return Op.Decl{
                .cap = tree.getTokSource(cap.tok),
                .mods = 0,
                .type_id = 0,

                .value = value,
            };
        }
    }

    fn transSet(ttree: *TypedTree, tree: *const Tree, node: *Node) anyerror!Op.Set {
        const n = @fieldParentPtr(Node.Set, "base", node);
        if (n.cap.kind != .Ident) @panic("expected Ident Node for decl Node Cap");
        const cap = @fieldParentPtr(Node.Ident, "base", n.cap);

        const value = try ttree.transExpr(tree, n.value);

        return Op.Set{
            .cap = tree.getTokSource(cap.tok),
            .mods = 0,
            .type_id = 0,

            .value = value,
        };
    }

    fn transCall(ttree: *TypedTree, tree: *const Tree, node: *Node) anyerror!Op.Call {
        const n = @fieldParentPtr(Node.Call, "base", node);
        if (n.cap.kind != .Ident) @panic("expected ident node for call node cap");
        const cap = @fieldParentPtr(Node.Ident, "base", n.cap);

        return Op.Call{
            .cap = tree.getTokSource(cap.tok),
        };
    }

    fn transExpr(ttree: *TypedTree, tree: *const Tree, node: *Node) anyerror!Expr {
        switch (node.kind) {
            .Literal => {
                const n = @fieldParentPtr(Node.Literal, "base", node);
                switch (tree.tokens[n.tok].kind) {
                    .LiteralInteger => {
                        return Expr{ .Literal = .{ .Integer = try std.fmt.parseInt(i64, tree.getTokSource(n.tok), 10) } };
                    },
                    .LiteralString => {
                        return Expr{ .Literal = .{ .String = tree.getTokSource(n.tok) } };
                    },
                    else => @panic("not implemented"),
                }
            },
            .Ident => {
                const n = @fieldParentPtr(Node.Ident, "base", node);
                return Expr{ .Ident = tree.getTokSource(n.tok) };
            },
            else => @panic("not implemented"),
        }
    }
};

pub const Block = struct {
    ops: std.ArrayList(Op),

    pub fn render(block: Block, writer: anytype) !void {
        for (block.ops.items) |op| try op.render(writer);
    }
};

pub const Op = union(enum) {
    pub const Decl = struct {
        cap: Ident,
        mods: u2,
        type_id: TypeId,

        value: ?Expr,
    };

    pub const Set = struct {
        cap: Ident,
        mods: u2,
        type_id: TypeId,

        value: Expr,
    };

    pub const Call = struct {
        cap: Ident,
    };

    Decl: Decl,
    Set: Set,
    Call: Call,

    pub fn render(op: Op, writer: anytype) anyerror!void {
        try writer.print("{}\n", .{op});
    }
};

pub const Ident = []const u8;

pub const Literal = union(enum) {
    Integer: i64,
    String: []const u8,
};

pub const Expr = union(enum) {
    Ident: Ident,
    Literal: Literal,
};

pub const ModFlags = enum(u2) {
    is_pub: 0b01,
    is_mut: 0b10,

    pub const Map = std.ComptimeStringMap(ModFlags, .{
        .{ "pub", .is_pub },
        .{ "mut", .is_mut },
    });
};

pub const TypeId = usize;

pub const Type = struct {
    tag: Tag,

    pub const Tag = enum {
        void_,
        u8_,
        u16_,
        u32_,
        u64_,
        usize_,
        i8_,
        i16_,
        i32_,
        i64_,
        isize_,
        f32_,
        f64_,
    };

    pub fn isInteger(self: *Type) !bool {
        switch (self.tag) {
            .u8_,
            .u16_,
            .u32_,
            .u64_,
            .usize_,
            .i8_,
            .i16_,
            .i32_,
            .i64_,
            .isize_,
            => return true,

            .f32_, .f64_ => return false,

            .void_ => return false,
        }
    }

    pub fn isUnsignedInt(self: *Type) !bool {
        switch (self.tag) {
            .u8_,
            .u16_,
            .u32_,
            .u64_,
            .usize_,
            => return true,

            .i8_,
            .i16_,
            .i32_,
            .i64_,
            .isize_,
            => return false,

            .f32_, .f64_ => return false,

            .void_ => return false,
        }
    }

    pub fn isSignedInt(self: *Type) !bool {
        switch (self.tag) {
            .u8_,
            .u16_,
            .u32_,
            .u64_,
            .usize_,
            => return false,

            .i8_,
            .i16_,
            .i32_,
            .i64_,
            .isize_,
            => return true,

            .f32_, .f64_ => return false,

            .void_ => return false,
        }
    }

    pub fn isFloat(self: *Type) !bool {
        switch (self.tag) {
            .u8_,
            .u16_,
            .u32_,
            .u64_,
            .usize_,
            => return false,

            .i8_,
            .i16_,
            .i32_,
            .i64_,
            .isize_,
            => return false,

            .f32_, .f64_ => return true,

            .void_ => return false,
        }
    }
};
