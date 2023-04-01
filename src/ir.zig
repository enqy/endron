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
};

pub const ScopePart = union(enum) {
    top: void,
    arg: void,
    up: usize,
    ident: []const u8,
};

pub const Scope = struct {
    path: std.ArrayList(ScopePart),

    pub fn deinit(self: *Scope) void {
        self.path.deinit();
    }
};

pub const Expr = union(enum) {
    literal: usize,
    block: usize,
    cap: usize,
    builtin: usize,
    scope: Scope,
    nil: void,

    pub fn deinit(self: *Expr) void {
        switch (self.*) {
            .scope => self.scope.deinit(),
            else => {},
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
};
