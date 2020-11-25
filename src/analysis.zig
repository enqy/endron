const std = @import("std");
const Allocator = std.mem.Allocator;

const ast = @import("ast.zig");
const Tree = ast.Tree;
const Node = ast.Node;

const Pass = fn (*Allocator, *const Tree, *State) anyerror!void;
const Passes = [_]Pass{
    @import("analysis/0_typing.zig").pass,
};

pub fn analyze(tree: *const Tree) !void {
    var arena = std.heap.ArenaAllocator.init(tree.gpa);
    defer arena.deinit();

    var state = try State.init(tree.gpa);
    defer state.deinit();

    for (Passes) |pass| {
        try pass(&arena.allocator, tree, &state);
    }
}

pub const State = struct {
    pub const Type = struct {
        pub const Kind = enum {
            void,
            u8,
            u16,
            u32,
            u64,
            i8,
            i16,
            i32,
            i64,
            f32,
            f64,
            bool,
        };
        kind: Kind,
    };
    pub const TypeId = usize;

    types: std.ArrayList(Type),
    type_map: std.StringHashMap(TypeId),

    pub fn init(gpa: *Allocator) !State {
        var state = State{
            .types = std.ArrayList(Type).init(gpa),
            .type_map = std.StringHashMap(TypeId).init(gpa),
        };

        try state.initBuiltinTypes();

        return state;
    }

    pub fn deinit(state: *State) void {
        state.types.deinit();
        state.type_map.deinit();
    }

    pub fn initBuiltinTypes(state: *State) !void {
        try state.registerType("void", .{
            .kind = .void,
        });
        try state.registerType("u8", .{
            .kind = .u8,
        });
        try state.registerType("u16", .{
            .kind = .u16,
        });
        try state.registerType("u32", .{
            .kind = .u32,
        });
        try state.registerType("u64", .{
            .kind = .u64,
        });
        try state.registerType("i8", .{
            .kind = .i8,
        });
        try state.registerType("i16", .{
            .kind = .i16,
        });
        try state.registerType("i32", .{
            .kind = .i32,
        });
        try state.registerType("i64", .{
            .kind = .i64,
        });
        try state.registerType("f32", .{
            .kind = .f32,
        });
        try state.registerType("f64", .{
            .kind = .f64,
        });
        try state.registerType("bool", .{
            .kind = .bool,
        });
    }

    fn registerType(state: *State, name: []const u8, t: Type) !void {
        try state.types.append(t);
        try state.type_map.put(name, state.types.items.len - 1);
    }
};
