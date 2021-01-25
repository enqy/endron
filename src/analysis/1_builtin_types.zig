const std = @import("std");
const Allocator = std.mem.Allocator;

const ast = @import("../ast.zig");
const Tree = ast.Tree;

pub fn pass(alloc: *Allocator, tree: *Tree) anyerror!void {
    try passBlock(alloc, tree, &tree.root);
}

pub fn passBlock(alloc: *Allocator, tree: *Tree, block: *ast.Block) anyerror!void {
    for (block.ops) |*op| try passOp(alloc, tree, op);
}

pub fn passOp(alloc: *Allocator, tree: *Tree, op: *ast.Op) anyerror!void {
    switch (op.*) {
        .Decl => try passDecl(alloc, tree, &op.Decl),
        else => {},
    }
}

pub fn passDecl(alloc: *Allocator, tree: *Tree, decl: *ast.Op.Decl) anyerror!void {
    switch (decl.mods.expr) {
        .Op => |op| {
            if (op == .BuiltinCall) {
                if (op.BuiltinCall.cap.* != .Ident) @panic("expected single ident as cap");
                // switch on builtin cap
                if (std.mem.eql(u8, op.BuiltinCall.cap.Ident, "fn")) {
                    try tree.types.put(decl.cap.Ident, .{
                        .tag = .fn_,
                        .payload = .{
                            .Fn = .{
                                .ret_type_id = tree.types.getIndex(op.BuiltinCall.args.?.items[1].expr.Ident).?,
                            },
                        }
                    });
                } else if (std.mem.eql(u8, op.BuiltinCall.cap.Ident, "struct")) {
                    try tree.types.put(decl.cap.Ident, .{
                        .tag = .struct_,
                        .payload = .{
                            .Struct = .{},
                        }
                    });
                }
                decl.type_id = tree.types.items().len - 1;
            }
        },
        else => {},
    }
    
    if (decl.value) |expr| try passExpr(alloc, tree, expr);
}

pub fn passExpr(alloc: *Allocator, tree: *Tree, expr: *ast.Expr) anyerror!void {
    switch (expr.expr) {
        else => {},
    }
}
