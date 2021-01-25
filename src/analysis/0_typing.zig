const std = @import("std");
const Allocator = std.mem.Allocator;

const ast = @import("../ast.zig");
const Tree = ast.Tree;

pub fn pass(alloc: *Allocator, tree: *Tree) anyerror!void {
    try initBuiltinTypes(tree);

    try typeBlock(alloc, tree, &tree.root);
}

pub fn typeBlock(alloc: *Allocator, tree: *Tree, block: *ast.Block) anyerror!void {
    for (block.ops) |*op| try typeOp(alloc, tree, op);
}

pub fn typeOp(alloc: *Allocator, tree: *Tree, op: *ast.Op) anyerror!void {
    switch (op.*) {
        .Decl => try typeDecl(alloc, tree, &op.Decl),
        else => {},
    }
}

pub fn typeDecl(alloc: *Allocator, tree: *Tree, decl: *ast.Op.Decl) anyerror!void {
    if (decl.type_id != 0) @panic("already has type");
    switch (decl.mods.expr) {
        .Ident => {
            if (tree.types.getIndex(decl.mods.expr.Ident)) |id| {
                decl.type_id = id;
            }
        },
        .Tuple => {
            for (decl.mods.expr.Tuple.items) |item| {
                if (item.expr == .Ident) {
                    if (tree.types.getIndex(item.expr.Ident)) |id| {
                        if (decl.type_id != 0) @panic("already has type");
                        decl.type_id = id;
                    }
                }
            }
        },
        else => {},
    }
    
    if (decl.value) |expr| try typeExpr(alloc, tree, expr);
}

pub fn typeExpr(alloc: *Allocator, tree: *Tree, expr: *ast.Expr) anyerror!void {
    switch (expr.expr) {
        .Literal => {
            switch (expr.expr.Literal) {
                .Integer => expr.type_id = tree.types.getIndex("i64").?,
                .Float => expr.type_id = tree.types.getIndex("f64").?,
                .String => expr.type_id = tree.types.getIndex("str").?,
            }
        },
        else => {},
    }
}

pub fn initBuiltinTypes(tree: *Tree) !void {
    try tree.types.put("invalid", .{
        .tag = .invalid_,
    });
    try tree.types.put("void", .{
        .tag = .void_,
    });
    try tree.types.put("u8", .{
        .tag = .u8_,
    });
    try tree.types.put("u16", .{
        .tag = .u16_,
    });
    try tree.types.put("u32", .{
        .tag = .u32_,
    });
    try tree.types.put("u64", .{
        .tag = .u64_,
    });
    try tree.types.put("usize", .{
        .tag = .usize_,
    });
    try tree.types.put("i8", .{
        .tag = .i8_,
    });
    try tree.types.put("i16", .{
        .tag = .i16_,
    });
    try tree.types.put("i32", .{
        .tag = .i32_,
    });
    try tree.types.put("i64", .{
        .tag = .i64_,
    });
    try tree.types.put("isize", .{
        .tag = .isize_,
    });
    try tree.types.put("f32", .{
        .tag = .f32_,
    });
    try tree.types.put("f64", .{
        .tag = .f64_,
    });
    try tree.types.put("str", .{
        .tag = .str_,
    });
}