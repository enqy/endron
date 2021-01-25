const std = @import("std");
const Allocator = std.mem.Allocator;

const ast = @import("../ast.zig");
const Tree = ast.Tree;

pub fn generate(alloc: *Allocator, tree: *Tree) ![]const u8 {
    var output = std.ArrayList(u8).init(tree.gpa);
    defer output.deinit();
    const writer = output.writer();

    try writer.writeAll(
        \\#include <stdint.h>
        \\#include <stdio.h>
        \\
        \\
    );

    try genRoot(writer, tree, tree.root);

    return output.toOwnedSlice();
}

fn genRoot(writer: anytype, tree: *Tree, block: ast.Block) anyerror!void {
    for (block.ops) |op, j| {
        switch (op) {
            .Decl => try genDecl(writer, tree, 0, op.Decl),
            else => {},
        }
        try writer.writeByte('\n');
    }
}

fn genFn(writer: anytype, tree: *Tree, level: u8, decl: ast.Op.Decl) anyerror!void {
    
}

fn genDecl(writer: anytype, tree: *Tree, level: u8, decl: ast.Op.Decl) anyerror!void {
    if (tree.types.items()[decl.type_id].value.isFn()) {
        try genType(writer, tree, tree.types.items()[decl.type_id].value.payload.Fn.ret_type_id);
        try writer.writeByte(' ');
        try genCap(writer, tree, level, decl.cap);

        try writer.writeByte('(');
        try writer.writeByte(')');

        try writer.writeByte(' ');
        try writer.writeByte('{');
        try writer.writeAll("\n   return y;\n");
        try writer.writeByte('}');
    } else {
        try genType(writer, tree, decl.type_id);
        if (tree.types.items()[decl.type_id].value.isArray()) try writer.writeAll("*");
        try writer.writeByte(' ');
        try genCap(writer, tree, level, decl.cap);

        if (decl.value) |expr| {
            try writer.writeAll(" = ");
            try genExpr(writer, tree, level, expr);
        }

        try writer.writeByte(';');
    }
}

fn genExpr(writer: anytype, tree: *Tree, level: u8, expr: *ast.Expr) anyerror!void {
    switch (expr.expr) {
        .Literal => {
            switch (expr.expr.Literal) {
                .Integer => try writer.print("{}", .{expr.expr.Literal.Integer}),
                .Float => try writer.print("{d}", .{expr.expr.Literal.Float}),
                .String => try writer.writeAll(expr.expr.Literal.String),
            }
        },
        else => {},
    }
}

fn genCap(writer: anytype, tree: *Tree, level: u8, cap: *ast.Cap) anyerror!void {
    switch (cap.*) {
        .Ident => try writer.writeAll(cap.Ident),
        .Scope => {
            if (cap.Scope.lhs) |lhs| if (lhs.* == .Ident) try writer.writeAll(lhs.Ident) else unreachable else try writer.writeByte('.');
            
            switch (cap.Scope.rhs.*) {
                .Ident => try writer.writeAll(cap.Scope.rhs.Ident),
                .Scope => try genCap(writer, tree, level, cap.Scope.rhs),
            }
        }
    }
}

fn genType(writer: anytype, tree: *Tree, type_id: usize) anyerror!void {
    switch (tree.types.items()[type_id].value.tag) {
        .invalid_ => @panic("invalid type"),
        .void_ => try writer.writeAll("void"),
        .u8_ => try writer.writeAll("uint8_t"),
        .u16_ => try writer.writeAll("uint16_t"),
        .u32_ => try writer.writeAll("uint32_t"),
        .u64_ => try writer.writeAll("uint64_t"),
        .usize_ => try writer.writeAll("uintptr_t"),
        .i8_ => try writer.writeAll("int8_t"),
        .i16_ => try writer.writeAll("int16_t"),
        .i32_ => try writer.writeAll("int32_t"),
        .i64_ => try writer.writeAll("int64_t"),
        .isize_ => try writer.writeAll("intptr_t"),
        .f32_ => try writer.writeAll("float"),
        .f64_ => try writer.writeAll("double"),
        .str_ => try writer.writeAll("char"),

        else => {},
    }
}