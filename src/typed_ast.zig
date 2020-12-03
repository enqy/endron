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
                .Call => try block.ops.append(.{ .Call = try ttree.transCall(tree, nn) }),
                .BuiltinCall => try block.ops.append(.{ .BuiltinCall = try ttree.transBuiltinCall(tree, nn) }),
                .MacroCall => try block.ops.append(.{ .MacroCall = try ttree.transMacroCall(tree, nn) }),
                .Branch => try block.ops.append(.{ .Branch = try ttree.transBranch(tree, nn) }),
                else => @panic("expected an inst node"),
            }
        }

        return block;
    }

    fn transDecl(ttree: *TypedTree, tree: *const Tree, node: *Node) anyerror!Op.Decl {
        const n = @fieldParentPtr(Node.Decl, "base", node);
        const cap = try ttree.transCap(tree, n.cap);

        if (n.mods) |mods| {
            const value = if (n.value) |val| try ttree.transExpr(tree, val) else null;

            return Op.Decl{
                .cap = cap,
                .mods = 0,
                .type_id = 0,

                .value = value,
            };
        } else {
            const value = if (n.value) |val| try ttree.transExpr(tree, val) else unreachable;

            return Op.Decl{
                .cap = cap,
                .mods = 0,
                .type_id = 0,

                .value = value,
            };
        }
    }

    fn transSet(ttree: *TypedTree, tree: *const Tree, node: *Node) anyerror!Op.Set {
        const n = @fieldParentPtr(Node.Set, "base", node);
        const cap = try ttree.transCap(tree, n.cap);

        const value = try ttree.transExpr(tree, n.value);

        return Op.Set{
            .cap = cap,
            .mods = 0,
            .type_id = 0,

            .value = value,
        };
    }

    fn transCall(ttree: *TypedTree, tree: *const Tree, node: *Node) anyerror!Op.Call {
        const n = @fieldParentPtr(Node.Call, "base", node);

        const cap = try ttree.transCap(tree, n.cap);
        if (n.args) |a| {
            const args = try ttree.transTuple(tree, a);

            return Op.Call{
                .cap = cap,

                .args = args,
            };
        } else {
            return Op.Call{
                .cap = cap,

                .args = null,
            };
        }
    }

    fn transBuiltinCall(ttree: *TypedTree, tree: *const Tree, node: *Node) anyerror!Op.BuiltinCall {
        const n = @fieldParentPtr(Node.BuiltinCall, "base", node);

        const cap = try ttree.transCap(tree, n.cap);
        if (n.args) |a| {
            const args = try ttree.transTuple(tree, a);

            return Op.BuiltinCall{
                .cap = cap,

                .args = args,
            };
        } else {
            return Op.BuiltinCall{
                .cap = cap,

                .args = null,
            };
        }
    }

    fn transMacroCall(ttree: *TypedTree, tree: *const Tree, node: *Node) anyerror!Op.MacroCall {
        const n = @fieldParentPtr(Node.MacroCall, "base", node);

        const cap = try ttree.transCap(tree, n.cap);
        if (n.args) |a| {
            const args = try ttree.transTuple(tree, a);

            return Op.MacroCall{
                .cap = cap,

                .args = args,
            };
        } else {
            return Op.MacroCall{
                .cap = cap,

                .args = null,
            };
        }
    }

    fn transBranch(ttree: *TypedTree, tree: *const Tree, node: *Node) anyerror!Op.Branch {
        const n = @fieldParentPtr(Node.Branch, "base", node);

        const cap = try ttree.transCap(tree, n.cap);
        const args = try ttree.transTuple(tree, n.args);

        return Op.Branch{
            .cap = cap,

            .args = args,
        };
    }

    fn transCap(ttree: *TypedTree, tree: *const Tree, node: *Node) anyerror!*Cap {
        const cap = try ttree.arena.create(Cap);
        switch (node.kind) {
            .Ident => {
                const n = @fieldParentPtr(Node.Ident, "base", node);
                cap.* = .{ .Ident = tree.getTokSource(n.tok) };
            },
            .Scope => {
                const n = @fieldParentPtr(Node.Scope, "base", node);
                cap.* = .{
                    .Scope = .{
                        .lhs = if (n.lhs) |lhs| try ttree.transCap(tree, lhs) else null,
                        .rhs = try ttree.transCap(tree, n.rhs),
                    },
                };
            },
            else => @panic("expected ident or scope node for node cap"),
        }
        return cap;
    }

    fn transTuple(ttree: *TypedTree, tree: *const Tree, node: *Node) anyerror!Tuple {
        const n = @fieldParentPtr(Node.Tuple, "base", node);

        var items = std.ArrayList(*Expr).init(ttree.arena);
        for (n.nodes) |i| try items.append(try ttree.transExpr(tree, i));

        return Tuple{
            .items = items.toOwnedSlice(),
        };
    }

    fn transMap(ttree: *TypedTree, tree: *const Tree, node: *Node) anyerror!Map {
        const n = @fieldParentPtr(Node.Map, "base", node);

        var entries = std.ArrayList(MapEntry).init(ttree.arena);
        for (n.nodes) |nod| {
            const e = @fieldParentPtr(Node.MapEntry, "base", nod);
            try entries.append(.{
                .key = tree.getTokSource(@fieldParentPtr(Node.Ident, "base", e.key).tok),
                .value = try ttree.transExpr(tree, e.value),
            });
        }

        return Map{
            .entries = entries.toOwnedSlice(),
        };
    }

    fn transExpr(ttree: *TypedTree, tree: *const Tree, node: *Node) anyerror!*Expr {
        const expr = try ttree.arena.create(Expr);
        switch (node.kind) {
            .Literal => {
                const n = @fieldParentPtr(Node.Literal, "base", node);
                switch (tree.tokens[n.tok].kind) {
                    .LiteralInteger => {
                        expr.* = .{
                            .Literal = .{ .Integer = try std.fmt.parseInt(i64, tree.getTokSource(n.tok), 10) },
                        };
                    },
                    .LiteralFloat => {
                        expr.* = .{
                            .Literal = .{ .Float = try std.fmt.parseFloat(f64, tree.getTokSource(n.tok)) },
                        };
                    },
                    .LiteralString => {
                        expr.* = .{
                            .Literal = .{ .String = tree.getTokSource(n.tok) },
                        };
                    },
                    else => @panic("not implemented"),
                }
            },
            .Ident => {
                const n = @fieldParentPtr(Node.Ident, "base", node);
                expr.* = .{ .Ident = tree.getTokSource(n.tok) };
            },
            .Call => {
                expr.* = .{
                    .Op = .{ .Call = try ttree.transCall(tree, node) },
                };
            },
            .BuiltinCall => {
                expr.* = .{
                    .Op = .{ .BuiltinCall = try ttree.transBuiltinCall(tree, node) },
                };
            },
            .MacroCall => {
                expr.* = .{
                    .Op = .{ .MacroCall = try ttree.transMacroCall(tree, node) },
                };
            },
            .Tuple => {
                expr.* = .{
                    .Tuple = try ttree.transTuple(tree, node),
                };
            },
            .Map => {
                expr.* = .{
                    .Map = try ttree.transMap(tree, node),
                };
            },
            .Block => {
                expr.* = .{
                    .Block = try ttree.transBlock(tree, node),
                };
            },
            else => @panic("not implemented"),
        }
        return expr;
    }
};

pub const Block = struct {
    ops: std.ArrayList(Op),

    pub fn render(block: Block, writer: anytype) !void {
        for (block.ops.items) |op| try op.render(writer);
    }
};

pub const Scope = struct {
    lhs: ?*Expr,
    rhs: *Expr,
};

pub const Op = union(enum) {
    pub const Decl = struct {
        cap: *Cap,
        mods: u2,
        type_id: TypeId,

        value: ?*Expr,
    };

    pub const Set = struct {
        cap: *Cap,
        mods: u2,
        type_id: TypeId,

        value: *Expr,
    };

    pub const Call = struct {
        cap: *Cap,

        args: ?Tuple,
    };

    pub const BuiltinCall = struct {
        cap: *Cap,

        args: ?Tuple,
    };

    pub const MacroCall = struct {
        cap: *Cap,

        args: ?Tuple,
    };

    pub const Branch = struct {
        cap: *Cap,

        args: Tuple,
    };

    Decl: Decl,
    Set: Set,
    Call: Call,
    BuiltinCall: BuiltinCall,
    MacroCall: MacroCall,
    Branch: Branch,

    pub fn render(op: Op, writer: anytype) anyerror!void {
        try writer.print("{}\n", .{op});
    }
};

pub const CapScope = struct {
    lhs: ?*Cap,
    rhs: *Cap,
};

pub const Cap = union(enum) {
    Ident: Ident,
    Scope: CapScope,
};

pub const Ident = []const u8;

pub const Literal = union(enum) {
    Integer: i64,
    Float: f64,
    String: []const u8,
};

pub const Tuple = struct {
    items: []*Expr,
};

pub const Map = struct {
    entries: []MapEntry,
};

pub const MapEntry = struct {
    key: Ident,
    value: *Expr,
};

pub const Expr = union(enum) {
    Ident: Ident,
    Literal: Literal,
    Op: Op,
    Tuple: Tuple,
    Map: Map,
    Block: Block,
    Scope: Scope,
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
