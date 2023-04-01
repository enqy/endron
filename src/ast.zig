const std = @import("std");
const Allocator = std.mem.Allocator;

const tokenizer = @import("tokenizer.zig");
const Token = tokenizer.Token;

pub const Tree = struct {
    alloc: Allocator,
    arena: std.heap.ArenaAllocator.State,

    source: []const u8,
    tokens: []const Token,

    root: Block,

    pub fn deinit(self: *Tree) void {
        self.arena.promote(self.alloc).deinit();
    }
};

pub const Block = struct {
    ops: []const Op,

    pub fn render(self: *const Block, writer: anytype, level: usize) anyerror!void {
        for (self.ops) |op| {
            try renderIndent(writer, level);
            try op.render(writer, level);
            if (level == 0) {
                try writer.writeAll("\n");
            }
        }
    }
};

pub const Scope = struct {
    root: i64,
    upper: usize,
    path: []const Ident,

    pub fn render(self: *const Scope, writer: anytype, level: usize) !void {
        _ = level;
        if (self.root == -1) {
            try writer.writeAll("_");
        } else if (self.root == 0) {
            try writer.writeAll("^");
        }

        var j: i64 = 0;
        while (j < self.upper) : (j += 1) {
            try writer.writeAll(".");
        }

        for (self.path) |ident| {
            try writer.writeAll(".");
            try writer.writeAll(ident);
        }
    }
};

pub const Op = union(enum) {
    pub const Decl = struct {
        cap: *Expr,
        type: *Expr,
        value: ?*Expr,
    };

    pub const Type = struct {
        cap: *Expr,
        args: ?[]const *Expr,
    };

    pub const Set = struct {
        cap: *Expr,
        args: []const *Expr,
    };

    pub const Call = struct {
        cap: *Expr,
        args: []const *Expr,
    };

    pub const Builtin = struct {
        cap: *Expr,
        args: []const *Expr,
    };

    pub const Branch = struct {
        cond: *Expr,
        if_true: *Expr,
        if_false: *Expr,
    };

    pub const Loop = struct {
        cond: *Expr,
        body: *Expr,
        early: ?*Expr,
    };

    pub const Alu = struct {
        pub const Func = enum {
            add,
            sub,
            mul,
            pow,
            div,
            gt,
            lt,
            eql,
        };

        func: Func,
        args: []const *Expr,
    };

    decl: Decl,
    type: Type,
    set: Set,
    call: Call,
    builtin: Builtin,
    branch: Branch,
    loop: Loop,
    alu: Alu,

    pub fn render(self: *const Op, writer: anytype, level: usize) !void {
        switch (self.*) {
            .decl => |op| {
                try writer.writeAll("Decl:\n");
                try op.cap.render(writer, level + 1);
                try writer.writeAll(" <\n");
                try op.type.render(writer, level + 2);
                try writer.writeAll("\n");
                try renderIndent(writer, level + 1);
                try writer.writeAll(">");
                if (op.value) |value| {
                    try writer.writeAll(" =\n");
                    try value.render(writer, level + 2);
                }
            },
            .type => |op| {
                try writer.writeAll("Type:\n");
                try op.cap.render(writer, level + 1);
                try writer.writeAll(" <");
                if (op.args) |args| {
                    try writer.writeAll("\n");
                    for (args) |arg| {
                        try arg.render(writer, level + 2);
                        try writer.writeAll("\n");
                    }
                    try renderIndent(writer, level + 1);
                }
                try writer.writeAll(">");
            },
            .set => |op| {
                try writer.writeAll("Set:\n");
                try op.cap.render(writer, level + 1);
                try writer.writeAll(" =\n");
                for (op.args) |arg| {
                    try arg.render(writer, level + 2);
                }
            },
            .call => |op| {
                try writer.writeAll("Call:\n");
                try op.cap.render(writer, level + 1);
                try writer.writeAll("(\n");
                for (op.args) |arg| {
                    try arg.render(writer, level + 2);
                    try writer.writeAll("\n");
                }
                try renderIndent(writer, level + 1);
                try writer.writeAll(")");
            },
            .builtin => |op| {
                try writer.writeAll("Builtin:\n");
                try op.cap.render(writer, level + 1);
                try writer.writeAll("(\n");
                for (op.args) |arg| {
                    try arg.render(writer, level + 2);
                    try writer.writeAll("\n");
                }
                try renderIndent(writer, level + 1);
                try writer.writeAll(")");
            },
            .branch => |op| {
                try writer.writeAll("Branch:\n");
                try op.cond.render(writer, level + 1);
                try writer.writeAll("\n");
                try renderIndent(writer, level + 2);
                try writer.writeAll("then:\n");
                try op.if_true.render(writer, level + 3);
                try writer.writeAll("\n");
                try renderIndent(writer, level + 2);
                try writer.writeAll("else:\n");
                try op.if_false.render(writer, level + 3);
            },
            .loop => |op| {
                try writer.writeAll("Loop:\n");
                try op.cond.render(writer, level + 1);
                try writer.writeAll("\n");
                try renderIndent(writer, level + 2);
                try writer.writeAll("body:\n");
                try op.body.render(writer, level + 3);
                if (op.early) |early| {
                    try writer.writeAll("\n");
                    try renderIndent(writer, level + 2);
                    try writer.writeAll("early:\n");
                    try early.render(writer, level + 3);
                }
            },
            .alu => |op| {
                try writer.writeAll("Alu:\n");
                try renderIndent(writer, level + 1);
                switch (op.func) {
                    .add => try writer.writeAll("add"),
                    .sub => try writer.writeAll("sub"),
                    .mul => try writer.writeAll("mul"),
                    .pow => try writer.writeAll("pow"),
                    .div => try writer.writeAll("div"),
                    .gt => try writer.writeAll("gt"),
                    .lt => try writer.writeAll("lt"),
                    .eql => try writer.writeAll("eql"),
                }
                try writer.writeAll("(\n");
                for (op.args) |arg| {
                    try arg.render(writer, level + 2);
                    try writer.writeAll("\n");
                }
                try renderIndent(writer, level + 1);
                try writer.writeAll(")");
            },
        }
        try writer.writeAll("\n");
    }
};

pub const Expr = struct {
    pub const Inner = union(enum) {
        ident: Ident,
        literal: Literal,
        block: Block,
        scope: Scope,
    };

    expr: Inner,

    pub fn render(self: *const Expr, writer: anytype, level: usize) !void {
        try renderIndent(writer, level);
        switch (self.expr) {
            .ident => |expr| {
                try writer.print("{s}", .{expr});
            },
            .literal => |expr| {
                try expr.render(writer, level);
            },
            .block => |expr| {
                try writer.writeAll("{\n");
                try expr.render(writer, level + 1);
                try renderIndent(writer, level);
                try writer.writeAll("}");
            },
            .scope => |expr| {
                try expr.render(writer, level);
            },
        }
    }
};

pub const Ident = []const u8;

pub const Literal = union(enum) {
    string: []const u8,
    number: i64,
    decimal: f64,

    pub fn render(self: *const Literal, writer: anytype, level: usize) !void {
        _ = level;
        switch (self.*) {
            .string => |lit| {
                try writer.writeByte('"');
                try writer.writeAll(lit);
                try writer.writeByte('"');
            },
            .number => |lit| {
                try writer.print("{}", .{lit});
            },
            .decimal => |lit| {
                try writer.print("{}", .{lit});
            },
        }
    }
};

fn renderIndent(writer: anytype, level: usize) !void {
    var i: usize = 0;
    while (i < level) : (i += 1) {
        try writer.writeAll("  ");
    }
}
