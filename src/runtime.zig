const std = @import("std");
const mem = std.mem;

const Assembly = @import("assembler.zig").Assembly;

pub const BuiltinFn = fn (allocator: *mem.Allocator, var_in: Assembly.Variable, var_out: *Assembly.Variable) anyerror!void;

pub fn RuntimeBase(comptime Builtins: type) type {
    return struct {
        pub fn run(allocator: *mem.Allocator, assembly: Assembly, fnName: []const u8) !void {
            if (assembly.functions.get(fnName) == null) return error.FunctionNotFound;

            var func_block = assembly.functions.get(fnName).?.block;
            var i: usize = 0;
            while (i < func_block.calls.items.len) {
                var call = &func_block.calls.items[i];
                if (call.builtin) {
                    if (mem.eql(u8, call.name, "jmp")) {
                        var in = if (!mem.eql(u8, call.var_in.name, "")) func_block.variables.get(call.var_in.name).? else call.var_in;
                        if (in.data.Bool) {
                            i = func_block.jmp_labels.get(call.var_out.data.String).?;
                            continue;
                        }
                    } else {
                        if (!mem.eql(u8, call.var_in.name, "")) {
                            if (call.var_out.data == .Void) { // Functions with var in and void out
                                var in = func_block.variables.get(call.var_in.name).?;
                                if (in.data == .Tuple) {
                                    for (in.data.Tuple.items) |*item| {
                                        item.data = func_block.variables.get(item.name).?.data;
                                    }
                                }
                                try @call(.{}, Builtins.get(call.name).?, .{ allocator, in, &call.var_out });
                            } else { // Function with var in and var out
                                var in = func_block.variables.get(call.var_in.name).?;
                                if (in.data == .Tuple) {
                                    for (in.data.Tuple.items) |*item| {
                                        if (!mem.eql(u8, item.name, "")) item.data = func_block.variables.get(item.name).?.data;
                                    }
                                }
                                try @call(.{}, Builtins.get(call.name).?, .{ allocator, in, &call.var_out });
                                try func_block.variables.put(call.var_out.name, call.var_out);
                            }
                        } else {
                            if (call.var_out.data == .Void) { // Function with typed in and void out
                                var in = call.var_in;
                                if (in.data == .Tuple) {
                                    for (in.data.Tuple.items) |*item| {
                                        if (!mem.eql(u8, item.name, "")) item.data = func_block.variables.get(item.name).?.data;
                                    }
                                }
                                try @call(.{}, Builtins.get(call.name).?, .{ allocator, in, &call.var_out });
                            } else { // Function with typed in and var out
                                var in = call.var_in;
                                if (in.data == .Tuple) {
                                    for (in.data.Tuple.items) |*item| {
                                        if (!mem.eql(u8, item.name, "")) item.data = func_block.variables.get(item.name).?.data;
                                    }
                                }
                                try @call(.{}, Builtins.get(call.name).?, .{ allocator, in, &call.var_out });
                                try func_block.variables.put(call.var_out.name, call.var_out);
                            }
                        }
                    }
                } else {
                    if (!mem.eql(u8, call.var_in.name, "")) {
                        if (call.var_out.data == .Void) { // Functions with var in and void out
                            var in = func_block.variables.get(call.var_in.name).?;
                            if (in.data == .Tuple) {
                                for (in.data.Tuple.items) |*item| {
                                    item.data = func_block.variables.get(item.name).?.data;
                                }
                            }
                            try runInternal(allocator, assembly, call.name, in, &call.var_out);
                        } else { // Function with var in and var out
                            var in = func_block.variables.get(call.var_in.name).?;
                            if (in.data == .Tuple) {
                                for (in.data.Tuple.items) |*item| {
                                    if (!mem.eql(u8, item.name, "")) item.data = func_block.variables.get(item.name).?.data;
                                }
                            }
                            try runInternal(allocator, assembly, call.name, in, &call.var_out);
                            try func_block.variables.put(call.var_out.name, call.var_out);
                        }
                    } else {
                        if (call.var_out.data == .Void) { // Function with typed in and void out
                            var in = call.var_in;
                            if (in.data == .Tuple) {
                                for (in.data.Tuple.items) |*item| {
                                    if (!mem.eql(u8, item.name, "")) item.data = func_block.variables.get(item.name).?.data;
                                }
                            }
                            try runInternal(allocator, assembly, call.name, in, &call.var_out);
                        } else { // Function with typed in and var out
                            var in = call.var_in;
                            if (in.data == .Tuple) {
                                for (in.data.Tuple.items) |*item| {
                                    if (!mem.eql(u8, item.name, "")) item.data = func_block.variables.get(item.name).?.data;
                                }
                            }
                            try runInternal(allocator, assembly, call.name, in, &call.var_out);
                            try func_block.variables.put(call.var_out.name, call.var_out);
                        }
                    }
                }

                i += 1;
            }
        }

        fn runInternal(allocator: *mem.Allocator, assembly: Assembly, fnName: []const u8, var_in: Assembly.Variable, var_out: *Assembly.Variable) anyerror!void {
            if (assembly.functions.get(fnName) == null) return error.FunctionNotFound;

            var func_block = assembly.functions.get(fnName).?.block;

            if (mem.eql(u8, var_in.name, "")) {
                try func_block.variables.put(assembly.functions.get(fnName).?.var_in.name, var_in);
                try func_block.variables.put(assembly.functions.get(fnName).?.var_out.name, var_out.*);
            } else {
                try func_block.variables.put(var_in.name, var_in);
                try func_block.variables.put(var_out.name, var_out.*);
            }

            var i: usize = 0;
            while (i < func_block.calls.items.len) {
                var call = &func_block.calls.items[i];
                if (call.builtin) {
                    if (mem.eql(u8, call.name, "jmp")) {
                        var in = func_block.variables.get(call.var_in.name).?;
                        if (in.data.Bool) {
                            i = func_block.jmp_labels.get(call.var_out.data.String).?;
                            continue;
                        }
                    } else {
                        if (!mem.eql(u8, call.var_in.name, "")) {
                            if (call.var_out.data == .Void) { // Functions with var in and void out
                                var in = func_block.variables.get(call.var_in.name).?;
                                if (in.data == .Tuple) {
                                    for (in.data.Tuple.items) |*item| {
                                        item.data = func_block.variables.get(item.name).?.data;
                                    }
                                }
                                try @call(.{}, Builtins.get(call.name).?, .{ allocator, in, &call.var_out });
                            } else { // Function with var in and var out
                                var in = func_block.variables.get(call.var_in.name).?;
                                if (in.data == .Tuple) {
                                    for (in.data.Tuple.items) |*item| {
                                        if (!mem.eql(u8, item.name, "")) item.data = func_block.variables.get(item.name).?.data;
                                    }
                                }
                                try @call(.{}, Builtins.get(call.name).?, .{ allocator, in, &call.var_out });
                                try func_block.variables.put(call.var_out.name, call.var_out);
                            }
                        } else {
                            if (call.var_out.data == .Void) { // Function with typed in and void out
                                var in = call.var_in;
                                if (in.data == .Tuple) {
                                    for (in.data.Tuple.items) |*item| {
                                        if (!mem.eql(u8, item.name, "")) item.data = func_block.variables.get(item.name).?.data;
                                    }
                                }
                                try @call(.{}, Builtins.get(call.name).?, .{ allocator, in, &call.var_out });
                            } else { // Function with typed in and var out
                                var in = call.var_in;
                                if (in.data == .Tuple) {
                                    for (in.data.Tuple.items) |*item| {
                                        if (!mem.eql(u8, item.name, "")) item.data = func_block.variables.get(item.name).?.data;
                                    }
                                }
                                try @call(.{}, Builtins.get(call.name).?, .{ allocator, in, &call.var_out });
                                try func_block.variables.put(call.var_out.name, call.var_out);
                            }
                        }
                    }
                } else {
                    if (!mem.eql(u8, call.var_in.name, "")) {
                        if (call.var_out.data == .Void) { // Functions with var in and void out
                            var in = func_block.variables.get(call.var_in.name).?;
                            if (in.data == .Tuple) {
                                for (in.data.Tuple.items) |*item| {
                                    item.data = func_block.variables.get(item.name).?.data;
                                }
                            }
                            try runInternal(allocator, assembly, call.name, in, &call.var_out);
                        } else { // Function with var in and var out
                            var in = func_block.variables.get(call.var_in.name).?;
                            if (in.data == .Tuple) {
                                for (in.data.Tuple.items) |*item| {
                                    if (!mem.eql(u8, item.name, "")) item.data = func_block.variables.get(item.name).?.data;
                                }
                            }
                            try runInternal(allocator, assembly, call.name, in, &call.var_out);
                            try func_block.variables.put(call.var_out.name, call.var_out);
                        }
                    } else {
                        if (call.var_out.data == .Void) { // Function with typed in and void out
                            var in = call.var_in;
                            if (in.data == .Tuple) {
                                for (in.data.Tuple.items) |*item| {
                                    if (!mem.eql(u8, item.name, "")) item.data = func_block.variables.get(item.name).?.data;
                                }
                            }
                            try runInternal(allocator, assembly, call.name, in, &call.var_out);
                        } else { // Function with typed in and var out
                            var in = call.var_in;
                            if (in.data == .Tuple) {
                                for (in.data.Tuple.items) |*item| {
                                    if (!mem.eql(u8, item.name, "")) item.data = func_block.variables.get(item.name).?.data;
                                }
                            }
                            try runInternal(allocator, assembly, call.name, in, &call.var_out);
                            try func_block.variables.put(call.var_out.name, call.var_out);
                        }
                    }
                }

                if (i == func_block.calls.items.len - 1) {
                    var_out.data = call.var_out.data;
                }

                i += 1;
            }

            _ = func_block.variables.remove(var_in.name);
            _ = func_block.variables.remove(var_out.name);
        }
    };
}

pub const SimpleRuntime = struct {
    pub const Builtins = std.ComptimeStringMap(BuiltinFn, .{
        .{ "print", print },
        .{ "readline", readline },
        .{ "set", set },
        .{ "add", add },
        .{ "sub", sub },
        .{ "mul", mul },
        .{ "div", div },
        .{ "mod", mod },
        .{ "gt", gt },
        .{ "gte", gte },
        .{ "lt", lt },
        .{ "lte", lte },
        .{ "eql", eql },
    });

    fn print(allocator: *mem.Allocator, var_in: Assembly.Variable, var_out: *Assembly.Variable) anyerror!void {
        switch (var_in.data) {
            .String => try std.io.getStdOut().outStream().print("{}", .{var_in.data.String}),
            .Number => try std.io.getStdOut().outStream().print("{d}", .{var_in.data.Number}),
            .Bool => try std.io.getStdOut().outStream().print("{}", .{var_in.data.Bool}),
            .Void => try std.io.getStdOut().outStream().print("\n", .{}),
            .Tuple => {
                try std.io.getStdOut().outStream().print("(", .{});
                for (var_in.data.Tuple.items) |item, i| {
                    try print(allocator, item, var_out);

                    if (i != var_in.data.Tuple.items.len - 1) try std.io.getStdOut().outStream().print(", ", .{});
                }
                try std.io.getStdOut().outStream().print(")", .{});
            },
        }
    }

    fn readline(allocator: *mem.Allocator, var_in: Assembly.Variable, var_out: *Assembly.Variable) !void {
        const data = try std.io.getStdIn().inStream().readUntilDelimiterAlloc(allocator, 10, std.math.maxInt(u64));
        var_out.data = switch (var_out.data) {
            .String => .{ .String = data },
            .Number => .{ .Number = try std.fmt.parseFloat(f64, data) },
            else => return error.UnsupportedType,
        };
    }

    fn set(allocator: *mem.Allocator, var_in: Assembly.Variable, var_out: *Assembly.Variable) !void {
        var_out.data = var_in.data;
    }

    fn add(allocator: *mem.Allocator, var_in: Assembly.Variable, var_out: *Assembly.Variable) !void {
        if (var_in.data == .Tuple) {
            var_out.data.Number = var_in.data.Tuple.items[0].data.Number + var_in.data.Tuple.items[1].data.Number;
        } else return error.UnsupportedType;
    }

    fn sub(allocator: *mem.Allocator, var_in: Assembly.Variable, var_out: *Assembly.Variable) !void {
        if (var_in.data == .Tuple) {
            var_out.data.Number = var_in.data.Tuple.items[0].data.Number - var_in.data.Tuple.items[1].data.Number;
        } else return error.UnsupportedType;
    }

    fn mul(allocator: *mem.Allocator, var_in: Assembly.Variable, var_out: *Assembly.Variable) !void {
        if (var_in.data == .Tuple) {
            var_out.data.Number = var_in.data.Tuple.items[0].data.Number * var_in.data.Tuple.items[1].data.Number;
        } else return error.UnsupportedType;
    }

    fn div(allocator: *mem.Allocator, var_in: Assembly.Variable, var_out: *Assembly.Variable) !void {
        if (var_in.data == .Tuple) {
            var_out.data.Number = var_in.data.Tuple.items[0].data.Number / var_in.data.Tuple.items[1].data.Number;
        } else return error.UnsupportedType;
    }

    fn mod(allocator: *mem.Allocator, var_in: Assembly.Variable, var_out: *Assembly.Variable) !void {
        if (var_in.data == .Tuple) {
            var_out.data.Number = @mod(var_in.data.Tuple.items[0].data.Number, var_in.data.Tuple.items[1].data.Number);
        } else return error.UnsupportedType;
    }

    fn gt(allocator: *mem.Allocator, var_in: Assembly.Variable, var_out: *Assembly.Variable) !void {
        if (var_in.data == .Tuple) {
            var_out.data.Bool = var_in.data.Tuple.items[0].data.Number > var_in.data.Tuple.items[1].data.Number;
        } else return error.UnsupportedType;
    }

    fn gte(allocator: *mem.Allocator, var_in: Assembly.Variable, var_out: *Assembly.Variable) !void {
        if (var_in.data == .Tuple) {
            var_out.data.Bool = var_in.data.Tuple.items[0].data.Number >= var_in.data.Tuple.items[1].data.Number;
        } else return error.UnsupportedType;
    }

    fn lt(allocator: *mem.Allocator, var_in: Assembly.Variable, var_out: *Assembly.Variable) !void {
        if (var_in.data == .Tuple) {
            var_out.data.Bool = var_in.data.Tuple.items[0].data.Number < var_in.data.Tuple.items[1].data.Number;
        } else return error.UnsupportedType;
    }

    fn lte(allocator: *mem.Allocator, var_in: Assembly.Variable, var_out: *Assembly.Variable) !void {
        if (var_in.data == .Tuple) {
            var_out.data.Bool = var_in.data.Tuple.items[0].data.Number <= var_in.data.Tuple.items[1].data.Number;
        } else return error.UnsupportedType;
    }

    fn eql(allocator: *mem.Allocator, var_in: Assembly.Variable, var_out: *Assembly.Variable) !void {
        if (var_in.data == .Tuple) {
            switch (var_in.data.Tuple.items[0].data) {
                .String => {
                    var_out.data.Bool = mem.eql(u8, var_in.data.Tuple.items[0].data.String, var_in.data.Tuple.items[1].data.String);
                },
                .Number => {
                    var_out.data.Bool = var_in.data.Tuple.items[0].data.Number == var_in.data.Tuple.items[1].data.Number;
                },
                .Bool => {
                    var_out.data.Bool = var_in.data.Tuple.items[0].data.Bool == var_in.data.Tuple.items[1].data.Bool;
                },
                else => return error.NotSupportedYet,
            }
        } else return error.UnsupportedType;
    }

    usingnamespace RuntimeBase(Builtins);
};
