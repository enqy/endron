const std = @import("std");
const Allocator = std.mem.Allocator;

const tk = @import("tokenizer.zig");
const Token = tk.Token;

pub const Tree = struct {
    tokens: []const Token,
    source: []const u8,

    arena: std.heap.ArenaAllocator.State,
    gpa: *Allocator,

    types: std.StringArrayHashMap(Type),

    root: Block,

    pub fn deinit(self: *Tree) void {
        self.types.deinit();
        self.gpa.free(self.tokens);
        self.arena.promote(self.gpa).deinit();
    }
};

pub const Block = struct {
    ops: []Op,

    pub fn render(block: Block, writer: anytype) !void {
        for (block.ops) |op| try op.render(writer);
    }
};

pub const Scope = struct {
    lhs: ?*Expr,
    rhs: *Expr,
};

pub const Op = union(enum) {
    pub const Decl = struct {
        cap: *Cap,
        mods: ?*Expr,
        type_id: TypeId,

        value: ?*Expr,
    };

    pub const Set = struct {
        cap: *Cap,
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

    // Binary Ops
    pub const Add = struct {
        args: Tuple,
    };

    pub const Sub = struct {
        args: Tuple,
    };

    // Op union
    Decl: Decl,
    Set: Set,
    Call: Call,
    BuiltinCall: BuiltinCall,
    MacroCall: MacroCall,
    Branch: Branch,

    Add: Add,
    Sub: Sub,

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

pub const Array = struct {
    items: []*Expr,
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
    Array: Array,
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
