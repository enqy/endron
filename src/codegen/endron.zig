const std = @import("std");
const Allocator = std.mem.Allocator;

const ast = @import("../ast.zig");
const Tree = ast.Tree;

pub fn generate(alloc: *Allocator, tree: *Tree) anyerror![]const u8 {
    var output = std.ArrayList(u8).init(tree.gpa);
    defer output.deinit();
    const writer = output.writer();

    try genBlock(writer, 0, tree.root);

    return output.toOwnedSlice();
}

fn genBlock(writer: anytype, level: u8, block: ast.Block) anyerror!void {
    if (level != 0) try writer.writeAll("{");

    for (block.ops) |op, j| {
        if (j == 0 and level != 0) try writer.writeByte('\n');

        var i: u8 = 0;
        while (i < level) : (i += 1) try writer.writeAll("  ");

        try genOp(writer, level, op);
        try writer.writeByte('\n');
    }

    if (level >= 1) {
        var i: u8 = 0;
        while (i < level - 1) : (i += 1) try writer.writeAll("  ");
    }
    if (level != 0) try writer.writeByte('}');
}

fn genOp(writer: anytype, level: u8, op: ast.Op) anyerror!void {
    switch (op) {
        .Decl => try genDecl(writer, level, op.Decl),
        .Set => try genSet(writer, level, op.Set),
        .Call => try genCall(writer, level, op.Call),
        .BuiltinCall => try genBuiltinCall(writer, level, op.BuiltinCall),
        .MacroCall => try genMacroCall(writer, level, op.MacroCall),
        .Branch => try genBranch(writer, level, op.Branch),
        .Add => try genAdd(writer, level, op.Add),
        .Sub => try genSub(writer, level, op.Sub),
    }
}

fn genDecl(writer: anytype, level: u8, decl: ast.Op.Decl) anyerror!void {
    try writer.writeByte('$');

    try genCap(writer, level, decl.cap);

    try writer.writeAll(": ");
    try genExpr(writer, level, decl.mods);

    if (decl.value) |value| {
        try writer.writeAll(" = ");
        try genExpr(writer, level, value);
    }
}

fn genSet(writer: anytype, level: u8, set: ast.Op.Set) anyerror!void {
    try writer.writeByte('~');

    try genCap(writer, level, set.cap);

    try writer.writeAll(" = ");
    try genExpr(writer, level, set.value);
}

fn genCall(writer: anytype, level: u8, call: ast.Op.Call) anyerror!void {
    try writer.writeByte('!');

    try genCap(writer, level, call.cap);

    if (call.args) |args| try genTuple(writer, level, args);
}

fn genBuiltinCall(writer: anytype, level: u8, call: ast.Op.BuiltinCall) anyerror!void {
    try writer.writeByte('@');

    try genCap(writer, level, call.cap);

    if (call.args) |args| try genTuple(writer, level, args);
}

fn genMacroCall(writer: anytype, level: u8, call: ast.Op.MacroCall) anyerror!void {
    try writer.writeByte('%');

    try genCap(writer, level, call.cap);

    if (call.args) |args| try genTuple(writer, level, args);
}

fn genBranch(writer: anytype, level: u8, branch: ast.Op.Branch) anyerror!void {
    try writer.writeByte('^');

    try genCap(writer, level, branch.cap);

    try genTuple(writer, level, branch.args);
}

fn genAdd(writer: anytype, level: u8, add: ast.Op.Add) anyerror!void {
    try writer.writeAll("#+");

    try genTuple(writer, level, add.args);
}

fn genSub(writer: anytype, level: u8, sub: ast.Op.Sub) anyerror!void {
    try writer.writeAll("#-");

    try genTuple(writer, level, sub.args);
}

fn genArray(writer: anytype, level: u8, array: ast.Array) anyerror!void {
    try writer.writeByte('[');

    for (array.items) |item, i| {
        try genExpr(writer, level, item);
        if (i != array.items.len - 1) try writer.writeAll(", ");
    }

    try writer.writeByte(']');
}

fn genTuple(writer: anytype, level: u8, tuple: ast.Tuple) anyerror!void {
    try writer.writeByte('(');

    for (tuple.items) |item, i| {
        try genExpr(writer, level, item);
        if (i != tuple.items.len - 1) try writer.writeAll(", ");
    }

    try writer.writeByte(')');
}

fn genMap(writer: anytype, level: u8, map: ast.Map) anyerror!void {
    try writer.writeByte('<');

    for (map.entries) |entry, i| {
        try writer.writeAll(entry.key);
        try writer.writeByte(':');
        try genExpr(writer, level, entry.value);
        if (i != map.entries.len - 1) try writer.writeAll(", ");
    }

    try writer.writeByte('>');
}

fn genExpr(writer: anytype, level: u8, expr: *ast.Expr) anyerror!void {
    switch (expr.expr) {
        .Literal => {
            switch (expr.expr.Literal) {
                .Integer => try writer.print("{}", .{expr.expr.Literal.Integer}),
                .Float => try writer.print("{d}", .{expr.expr.Literal.Float}),
                .String => try writer.writeAll(expr.expr.Literal.String),
            }
        },
        .Ident => try writer.writeAll(expr.expr.Ident),
        .Op => try genOp(writer, level, expr.expr.Op),
        .Array => try genArray(writer, level, expr.expr.Array),
        .Tuple => try genTuple(writer, level, expr.expr.Tuple),
        .Map => try genMap(writer, level, expr.expr.Map),
        .Block => try genBlock(writer, level + 1, expr.expr.Block),
        .Scope => {
            if (expr.expr.Scope.lhs) |lhs| if (lhs.expr != .Scope) try genExpr(writer, level, lhs) else unreachable;
            try writer.writeByte('.');
            try genExpr(writer, level, expr.expr.Scope.rhs);
        },
    }
}

fn genCap(writer: anytype, level: u8, cap: *ast.Cap) anyerror!void {
    switch (cap.*) {
        .Ident => try writer.writeAll(cap.Ident),
        .Scope => {
            if (cap.Scope.lhs) |lhs| if (lhs.* == .Ident) try writer.writeAll(lhs.Ident) else unreachable else try writer.writeByte('.');
            
            switch (cap.Scope.rhs.*) {
                .Ident => try writer.writeAll(cap.Scope.rhs.Ident),
                .Scope => try genCap(writer, level, cap.Scope.rhs),
            }
        }
    }
}