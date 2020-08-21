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

        fn runBlock(state: *RuntimeState, block: *RuntimeState.Block, var_in: ?[]std.StringHashMap(RuntimeState.Variable).Entry) anyerror!std.StringHashMap(RuntimeState.Variable) {
            if (var_in) |ins| {
                for (ins) |in| {
                    try block.variables.put(in.key, in.value);
                }
            }

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
                                .Operation => |o| block.variables.getEntry(out.name).?.value = (try runOpCall(state, block, o)).?,
                            }
                        }
                    },
                    .Call => _ = try runOpCall(state, block, ops[i]),
                    .If => {
                        const op = @fieldParentPtr(pa.Parsed.Operation.If, "base", ops[i]);

                        var ifelse = false;
                        switch (op.input) {
                            .Literal => |il| {
                                switch (op.comp) {
                                    .Literal => |cl| {
                                        if (@enumToInt(il) != @enumToInt(cl)) std.debug.panic("If types {} and {} are not equal!", .{ il, cl });
                                        switch (il) {
                                            .Integer => ifelse = (il.Integer == cl.Integer),
                                            .Number => ifelse = (il.Number == cl.Number),
                                            .String => ifelse = mem.eql(u8, il.String, cl.String),
                                            .Bool => ifelse = (il.Bool == cl.Bool),

                                            else => std.debug.panic("Not Supported!", .{}),
                                        }
                                    },
                                    .Variable => |cv| {
                                        if (!block.variables.contains(cv.name)) std.debug.panic("Variable `{}` does not exist", .{cv.name});
                                        if (@enumToInt(il) != @enumToInt(block.variables.get(cv.name).?)) std.debug.panic("If types {} and {} are not equal!", .{ il, block.variables.get(cv.name).? });
                                        const cd = block.variables.get(cv.name).?;
                                        switch (il) {
                                            .Integer => ifelse = (il.Integer == cd.Integer),
                                            .Number => ifelse = (il.Number == cd.Number),
                                            .String => ifelse = mem.eql(u8, il.String, cd.String),
                                            .Bool => ifelse = (il.Bool == cd.Bool),

                                            else => std.debug.panic("Not Supported!", .{}),
                                        }
                                    },
                                    else => std.debug.panic("Not Supported Yet!", .{}),
                                }
                            },
                            .Variable => |iv| {
                                switch (op.comp) {
                                    .Literal => |cl| {
                                        if (!block.variables.contains(iv.name)) std.debug.panic("Variable `{}` does not exist", .{iv.name});
                                        if (@enumToInt(block.variables.get(iv.name).?) != @enumToInt(cl)) std.debug.panic("If types {} and {} are not equal!", .{ block.variables.get(iv.name).?, cl });
                                        const id = block.variables.get(iv.name).?;
                                        switch (id) {
                                            .Integer => ifelse = (id.Integer == cl.Integer),
                                            .Number => ifelse = (id.Number == cl.Number),
                                            .String => ifelse = mem.eql(u8, id.String, cl.String),
                                            .Bool => ifelse = (id.Bool == cl.Bool),

                                            else => std.debug.panic("Not Supported!", .{}),
                                        }
                                    },
                                    .Variable => |cv| {
                                        if (!block.variables.contains(iv.name)) std.debug.panic("Variable `{}` does not exist", .{iv.name});
                                        if (!block.variables.contains(cv.name)) std.debug.panic("Variable `{}` does not exist", .{cv.name});
                                        if (@enumToInt(block.variables.get(iv.name).?) != @enumToInt(block.variables.get(cv.name).?)) std.debug.panic("If types {} and {} are not equal!", .{ block.variables.get(iv.name).?, block.variables.get(cv.name).? });
                                        const id = block.variables.get(iv.name).?;
                                        const cd = block.variables.get(cv.name).?;
                                        switch (id) {
                                            .Integer => ifelse = (id.Integer == cd.Integer),
                                            .Number => ifelse = (id.Number == cd.Number),
                                            .String => ifelse = mem.eql(u8, id.String, cd.String),
                                            .Bool => ifelse = (id.Bool == cd.Bool),

                                            else => std.debug.panic("Not Supported!", .{}),
                                        }
                                    },
                                    else => std.debug.panic("Not Supported Yet!", .{}),
                                }
                            },
                            else => std.debug.panic("Not Supported Yet!", .{}),
                        }

                        if (ifelse) {
                            var ifelseblock = RuntimeState.Block.initBlock(state.allocator, op.ifblock);
                            defer ifelseblock.deinit();
                            const var_out = (try runBlock(state, &ifelseblock, block.variables.items())).items();
                            for (var_out) |out| {
                                try block.variables.put(out.key, out.value);
                            }
                        } else {
                            if (op.elseblock != null) {
                                var ifelseblock = RuntimeState.Block.initBlock(state.allocator, op.elseblock.?);
                                defer ifelseblock.deinit();
                                const var_out = (try runBlock(state, &ifelseblock, block.variables.items())).items();
                                for (var_out) |out| {
                                    try block.variables.put(out.key, out.value);
                                }
                            }
                        }
                    },
                }

                i += 1;
            }

            return block.variables;
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

                    .Void => {},

                    .Block => |d| try inputs.append(.{ .Block = RuntimeState.Block.initBlock(state.allocator, d) }),
                },
                .Variable => |v| {
                    if (!block.variables.contains(v.name)) std.debug.panic("Variable `{}` not found!", .{v.name});
                    try inputs.append(block.variables.get(v.name).?);
                },

                .Operation => try inputs.append((try runOpCall(state, block, input.Operation)) orelse .{ .Void = {} }),
            };

            const input_slice = inputs.toOwnedSlice();
            if (Builtins.has(op.func)) {
                return @call(.{}, Builtins.get(op.func).?, .{ state, input_slice });
            } else if (block.variables.contains(op.func) and block.variables.get(op.func).? == .Block) {
                var opblock = block.variables.get(op.func).?.Block;

                if (opblock.block.var_in.items().len != input_slice.len) std.debug.panic("Not Enough Inputs for Block!", .{});

                var block_inputs = try block.variables.clone();
                defer block_inputs.deinit();
                for (input_slice) |in, i| {
                    if (opblock.block.var_in.items()[i].value != in) std.debug.panic("Type mismatch between {} and {}", .{opblock.block.var_in.items()[i].value, in});
                    try block_inputs.put(opblock.block.var_in.items()[i].key, in);
                }

                const res = try runBlock(state, &opblock, block_inputs.items());
                if (opblock.block.var_out != null) {
                    return res.get(opblock.block.var_out.?.name);
                } else return null;
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
        .{ "readline", readline },
        .{ "readlineInt", readlineInt },
        .{ "readlineNum", readlineNum },
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

    fn readline(state: *RuntimeState, var_in: []const RuntimeState.Variable) anyerror!?RuntimeState.Variable {
        const data = try std.io.getStdIn().inStream().readUntilDelimiterAlloc(state.allocator, 10, std.math.maxInt(u64));
        return RuntimeState.Variable{ .String = data };
    }

    fn readlineInt(state: *RuntimeState, var_in: []const RuntimeState.Variable) anyerror!?RuntimeState.Variable {
        const data = try std.io.getStdIn().inStream().readUntilDelimiterAlloc(state.allocator, 10, std.math.maxInt(u64));
        return RuntimeState.Variable{ .Integer = try std.fmt.parseInt(i64, data, 10) };
    }

    fn readlineNum(state: *RuntimeState, var_in: []const RuntimeState.Variable) anyerror!?RuntimeState.Variable {
        const data = try std.io.getStdIn().inStream().readUntilDelimiterAlloc(state.allocator, 10, std.math.maxInt(u64));
        return RuntimeState.Variable{ .Number = try std.fmt.parseFloat(f64, data) };
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
