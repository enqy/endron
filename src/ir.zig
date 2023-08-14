const std = @import("std");

pub const Ir = struct {
    blocks: std.ArrayList(Block),
    exprs: std.ArrayList(Expr),
    literals: std.ArrayList(Literal),

    pub fn deinit(self: *Ir) void {
        for (self.blocks.items) |*block| {
            block.deinit();
        }
        self.blocks.deinit();
        for (self.exprs.items) |*expr| {
            expr.deinit();
        }
        self.exprs.deinit();
        self.literals.deinit();
    }

    pub fn render(self: *const Ir, writer: anytype) !void {
        try writer.writeAll("\n===== LITERALS =====\n");

        for (self.literals.items, 0..) |literal, i| {
            try writer.print("{} <- ", .{i});
            try literal.render(writer);
            try writer.writeAll("\n");
        }

        try writer.writeAll("\n===== EXPRS =====\n");

        for (self.exprs.items, 0..) |expr, i| {
            try writer.print("{} <- ", .{i});
            try expr.render(writer);
            try writer.writeAll("\n");
        }

        try writer.writeAll("\n===== BLOCKS =====\n");

        for (self.blocks.items) |block| {
            try block.render(writer);
        }
    }
};

pub const Block = struct {
    index: usize,

    parent: usize,
    ops: std.ArrayList(Op),

    ident_map: std.StringArrayHashMap(usize),

    pub fn deinit(self: *Block) void {
        self.ops.deinit();
        self.ident_map.deinit();
    }

    pub fn render(self: *const Block, writer: anytype) !void {
        try writer.print("block {} {{\n", .{self.index});
        for (self.ops.items) |op| {
            try writer.writeAll("  ");
            try op.render(writer);
            try writer.writeAll("\n");
        }
        try writer.print("}}\n", .{});
    }
};

pub const Op = struct {
    kind: Kind,
    data: Data,

    pub const Kind = enum(u8) {
        decl,
        type,
        set,
        call,
        builtin,
        branch,
        loop,
        alu,
    };

    pub const Data = union {
        decl: Decl,
        type: Type,
        set: Set,
        call: Call,
        builtin: Builtin,
        branch: Branch,
        loop: Loop,
        alu: Alu,

        pub const Decl = struct {
            cap: usize,
            type: usize,
            value: usize,
        };

        pub const Type = struct {
            cap: usize,
            args: ?ArgsExpr,
        };

        pub const Set = struct {
            cap: usize,
            args: ArgsExpr,
        };

        pub const Call = struct {
            cap: usize,
            args: ArgsExpr,
        };

        pub const Builtin = struct {
            cap: usize,
            args: ArgsExpr,
        };

        pub const Branch = struct {
            cond: usize,
            if_true: usize,
            if_false: usize,
        };

        pub const Loop = struct {
            cond: usize,
            body: usize,
            early: ?usize,
        };

        pub const Alu = struct {
            func: Func,
            args: ArgsExpr,

            pub const Func = enum(usize) {
                add,
                sub,
                mul,
                pow,
                div,
                gt,
                lt,
                eql,
            };
        };
    };

    pub fn render(self: *const Op, writer: anytype) !void {
        switch (self.kind) {
            .decl => {
                try writer.print("decl {}: {} <- {?}", .{
                    self.data.decl.cap,
                    self.data.decl.type,
                    self.data.decl.value,
                });
            },
            .type => {
                try writer.print("type {}", .{self.data.type.cap});
                if (self.data.type.args) |args| {
                    try writer.writeAll(" <-");
                    for (args.ptr..args.ptr + args.len) |i| {
                        try writer.print(" {},", .{i});
                    }
                }
            },
            .set => {
                try writer.print("set {} <-", .{self.data.set.cap});
                for (self.data.set.args.ptr..self.data.set.args.ptr + self.data.set.args.len) |i| {
                    try writer.print(" {},", .{i});
                }
            },
            .call => {
                try writer.print("call {} <-", .{self.data.call.cap});
                for (self.data.call.args.ptr..self.data.call.args.ptr + self.data.call.args.len) |i| {
                    try writer.print(" {},", .{i});
                }
            },
            .builtin => {
                try writer.print("builtin {} = ", .{self.data.builtin.cap});
                for (self.data.builtin.args.ptr..self.data.builtin.args.ptr + self.data.builtin.args.len) |i| {
                    try writer.print(" {},", .{i});
                }
            },
            .branch => {
                try writer.print("branch {} ? {} : {}", .{
                    self.data.branch.cond,
                    self.data.branch.if_true,
                    self.data.branch.if_false,
                });
            },
            .loop => {
                try writer.print("loop {} ? {} : {?}", .{
                    self.data.loop.cond,
                    self.data.loop.body,
                    self.data.loop.early,
                });
            },
            .alu => {
                try writer.print("alu {} ->", .{self.data.alu.func});
                for (self.data.alu.args.ptr..self.data.alu.args.ptr + self.data.alu.args.len) |i| {
                    try writer.print(" {},", .{i});
                }
            },
        }
    }
};

pub const Access = struct {
    path: std.ArrayList([]const u8),

    pub fn deinit(self: *Access) void {
        self.path.deinit();
    }

    pub fn render(self: *const Access, writer: anytype) !void {
        try writer.writeAll("access: ");
        for (self.path.items) |part| {
            try writer.writeAll(".");
            try writer.writeAll(part);
        }
    }
};

pub const Expr = union(enum) {
    literal: usize,
    block: usize,
    cap: usize,
    builtin: usize,
    access: Access,
    nil: void,

    pub fn deinit(self: *Expr) void {
        switch (self.*) {
            .access => self.access.deinit(),
            else => {},
        }
    }

    pub fn render(self: *const Expr, writer: anytype) !void {
        switch (self.*) {
            .literal => try writer.print("literal: {}", .{self.literal}),
            .block => try writer.print("block: {}", .{self.block}),
            .cap => try writer.print("cap: {}", .{self.cap}),
            .builtin => try writer.print("builtin: {}", .{self.builtin}),
            .access => try self.access.render(writer),
            .nil => try writer.writeAll("nil"),
        }
    }
};

pub const ArgsExpr = struct {
    ptr: usize,
    len: usize,
};

pub const Literal = union(enum) {
    string: []const u8,
    number: i64,
    decimal: f64,

    pub fn render(self: *const Literal, writer: anytype) !void {
        switch (self.*) {
            .string => try writer.print("\"{s}\"", .{self.string}),
            .number => try writer.print("{}", .{self.number}),
            .decimal => try writer.print("{}", .{self.decimal}),
        }
    }
};
