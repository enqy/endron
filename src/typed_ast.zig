const std = @import("std");
const Allocator = std.mem.Allocator;

const ast = @import("ast.zig");
const Tree = ast.Tree;
const Node = ast.Node;

pub const Module = struct {
    types: std.ArrayList(Type),
    type_map: std.StringHashMap(TypeId),

    insts: std.ArrayList(Inst),

    pub fn transform(arena: *Allocator, tree: *const Tree) !Module {
        var mod = Module{
            .types = std.ArrayList(Type).init(arena),
            .type_map = std.StringHashMap(TypeId).init(arena),

            .insts = std.ArrayList(Inst).init(arena),
        };

        if (tree.root.kind != .Block) @panic("Expected Block Node");
        var troot = @fieldParentPtr(Node.Block, "base", tree.root);
        for (troot.nodes) |node| {
            switch (node.kind) {
                .Decl => {
                    const n = @fieldParentPtr(Node.Decl, "base", node);
                    if (n.cap.kind != .Ident) @panic("Expected Ident Node for Decl Node Cap");
                    const cap = @fieldParentPtr(Node.Ident, "base", n.cap);

                    const value: ?Expr = blk: {
                        if (n.value) |val| {
                            switch (val.kind) {
                                .Literal => {
                                    const valn = @fieldParentPtr(Node.Literal, "base", val);
                                    switch (tree.tokens[valn.tok].kind) {
                                        .LiteralInteger => {
                                            break :blk Expr{ .Literal = .{ .Integer = try std.fmt.parseInt(i64, tree.getTokSource(valn.tok), 10) } };
                                        },
                                        else => @panic("not implemented"),
                                    }
                                },
                                else => @panic("not implemented"),
                            }
                        } else break :blk null;
                    };

                    try mod.insts.append(.{
                        .Decl = .{
                            .cap = tree.getTokSource(cap.tok),
                            .mods = 0,
                            .type_id = 0,

                            .value = value,
                        },
                    });
                },
                .Assign => {
                    const n = @fieldParentPtr(Node.Assign, "base", node);
                    if (n.cap.kind != .Ident) @panic("Expected Ident Node for Assign Node Cap");
                    const cap = @fieldParentPtr(Node.Ident, "base", n.cap);

                    const value: Expr = blk: {
                        switch (n.value.kind) {
                            .Literal => {
                                const valn = @fieldParentPtr(Node.Literal, "base", n.value);
                                switch (tree.tokens[valn.tok].kind) {
                                    .LiteralInteger => {
                                        break :blk Expr{ .Literal = .{ .Integer = try std.fmt.parseInt(i64, tree.getTokSource(valn.tok), 10) } };
                                    },
                                    else => @panic("not implemented"),
                                }
                            },
                            else => @panic("not implemented"),
                        }
                    };

                    try mod.insts.append(.{
                        .Assign = .{
                            .cap = tree.getTokSource(cap.tok),
                            .mods = 0,
                            .type_id = 0,

                            .value = value,
                        },
                    });
                },
                else => @panic("Expected Decl or Assign Node"),
            }
        }

        for (mod.insts.items) |inst| {
            try inst.render(std.io.getStdOut().writer());
        }

        return mod;
    }
};

pub const Inst = union(enum) {
    pub const Decl = struct {
        cap: Ident,
        mods: u2,
        type_id: TypeId,

        value: ?Expr,
    };

    pub const Assign = struct {
        cap: Ident,
        mods: u2,
        type_id: TypeId,

        value: Expr,
    };

    Decl: Decl,
    Assign: Assign,

    pub fn render(inst: Inst, writer: anytype) anyerror!void {
        switch (inst) {
            .Decl => |is| {
                _ = try writer.writeAll("Decl: ");
                _ = try writer.print("{}", .{is});
            },
            .Assign => |is| {
                _ = try writer.writeAll("Assign: ");
                _ = try writer.print("{}", .{is});
            },
        }
        _ = try writer.writeAll("\n");
    }
};

pub const Ident = []const u8;

pub const Literal = union(enum) {
    Integer: i64,
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
