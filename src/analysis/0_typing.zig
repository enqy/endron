const std = @import("std");
const Allocator = std.mem.Allocator;

const State = @import("../analysis.zig").State;
const Tree = @import("../ast.zig").Tree;

pub fn pass(arena: *Allocator, tree: *const Tree, state: *State) !void {

}