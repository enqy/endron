const std = @import("std");
const mem = std.mem;

const pa = @import("parser.zig");

pub const BuiltinFn = fn (state: *RuntimeState, var_in: []const RuntimeState.Variable) anyerror!?RuntimeState.Variable;

pub const RuntimeState = struct {
    pub const Variable = union(pa.Parsed.Variable.Kind) {
        Integer: i64,
        Number: f64,
        String: []const u8,
        Bool: bool,

        Void: void,

        Block: Block,
    };

    pub const Block = struct {
        variables: std.StringHashMap(Variable),
        block: pa.Parsed.Block,

        fn init(allocator: *mem.Allocator) Block {
            return Block{
                .variables = std.StringHashMap(Variable).init(allocator),
                .block = undefined,
            };
        }

        fn initBlock(allocator: *mem.Allocator, block: pa.Parsed.Block) Block {
            return Block{
                .variables = std.StringHashMap(Variable).init(allocator),
                .block = block,
            };
        }

        fn deinit(self: *Block) void {
            self.variables.deinit();
            self.* = undefined;
        }
    };

    allocator: *mem.Allocator,

    block: Block,

    fn init(allocator: *mem.Allocator, block: pa.Parsed.Block) RuntimeState {
        return RuntimeState{
            .allocator = allocator,

            .block = Block.initBlock(allocator, block),
        };
    }

    fn deinit(self: *RuntimeState) void {
        self.block.deinit();
        self.* = undefined;
    }
};

pub fn RuntimeBase(comptime Builtins: type) type {
    return struct {
        pub fn run(parsed: *pa.Parsed) !void {
            var allocator = &parsed.arena.allocator;

            var state = RuntimeState.init(allocator, parsed.block);
            defer state.deinit();

            _ = try runBlock(&state, &state.block, null);
        }

        fn runBlock(state: *RuntimeState, block: *RuntimeState.Block, var_in: ?[]RuntimeState.Variable) anyerror!?RuntimeState.Variable {
            const ops = block.block.operations.items;

            var i: usize = 0;
            while (i < ops.len) {
                switch (ops[i].kind) {
                    .Decl => {
                        const op = @fieldParentPtr(pa.Parsed.Operation.Decl, "base", ops[i]);

                        switch (op.kind) {
                            .Integer => for (op.decls) |decl| try block.variables.put(decl, .{ .Integer = undefined }),
                            .Number => for (op.decls) |decl| try block.variables.put(decl, .{ .Number = undefined }),
                            .String => for (op.decls) |decl| try block.variables.put(decl, .{ .String = undefined }),
                            .Bool => for (op.decls) |decl| try block.variables.put(decl, .{ .Bool = undefined }),

                            .Void => for (op.decls) |decl| try block.variables.put(decl, .{ .Void = {} }),

                            .Block => for (op.decls) |decl| try block.variables.put(decl, .{ .Block = RuntimeState.Block.init(state.allocator) }),
                        }
                    },

                    .Set => {
                        const op = @fieldParentPtr(pa.Parsed.Operation.Set, "base", ops[i]);

                        for (op.outputs) |out| {
                            if (!block.variables.contains(out.name)) std.debug.panic("Variable `{}` does not exist", .{out.name});
                            switch (op.input) {
                                .Literal => |l| switch (l) {
                                    .Integer => block.variables.getEntry(out.name).?.value = RuntimeState.Variable{ .Integer = l.Integer },
                                    .Number => block.variables.getEntry(out.name).?.value = RuntimeState.Variable{ .Number = l.Number },
                                    .String => block.variables.getEntry(out.name).?.value = RuntimeState.Variable{ .String = l.String },
                                    .Bool => block.variables.getEntry(out.name).?.value = RuntimeState.Variable{ .Bool = l.Bool },

                                    .Void => block.variables.getEntry(out.name).?.value = RuntimeState.Variable{ .Void = {} },

                                    .Block => block.variables.getEntry(out.name).?.value.Block.block = l.Block,
                                },
                                .Variable => |v| switch (block.variables.get(v.name).?) {
                                    .Integer => block.variables.getEntry(out.name).?.value = RuntimeState.Variable{ .Integer = block.variables.get(v.name).?.Integer },
                                    .Number => block.variables.getEntry(out.name).?.value = RuntimeState.Variable{ .Number = block.variables.get(v.name).?.Number },
                                    .String => block.variables.getEntry(out.name).?.value = RuntimeState.Variable{ .String = block.variables.get(v.name).?.String },
                                    .Bool => block.variables.getEntry(out.name).?.value = RuntimeState.Variable{ .Bool = block.variables.get(v.name).?.Bool },

                                    .Void => block.variables.getEntry(out.name).?.value = RuntimeState.Variable{ .Void = {} },

                                    .Block => block.variables.getEntry(out.name).?.value.Block.block = block.variables.get(v.name).?.Block.block,
                                },
                                else => std.debug.panic("Not Supported Yet!", .{}),
                            }
                        }
                    },

                    .Call => _ = try runOpCall(state, block, ops[i]),

                    else => std.debug.panic("Not Supported Yet!", .{}),
                }

                i += 1;
            }

            return block.variables.get("out");
        }

        fn runOpCall(state: *RuntimeState, block: *RuntimeState.Block, opp: *pa.Parsed.Operation) anyerror!?RuntimeState.Variable {
            const op = @fieldParentPtr(pa.Parsed.Operation.Call, "base", opp);

            var inputs = std.ArrayList(RuntimeState.Variable).init(state.allocator);
            defer inputs.deinit();
            for (op.inputs) |input| switch (input) {
                .Literal => |l| switch (l) {
                    .Integer => |d| try inputs.append(.{ .Integer = d }),
                    .Number => |d| try inputs.append(.{ .Number = d }),
                    .String => |d| try inputs.append(.{ .String = d }),
                    .Bool => |d| try inputs.append(.{ .Bool = d }),

                    .Void => try inputs.append(.{ .Void = {} }),

                    .Block => |d| try inputs.append(.{ .Block = RuntimeState.Block.initBlock(state.allocator, d) }),
                },
                .Variable => |v| {
                    if (!state.block.variables.contains(v.name)) std.debug.panic("Variable `{}` not found!", .{v.name});
                    try inputs.append(state.block.variables.get(v.name).?);
                },

                .Operation => try inputs.append((try runOpCall(state, block, input.Operation)) orelse .{ .Void = {} }),
            };

            const input_slice = inputs.toOwnedSlice();
            if (Builtins.has(op.func)) {
                return @call(.{}, Builtins.get(op.func).?, .{ state, input_slice });
            } else if (block.variables.contains(op.func) and block.variables.get(op.func).? == .Block) {
                return runBlock(state, &block.variables.getEntry(op.func).?.value.Block, null);
            } else std.debug.panic("Function Not Found: {}", .{op.func});
            state.allocator.free(input_slice);
        }
    };
}

pub const SimpleRuntime = struct {
    pub const Builtins = std.ComptimeStringMap(BuiltinFn, .{
        .{ "print", print },
        .{ "add", add },
        .{ "sub", sub },
        .{ "mul", mul },
        .{ "div", div },
    });

    fn print(state: *RuntimeState, var_in: []const RuntimeState.Variable) anyerror!?RuntimeState.Variable {
        for (var_in) |in| {
            switch (in) {
                .Integer => |d| try std.io.getStdOut().outStream().print("{d}", .{d}),
                .Number => |d| try std.io.getStdOut().outStream().print("{d}", .{d}),
                .String => |d| {
                    if (mem.eql(u8, d, "\\n")) {
                        try std.io.getStdOut().outStream().print("\n", .{});
                    } else {
                        try std.io.getStdOut().outStream().print("{}", .{d});
                    }
                },
                .Bool => |d| try std.io.getStdOut().outStream().print("{}", .{d}),

                .Void => try std.io.getStdOut().outStream().print("\n", .{}),

                else => std.debug.panic("Not Supported!", .{}),
            }
        }

        return null;
    }

    fn add(state: *RuntimeState, var_in: []const RuntimeState.Variable) anyerror!?RuntimeState.Variable {
        switch (var_in[0]) {
            .Integer => {
                var sum = RuntimeState.Variable{ .Integer = var_in[0].Integer };
                for (var_in) |in, i| {
                    if (i == 0) continue;
                    switch (in) {
                        .Integer => sum.Integer += in.Integer,
                        .Number => sum.Integer += @floatToInt(i64, in.Number),
                        else => std.debug.panic("Not Supported!", .{}),
                    }
                }
                return sum;
            },
            .Number => {
                var sum = RuntimeState.Variable{ .Number = var_in[0].Number };
                for (var_in) |in, i| {
                    if (i == 0) continue;
                    switch (in) {
                        .Integer => sum.Number += @intToFloat(f64, in.Integer),
                        .Number => sum.Number += in.Number,
                        else => std.debug.panic("Not Supported!", .{}),
                    }
                }
                return sum;
            },

            else => std.debug.panic("Not Supported!", .{}),
        }
    }

    fn sub(state: *RuntimeState, var_in: []const RuntimeState.Variable) anyerror!?RuntimeState.Variable {
        switch (var_in[0]) {
            .Integer => {
                var sum = RuntimeState.Variable{ .Integer = var_in[0].Integer };
                for (var_in) |in, i| {
                    if (i == 0) continue;
                    switch (in) {
                        .Integer => sum.Integer -= in.Integer,
                        .Number => sum.Integer -= @floatToInt(i64, in.Number),
                        else => std.debug.panic("Not Supported!", .{}),
                    }
                }
                return sum;
            },
            .Number => {
                var sum = RuntimeState.Variable{ .Number = var_in[0].Number };
                for (var_in) |in, i| {
                    if (i == 0) continue;
                    switch (in) {
                        .Integer => sum.Number -= @intToFloat(f64, in.Integer),
                        .Number => sum.Number -= in.Number,
                        else => std.debug.panic("Not Supported!", .{}),
                    }
                }
                return sum;
            },

            else => std.debug.panic("Not Supported!", .{}),
        }
    }

    fn mul(state: *RuntimeState, var_in: []const RuntimeState.Variable) anyerror!?RuntimeState.Variable {
        switch (var_in[0]) {
            .Integer => {
                var sum = RuntimeState.Variable{ .Integer = var_in[0].Integer };
                for (var_in) |in, i| {
                    if (i == 0) continue;
                    switch (in) {
                        .Integer => sum.Integer *= in.Integer,
                        .Number => sum.Integer *= @floatToInt(i64, in.Number),
                        else => std.debug.panic("Not Supported!", .{}),
                    }
                }
                return sum;
            },
            .Number => {
                var sum = RuntimeState.Variable{ .Number = var_in[0].Number };
                for (var_in) |in, i| {
                    if (i == 0) continue;
                    switch (in) {
                        .Integer => sum.Number *= @intToFloat(f64, in.Integer),
                        .Number => sum.Number *= in.Number,
                        else => std.debug.panic("Not Supported!", .{}),
                    }
                }
                return sum;
            },

            else => std.debug.panic("Not Supported!", .{}),
        }
    }

    fn div(state: *RuntimeState, var_in: []const RuntimeState.Variable) anyerror!?RuntimeState.Variable {
        switch (var_in[0]) {
            .Integer => {
                var sum = RuntimeState.Variable{ .Integer = var_in[0].Integer };
                for (var_in) |in, i| {
                    if (i == 0) continue;
                    switch (in) {
                        .Integer => sum.Integer = @divFloor(sum.Integer, in.Integer),
                        .Number => sum.Integer = @divFloor(sum.Integer, @floatToInt(i64, in.Number)),
                        else => std.debug.panic("Not Supported!", .{}),
                    }
                }
                return sum;
            },
            .Number => {
                var sum = RuntimeState.Variable{ .Number = var_in[0].Number };
                for (var_in) |in, i| {
                    if (i == 0) continue;
                    switch (in) {
                        .Integer => sum.Number /= @intToFloat(f64, in.Integer),
                        .Number => sum.Number /= in.Number,
                        else => std.debug.panic("Not Supported!", .{}),
                    }
                }
                return sum;
            },

            else => std.debug.panic("Not Supported!", .{}),
        }
    }

    usingnamespace RuntimeBase(Builtins);
};
