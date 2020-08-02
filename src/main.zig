const std = @import("std");
const mem = std.mem;

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = &arena.allocator;

    const file = try std.fs.cwd().openFile("small.edr", .{});
    defer file.close();
    const code = try cleanup(allocator, try file.reader().readAllAlloc(allocator, std.math.maxInt(usize)));

    var tokens = try tokenize(allocator, code);

    // for (tokens) |token| std.debug.print("{}\n", .{token});

    var assembly = try assemble(allocator, tokens);
    // std.debug.print("{}\n", .{assembly});

    try Runtime.run(assembly, "main");
}

const CleanupState = enum {
    String,
    None,
};

fn cleanup(allocator: *mem.Allocator, code: []u8) ![]u8 {
    var cleaned = std.ArrayList(u8).init(allocator);
    defer cleaned.deinit();

    var state: CleanupState = .None;

    var skip: usize = 0;

    for (code) |char, i| {
        if (skip > 0) {
            skip -= 1;
            continue;
        }

        if (state == .String) {
            if (char == 34) {
                state = .None;
                try cleaned.append(char);
                continue;
            } else if (char == 92) {
                try cleaned.append(char);
                try cleaned.append(code[i + 1]);
                skip += 1;
                continue;
            }
        } else {
            if (char == 34) {
                state = .String;
                try cleaned.append(char);
                continue;
            }
        }

        if (state != .String and char == 9) continue;
        if (state != .String and char == 10) continue;
        if (state != .String and char == 13) continue;
        if (state != .String and char == 32) continue;
        try cleaned.append(char);
    }

    // std.debug.print("{}\n", .{cleaned.items});
    return cleaned.toOwnedSlice();
}

const Token = union(enum) {
    String: []const u8,
    Number: struct { string: []const u8, num: f64 },
    Ident: []const u8,
    CallSym: void,
    DefSym: void,
    DeclSym: void,
    TypeSym: void,
    Semicolon: void,
    Colon: void,
    Comma: void,
    BlockStart: void,
    BlockEnd: void,
    TupleStart: void,
    TupleEnd: void,
    IndexStart: void,
    IndexEnd: void,
    Void: void,
    None: void,
};

fn tokenize(allocator: *mem.Allocator, code: []u8) ![]Token {
    var tokens = std.ArrayList(Token).init(allocator);
    defer tokens.deinit();

    var curr_token: Token = .{ .None = {} };

    var skip: usize = 0;

    for (code) |char, i| {
        if (skip > 0) {
            skip -= 1;
            continue;
        }

        // Tokenize Ident
        if ((char >= 65 and char <= 90) or (char >= 97 and char <= 122)) {
            if (curr_token == .None) {
                curr_token = .{ .Ident = try mem.join(allocator, "", &[_][]const u8{ "", &[_]u8{char} }) };
                continue;
            } else if (curr_token == .Ident) {
                curr_token.Ident = try mem.join(allocator, "", &[_][]const u8{ curr_token.Ident, &[_]u8{char} });
                continue;
            }
        } else if (curr_token == .Ident) {
            try tokens.append(curr_token);
            curr_token = .{ .None = {} };
        }

        // Tokenize String
        if (char == 34) {
            if (curr_token == .None) {
                curr_token = .{ .String = "" };
                continue;
            } else if (curr_token == .String) {
                try tokens.append(curr_token);
                curr_token = .{ .None = {} };
                continue;
            }
        }
        if ((char >= 35 and char <= 126) or char == 32 or char == 33) {
            if (curr_token == .String) {
                if (char == 92) {
                    skip += 1;
                    curr_token.String = try mem.join(allocator, "", &[_][]const u8{ curr_token.String, &[_]u8{code[i + 1]} });
                    continue;
                } else {
                    curr_token.String = try mem.join(allocator, "", &[_][]const u8{ curr_token.String, &[_]u8{char} });
                    continue;
                }
            }
        }

        // Tokenize Number
        if ((char >= 48 and char <= 57) or char == 45 or char == 46) {
            if (curr_token == .None) {
                curr_token = .{ .Number = .{ .string = try mem.join(allocator, "", &[_][]const u8{ "", &[_]u8{char} }), .num = 0 } };
                continue;
            } else if (curr_token == .Number) {
                curr_token.Number.string = try mem.join(allocator, "", &[_][]const u8{ curr_token.Number.string, &[_]u8{char} });
                continue;
            }
        } else if (curr_token == .Number) {
            curr_token.Number.num = try std.fmt.parseFloat(f64, curr_token.Number.string);
            try tokens.append(curr_token);
            curr_token = .{ .None = {} };
        }

        // Tokenize #
        if (char == 35) {
            try tokens.append(Token{ .DefSym = {} });
            continue;
        }

        // Tokenize !
        if (char == 33) {
            try tokens.append(Token{ .CallSym = {} });
            continue;
        }

        // Tokenize :
        if (char == 58) {
            try tokens.append(Token{ .Colon = {} });
            continue;
        }

        // Tokenize ;
        if (char == 59) {
            try tokens.append(Token{ .Semicolon = {} });
            continue;
        }

        // Tokenize ,
        if (char == 44) {
            try tokens.append(Token{ .Comma = {} });
            continue;
        }

        // Tokenize {
        if (char == 123) {
            try tokens.append(Token{ .BlockStart = {} });
            continue;
        }

        // Tokenize }
        if (char == 125) {
            try tokens.append(Token{ .BlockEnd = {} });
            continue;
        }

        // Tokenize (
        if (char == 40) {
            try tokens.append(Token{ .TupleStart = {} });
            continue;
        }

        // Tokenize )
        if (char == 41) {
            try tokens.append(Token{ .TupleEnd = {} });
            continue;
        }

        // Tokenize [
        if (char == 91) {
            try tokens.append(Token{ .IndexStart = {} });
            continue;
        }

        // Tokenize ]
        if (char == 93) {
            try tokens.append(Token{ .IndexEnd = {} });
            continue;
        }

        // Tokenize _
        if (char == 95) {
            try tokens.append(Token{ .Void = {} });
            continue;
        }

        // Tokenize @
        if (char == 64) {
            try tokens.append(Token{ .TypeSym = {} });
            continue;
        }

        if (char == 36) {
            try tokens.append(Token{ .DeclSym = {} });
            continue;
        }

        std.debug.panic("Invalid Token: {c}\n", .{char});
    }

    return tokens.toOwnedSlice();
}

const Assembly = struct {
    const Variable = struct {
        name: []const u8,

        data: union(enum) {
            Number: f64,
            String: []const u8,
            Tuple: std.ArrayList(Variable),
            Void: void,
        },
    };

    const Call = struct {
        name: []const u8,

        var_in: Variable,
        var_out: Variable,

        builtin: bool,
    };

    const Function = struct {
        name: []const u8,

        var_in: Variable,
        var_out: Variable,

        block: Block,

        pub fn init(allocator: *mem.Allocator, name: []const u8, var_in: Variable, var_out: Variable) !Function {
            var block = Block.init(allocator);
            try block.variables.put(var_in.name, var_in);
            try block.variables.put(var_out.name, var_out);

            return Function{
                .name = name,

                .var_in = var_in,
                .var_out = var_out,

                .block = block,
            };
        }

        pub fn deinit(self: Function, allocator: *mem.Allocator) void {
            self.block.deinit(allocator);
        }
    };

    const Block = struct {
        variables: std.StringHashMap(Variable),

        calls: std.ArrayList(Call),

        pub fn init(allocator: *mem.Allocator) Block {
            return Block{
                .variables = std.StringHashMap(Variable).init(allocator),

                .calls = std.ArrayList(Call).init(allocator),
            };
        }

        pub fn deinit(self: Block, allocator: *mem.Allocator) void {
            self.variables.deinit();
            self.calls.deinit();
        }
    };

    allocator: *mem.Allocator,

    functions: std.StringHashMap(Function),

    pub fn init(allocator: *mem.Allocator) Assembly {
        return Assembly{
            .allocator = allocator,

            .functions = std.StringHashMap(Function).init(allocator),
        };
    }

    pub fn deinit(self: Assembly) void {
        for (self.functions.items()) |kv| kv.value.deinit();
        self.functions.deinit();
    }

    pub fn addFunction(self: *Assembly, function: Function) !void {
        try self.functions.put(function.name, function);
    }
};

fn assemble(allocator: *mem.Allocator, tokens: []Token) !Assembly {
    var assembly = Assembly.init(allocator);

    var i: usize = 0;
    while (i < tokens.len) {
        var skip: usize = 0;

        if (tokens[i + skip] == .DefSym) {
            skip += 1;
            if (tokens[i + skip] != .Ident) return error.InvalidSyntax;

            // Parses In and Out variables
            var in: Assembly.Variable = .{
                .name = "",
                .data = .{ .Void = {} },
            };
            var out: Assembly.Variable = .{
                .name = "",
                .data = .{ .Void = {} },
            };

            if (tokens[i + skip + 1] != .Colon) return error.InvalidSyntax;
            if (tokens[i + skip + 2] == .Ident) {
                in.name = tokens[i + skip + 2].Ident;
            } else if (tokens[i + skip + 2] == .Void) {
                in.name = "";
            } else return error.InvalidSyntax;
            if (tokens[i + skip + 3] != .TypeSym) return error.InvalidSyntax;
            switch (tokens[i + skip + 4]) {
                .String => in.data = .{ .String = tokens[i + skip + 4].String },
                .Number => in.data = .{ .Number = tokens[i + skip + 4].Number.num },
                .Void => in.data = .{ .Void = {} },
                .TupleStart => in.data = .{ .Tuple = undefined },
                else => return error.InvalidSyntax,
            }
            if (tokens[i + skip + 5] != .Colon) return error.InvalidSyntax;
            if (tokens[i + skip + 6] == .Ident) {
                out.name = tokens[i + skip + 6].Ident;
            } else if (tokens[i + skip + 6] == .Void) {
                out.name = "";
            } else return error.InvalidSyntax;
            if (tokens[i + skip + 7] != .TypeSym) return error.InvalidSyntax;
            switch (tokens[i + skip + 8]) {
                .String => out.data = .{ .String = tokens[i + skip + 8].String },
                .Number => out.data = .{ .Number = tokens[i + skip + 8].Number.num },
                .Void => out.data = .{ .Void = {} },
                .TupleStart => out.data = .{ .Tuple = undefined },
                else => return error.InvalidSyntax,
            }

            var function = try Assembly.Function.init(allocator, tokens[i + skip].Ident, in, out);
            skip += 9;

            // Parses Block
            if (tokens[i + skip] != .BlockStart) return error.InvalidSyntax;
            while (tokens[i + skip] != .BlockEnd) {
                // Variable Decl
                if (tokens[i + skip] == .DeclSym) {
                    var decl: Assembly.Variable = .{
                        .name = "",
                        .data = .{ .Void = {} },
                    };

                    if (tokens[i + skip + 1] != .Ident) return error.InvalidSyntax;
                    decl.name = tokens[i + skip + 1].Ident;
                    if (tokens[i + skip + 2] != .Colon) return error.InvalidSyntax;
                    switch (tokens[i + skip + 3]) {
                        .String => decl.data = .{ .String = tokens[i + skip + 3].String },
                        .Number => decl.data = .{ .Number = tokens[i + skip + 3].Number.num },
                        .Ident => decl.data = function.block.variables.get(tokens[i + skip + 3].Ident).?.data,
                        .Void => decl.data = .{ .Void = {} },
                        .TupleStart => {
                            decl.data = .{ .Tuple = std.ArrayList(Assembly.Variable).init(allocator) };
                            skip += 1;
                            while (tokens[i + skip + 3] != .TupleEnd) {
                                try switch (tokens[i + skip + 3]) {
                                    .String => decl.data.Tuple.append(.{ .name = "", .data = .{ .String = tokens[i + skip + 3].String } }),
                                    .Number => decl.data.Tuple.append(.{ .name = "", .data = .{ .Number = tokens[i + skip + 3].Number.num } }),
                                    .Ident => decl.data.Tuple.append(.{ .name = tokens[i + skip + 3].Ident, .data = function.block.variables.get(tokens[i + skip + 3].Ident).?.data }),
                                    .Void => decl.data.Tuple.append(.{ .name = "", .data = .{ .Void = {} } }),
                                    .TupleStart => return error.NotSupportedYet,
                                    .Comma => {},
                                    else => return error.InvalidSyntax,
                                };
                                skip += 1;
                            }
                        },
                        else => return error.InvalidSyntax,
                    }

                    try function.block.variables.put(decl.name, decl);
                    skip += 4;
                }
                // Function Call
                if (tokens[i + skip] == .CallSym) {
                    var call: Assembly.Call = .{
                        .name = "",

                        .var_in = .{
                            .name = "",
                            .data = .{ .Void = {} },
                        },
                        .var_out = .{
                            .name = "",
                            .data = .{ .Void = {} },
                        },

                        .builtin = false,
                    };

                    if (tokens[i + skip + 1] != .Ident) return error.InvalidSyntax;
                    call.name = tokens[i + skip + 1].Ident;
                    if (tokens[i + skip + 2] != .Colon) return error.InvalidSyntax;
                    switch (tokens[i + skip + 3]) {
                        .String => call.var_in = .{ .name = "", .data = .{ .String = tokens[i + skip + 3].String } },
                        .Number => call.var_in = .{ .name = "", .data = .{ .Number = tokens[i + skip + 3].Number.num } },
                        .Ident => call.var_in = .{ .name = tokens[i + skip + 3].Ident, .data = function.block.variables.get(tokens[i + skip + 3].Ident).?.data },
                        .Void => call.var_in = .{ .name = "", .data = .{ .Void = {} } },
                        .TupleStart => {
                            call.var_in = .{ .name = "", .data = .{ .Tuple = std.ArrayList(Assembly.Variable).init(allocator) } };
                            skip += 1;
                            while (tokens[i + skip + 3] != .TupleEnd) {
                                try switch (tokens[i + skip + 3]) {
                                    .String => call.var_in.data.Tuple.append(.{ .name = "", .data = .{ .String = tokens[i + skip + 3].String } }),
                                    .Number => call.var_in.data.Tuple.append(.{ .name = "", .data = .{ .Number = tokens[i + skip + 3].Number.num } }),
                                    .Ident => call.var_in.data.Tuple.append(.{ .name = tokens[i + skip + 3].Ident, .data = function.block.variables.get(tokens[i + skip + 3].Ident).?.data }),
                                    .Void => call.var_in.data.Tuple.append(.{ .name = "", .data = .{ .Void = {} } }),
                                    .TupleStart => return error.NotSupportedYet,
                                    .Comma => {},
                                    else => return error.InvalidSyntax,
                                };
                                skip += 1;
                            }
                        },
                        else => return error.InvalidSyntax,
                    }
                    if (tokens[i + skip + 4] != .Colon) return error.InvalidSyntax;
                    switch (tokens[i + skip + 5]) {
                        .Ident => call.var_out = .{ .name = tokens[i + skip + 5].Ident, .data = function.block.variables.get(tokens[i + skip + 5].Ident).?.data },
                        .Void => call.var_out = .{ .name = "", .data = .{ .Void = {} } },
                        else => return error.InvalidSyntax,
                    }

                    if (Runtime.Builtins.get(call.name) != null) call.builtin = true;

                    skip += 6;
                    try function.block.calls.append(call);
                }
                skip += 1;
            }
            if (tokens[i + skip + 1] != .Semicolon) return error.InvalidSyntax;

            try assembly.addFunction(function);
        }

        skip += 1;
        i += skip;
    }

    return assembly;
}

const Runtime = struct {
    const BuiltinFn = fn (var_in: Assembly.Variable, var_out: *Assembly.Variable) anyerror!void;
    pub const Builtins = std.ComptimeStringMap(BuiltinFn, .{
        .{ "print", print },
        .{ "add", add },
        .{ "sub", sub },
        .{ "mul", mul },
        .{ "div", div },
        .{ "square", square },
    });

    fn print(var_in: Assembly.Variable, var_out: *Assembly.Variable) anyerror!void {
        switch (var_in.data) {
            .String => std.debug.print("{}", .{var_in.data.String}),
            .Number => std.debug.print("{d}", .{var_in.data.Number}),
            .Void => std.debug.print("\n", .{}),
            .Tuple => {
                std.debug.print("(", .{});
                for (var_in.data.Tuple.items) |item, i| {
                    try print(item, var_out);

                    if (i != var_in.data.Tuple.items.len - 1) std.debug.print(", ", .{});
                }
                std.debug.print(")", .{});
            },
        }
    }

    fn add(var_in: Assembly.Variable, var_out: *Assembly.Variable) !void {
        if (var_in.data == .Tuple) {
            var_out.data.Number = var_in.data.Tuple.items[0].data.Number + var_in.data.Tuple.items[1].data.Number;
        } else return error.UnsupportedType;
    }

    fn sub(var_in: Assembly.Variable, var_out: *Assembly.Variable) !void {
        if (var_in.data == .Tuple) {
            var_out.data.Number = var_in.data.Tuple.items[0].data.Number - var_in.data.Tuple.items[1].data.Number;
        } else return error.UnsupportedType;
    }

    fn mul(var_in: Assembly.Variable, var_out: *Assembly.Variable) !void {
        if (var_in.data == .Tuple) {
            var_out.data.Number = var_in.data.Tuple.items[0].data.Number * var_in.data.Tuple.items[1].data.Number;
        } else return error.UnsupportedType;
    }

    fn div(var_in: Assembly.Variable, var_out: *Assembly.Variable) !void {
        if (var_in.data == .Tuple) {
            var_out.data.Number = var_in.data.Tuple.items[0].data.Number / var_in.data.Tuple.items[1].data.Number;
        } else return error.UnsupportedType;
    }

    fn square(var_in: Assembly.Variable, var_out: *Assembly.Variable) !void {
        if (var_in.data == .Number) {
            var_out.data.Number = var_in.data.Number * var_in.data.Number;
        } else return error.UnsupportedType;
    }

    pub fn run(assembly: Assembly, fnName: []const u8) !void {
        if (assembly.functions.get(fnName) == null) return error.FunctionNotFound;

        var func_block = assembly.functions.get(fnName).?.block;
        for (func_block.calls.items) |*call| {
            if (call.builtin) {
                if (!std.mem.eql(u8, call.var_in.name, "")) { 
                    if (call.var_out.data == .Void) { // Functions with var in and void out
                        var in = func_block.variables.get(call.var_in.name).?;
                        if (in.data == .Tuple) {
                            for (in.data.Tuple.items) |*item| {
                                item.data = func_block.variables.get(item.name).?.data;
                            }
                        }
                        try @call(.{}, Builtins.get(call.name).?, .{ in, &call.var_out });
                    } else { // Function with var in and var out
                        var in = func_block.variables.get(call.var_in.name).?;
                        if (in.data == .Tuple) {
                            for (in.data.Tuple.items) |*item| {
                                if (!std.mem.eql(u8, item.name, "")) item.data = func_block.variables.get(item.name).?.data;
                            }
                        }
                        try @call(.{}, Builtins.get(call.name).?, .{ in, &call.var_out });
                        try func_block.variables.put(call.var_out.name, call.var_out);
                    }
                } else if (std.mem.eql(u8, call.var_in.name, "")) { 
                    if (call.var_out.data == .Void) { // Function with typed in and void out
                        var in = func_block.variables.get(call.var_in.name).?;
                        if (in.data == .Tuple) {
                            for (in.data.Tuple.items) |*item| {
                                if (!std.mem.eql(u8, item.name, "")) item.data = func_block.variables.get(item.name).?.data;
                            }
                        }
                        try @call(.{}, Builtins.get(call.name).?, .{ in, &call.var_out });
                    } else { // Function with typed in and var out
                        var in = func_block.variables.get(call.var_in.name).?;
                        if (in.data == .Tuple) {
                            for (in.data.Tuple.items) |*item| {
                                if (!std.mem.eql(u8, item.name, "")) item.data = func_block.variables.get(item.name).?.data;
                            }
                        }
                        try @call(.{}, Builtins.get(call.name).?, .{ in, &call.var_out });
                        try func_block.variables.put(call.var_out.name, call.var_out);
                    }
                }
            } else {
                if (!std.mem.eql(u8, call.var_in.name, "")) { 
                    if (call.var_out.data == .Void) { // Functions with var in and void out
                        var in = func_block.variables.get(call.var_in.name).?;
                        if (in.data == .Tuple) {
                            for (in.data.Tuple.items) |*item| {
                                item.data = func_block.variables.get(item.name).?.data;
                            }
                        }
                        try runInternal(assembly, call.name, in, &call.var_out);
                    } else { // Function with var in and var out
                        var in = func_block.variables.get(call.var_in.name).?;
                        if (in.data == .Tuple) {
                            for (in.data.Tuple.items) |*item| {
                                if (!std.mem.eql(u8, item.name, "")) item.data = func_block.variables.get(item.name).?.data;
                            }
                        }
                        try runInternal(assembly, call.name, in, &call.var_out);
                        try func_block.variables.put(call.var_out.name, call.var_out);
                    }
                } else if (std.mem.eql(u8, call.var_in.name, "")) { 
                    if (call.var_out.data == .Void) { // Function with typed in and void out
                        var in = call.var_in;
                        if (in.data == .Tuple) {
                            for (in.data.Tuple.items) |*item| {
                                if (!std.mem.eql(u8, item.name, "")) item.data = func_block.variables.get(item.name).?.data;
                            }
                        }
                        try runInternal(assembly, call.name, in, &call.var_out);
                    } else { // Function with typed in and var out
                        var in = call.var_in;
                        if (in.data == .Tuple) {
                            for (in.data.Tuple.items) |*item| {
                                if (!std.mem.eql(u8, item.name, "")) item.data = func_block.variables.get(item.name).?.data;
                            }
                        }
                        try runInternal(assembly, call.name, in, &call.var_out);
                        try func_block.variables.put(call.var_out.name, call.var_out);
                    }
                }
            }
        }
    }

    fn runInternal(assembly: Assembly, fnName: []const u8, var_in: Assembly.Variable, var_out: *Assembly.Variable) anyerror!void {
        if (assembly.functions.get(fnName) == null) return error.FunctionNotFound;

        var func_block = assembly.functions.get(fnName).?.block;

        try func_block.variables.put(var_in.name, var_in);
        try func_block.variables.put(var_out.name, var_out.*);

        for (func_block.calls.items) |*call, i| {
            if (call.builtin) {
                if (!std.mem.eql(u8, call.var_in.name, "")) { 
                    if (call.var_out.data == .Void) { // Functions with var in and void out
                        var in = func_block.variables.get(call.var_in.name).?;
                        if (in.data == .Tuple) {
                            for (in.data.Tuple.items) |*item| {
                                item.data = func_block.variables.get(item.name).?.data;
                            }
                        }
                        try @call(.{}, Builtins.get(call.name).?, .{ in, &call.var_out });
                    } else { // Function with var in and var out
                        var in = func_block.variables.get(call.var_in.name).?;
                        if (in.data == .Tuple) {
                            for (in.data.Tuple.items) |*item| {
                                if (!std.mem.eql(u8, item.name, "")) item.data = func_block.variables.get(item.name).?.data;
                            }
                        }
                        try @call(.{}, Builtins.get(call.name).?, .{ in, &call.var_out });
                        try func_block.variables.put(call.var_out.name, call.var_out);
                    }
                } else if (std.mem.eql(u8, call.var_in.name, "")) { 
                    if (call.var_out.data == .Void) { // Function with typed in and void out
                        var in = call.var_in;
                        if (in.data == .Tuple) {
                            for (in.data.Tuple.items) |*item| {
                                if (!std.mem.eql(u8, item.name, "")) item.data = func_block.variables.get(item.name).?.data;
                            }
                        }
                        std.debug.print("{}\n", .{call});
                        try @call(.{}, Builtins.get(call.name).?, .{ in, &call.var_out });
                    } else { // Function with typed in and var out
                        var in = call.var_in;
                        if (in.data == .Tuple) {
                            for (in.data.Tuple.items) |*item| {
                                if (!std.mem.eql(u8, item.name, "")) item.data = func_block.variables.get(item.name).?.data;
                            }
                        }
                        try @call(.{}, Builtins.get(call.name).?, .{ in, &call.var_out });
                        try func_block.variables.put(call.var_out.name, call.var_out);
                    }
                }
            } else {
                if (!std.mem.eql(u8, call.var_in.name, "")) { 
                    if (call.var_out.data == .Void) { // Functions with var in and void out
                        var in = func_block.variables.get(call.var_in.name).?;
                        if (in.data == .Tuple) {
                            for (in.data.Tuple.items) |*item| {
                                item.data = func_block.variables.get(item.name).?.data;
                            }
                        }
                        try runInternal(assembly, call.name, in, &call.var_out);
                    } else { // Function with var in and var out
                        var in = func_block.variables.get(call.var_in.name).?;
                        if (in.data == .Tuple) {
                            for (in.data.Tuple.items) |*item| {
                                if (!std.mem.eql(u8, item.name, "")) item.data = func_block.variables.get(item.name).?.data;
                            }
                        }
                        try runInternal(assembly, call.name, in, &call.var_out);
                        try func_block.variables.put(call.var_out.name, call.var_out);
                    }
                } else if (std.mem.eql(u8, call.var_in.name, "")) { 
                    if (call.var_out.data == .Void) { // Function with typed in and void out
                        var in = call.var_in;
                        if (in.data == .Tuple) {
                            for (in.data.Tuple.items) |*item| {
                                if (!std.mem.eql(u8, item.name, "")) item.data = func_block.variables.get(item.name).?.data;
                            }
                        }
                        try runInternal(assembly, call.name, in, &call.var_out);
                    } else { // Function with typed in and var out
                        var in = call.var_in;
                        if (in.data == .Tuple) {
                            for (in.data.Tuple.items) |*item| {
                                if (!std.mem.eql(u8, item.name, "")) item.data = func_block.variables.get(item.name).?.data;
                            }
                        }
                        try runInternal(assembly, call.name, in, &call.var_out);
                        try func_block.variables.put(call.var_out.name, call.var_out);
                    }
                }
            }

            if (i == func_block.calls.items.len - 1) {
                var_out.data = call.var_out.data;
            }
        }

        _ = func_block.variables.remove(var_in.name);
        _ = func_block.variables.remove(var_out.name);
    }
};
