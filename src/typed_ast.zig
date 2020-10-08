const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Ident = []const u8;

pub const Decl = struct {
    cap: Ident,
    mods: u2,
    type_id: TypeId,

    value: Expr,
};

pub const Expr = union(enum) {
    Ident: Ident,
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
