const std = @import("std");
const mem = std.mem;

const tk = @import("tokenizer.zig");

pub const Assembly = struct {
    pub const Variable = struct {
        name: []const u8,

        data: union(enum) {
            Number: f64,
            String: []const u8,
            Bool: bool,
            Tuple: struct { items: std.ArrayList(Variable), index: ?usize = null },
            Void: void,
        },
    };

    pub const Call = struct {
        name: []const u8,

        var_in: Variable,
        var_out: Variable,

        builtin: bool,
    };

    pub const Function = struct {
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

    pub const Block = struct {
        variables: std.StringHashMap(Variable),
        calls: std.ArrayList(Call),
        jmp_labels: std.StringHashMap(usize),

        pub fn init(allocator: *mem.Allocator) Block {
            return Block{
                .variables = std.StringHashMap(Variable).init(allocator),
                .calls = std.ArrayList(Call).init(allocator),
                .jmp_labels = std.StringHashMap(usize).init(allocator),
            };
        }

        pub fn deinit(self: Block, allocator: *mem.Allocator) void {
            self.variables.deinit();
            self.calls.deinit();
            self.jmp_labels.deinit();
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

pub fn assemble(comptime Runtime: type, allocator: *mem.Allocator, code: []const u8) !Assembly {
    var tokens = try tk.tokenize(allocator, code);

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
                .Bool => in.data = .{ .Bool = tokens[i + skip + 4].Bool },
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
                .Bool => out.data = .{ .Bool = tokens[i + skip + 8].Bool },
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
                        .Bool => decl.data = .{ .Bool = tokens[i + skip + 3].Bool },
                        .Void => decl.data = .{ .Void = {} },
                        .TupleStart => {
                            decl.data = .{ .Tuple = .{ .items = std.ArrayList(Assembly.Variable).init(allocator) } };
                            skip += 1;
                            while (tokens[i + skip + 3] != .TupleEnd) {
                                try switch (tokens[i + skip + 3]) {
                                    .String => decl.data.Tuple.items.append(.{ .name = "", .data = .{ .String = tokens[i + skip + 3].String } }),
                                    .Number => decl.data.Tuple.items.append(.{ .name = "", .data = .{ .Number = tokens[i + skip + 3].Number.num } }),
                                    .Ident => decl.data.Tuple.items.append(.{ .name = tokens[i + skip + 3].Ident, .data = function.block.variables.get(tokens[i + skip + 3].Ident).?.data }),
                                    .Bool => decl.data.Tuple.items.append(.{ .name = "", .data = .{ .Bool = tokens[i + skip + 3].Bool } }),
                                    .Void => decl.data.Tuple.items.append(.{ .name = "", .data = .{ .Void = {} } }),
                                    .TupleStart => {
                                        var inner = std.ArrayList(Assembly.Variable).init(allocator);
                                        skip += 1;
                                        while (tokens[i + skip + 3] != .TupleEnd) {
                                            try switch (tokens[i + skip + 3]) {
                                                .String => inner.append(.{ .name = "", .data = .{ .String = tokens[i + skip + 3].String } }),
                                                .Number => inner.append(.{ .name = "", .data = .{ .Number = tokens[i + skip + 3].Number.num } }),
                                                .Ident => inner.append(.{ .name = tokens[i + skip + 3].Ident, .data = function.block.variables.get(tokens[i + skip + 3].Ident).?.data }),
                                                .Bool => inner.append(.{ .name = "", .data = .{ .Bool = tokens[i + skip + 3].Bool } }),
                                                .Void => inner.append(.{ .name = "", .data = .{ .Void = {} } }),
                                                .TupleStart => return error.NotSupportedYet,
                                                .Comma => {},
                                                else => return error.InvalidSyntax,
                                            };
                                            skip += 1;
                                        }
                                        try decl.data.Tuple.items.append(.{ .name = "", .data = .{ .Tuple = .{ .items = inner } } });
                                    },
                                    .Comma => {},
                                    else => return error.InvalidSyntax,
                                };
                                skip += 1;
                            }
                        },
                        else => return error.InvalidSyntax,
                    }

                    try function.block.variables.put(decl.name, decl);
                    skip += 3;
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
                        .Bool => call.var_in = .{ .name = "", .data = .{ .Bool = tokens[i + skip + 3].Bool } },
                        .Void => call.var_in = .{ .name = "", .data = .{ .Void = {} } },
                        .TupleStart => {
                            call.var_in = .{ .name = "", .data = .{ .Tuple = .{ .items = std.ArrayList(Assembly.Variable).init(allocator) } } };
                            skip += 1;
                            while (tokens[i + skip + 3] != .TupleEnd) {
                                try switch (tokens[i + skip + 3]) {
                                    .String => call.var_in.data.Tuple.items.append(.{ .name = "", .data = .{ .String = tokens[i + skip + 3].String } }),
                                    .Number => call.var_in.data.Tuple.items.append(.{ .name = "", .data = .{ .Number = tokens[i + skip + 3].Number.num } }),
                                    .Ident => call.var_in.data.Tuple.items.append(.{ .name = tokens[i + skip + 3].Ident, .data = function.block.variables.get(tokens[i + skip + 3].Ident).?.data }),
                                    .Bool => call.var_in.data.Tuple.items.append(.{ .name = "", .data = .{ .Bool = tokens[i + skip + 3].Bool } }),
                                    .Void => call.var_in.data.Tuple.items.append(.{ .name = "", .data = .{ .Void = {} } }),
                                    .TupleStart => {
                                        var inner = std.ArrayList(Assembly.Variable).init(allocator);
                                        skip += 1;
                                        while (tokens[i + skip + 3] != .TupleEnd) {
                                            try switch (tokens[i + skip + 3]) {
                                                .String => inner.append(.{ .name = "", .data = .{ .String = tokens[i + skip + 3].String } }),
                                                .Number => inner.append(.{ .name = "", .data = .{ .Number = tokens[i + skip + 3].Number.num } }),
                                                .Ident => inner.append(.{ .name = tokens[i + skip + 3].Ident, .data = function.block.variables.get(tokens[i + skip + 3].Ident).?.data }),
                                                .Bool => inner.append(.{ .name = "", .data = .{ .Bool = tokens[i + skip + 3].Bool } }),
                                                .Void => inner.append(.{ .name = "", .data = .{ .Void = {} } }),
                                                .TupleStart => return error.NotSupportedYet,
                                                .Comma => {},
                                                else => return error.InvalidSyntax,
                                            };
                                            skip += 1;
                                        }
                                        try call.var_in.data.Tuple.items.append(.{ .name = "", .data = .{ .Tuple = .{ .items = inner } } });
                                    },
                                    .Comma => {},
                                    else => return error.InvalidSyntax,
                                };
                                skip += 1;
                            }
                        },
                        else => return error.InvalidSyntax,
                    }
                    switch (tokens[i + skip + 4]) {
                        .IndexStart => {
                            skip += 1;
                            switch (tokens[i + skip + 4]) {
                                .Number => call.var_in.data.Tuple.index = @floatToInt(usize, tokens[i + skip + 4].Number.num),
                                else => return error.InvalidSyntax,
                            }
                            skip += 2;
                        },
                        .Colon => {},
                        else => return error.InvalidSyntax,
                    }
                    switch (tokens[i + skip + 5]) {
                        .Ident => call.var_out = .{ .name = tokens[i + skip + 5].Ident, .data = function.block.variables.get(tokens[i + skip + 5].Ident).?.data },
                        .Void => call.var_out = .{ .name = "", .data = .{ .Void = {} } },
                        else => return error.InvalidSyntax,
                    }

                    if (@hasDecl(Runtime, "Builtins")) {
                        if (Runtime.Builtins.get(call.name) != null) call.builtin = true;
                    } else @compileError("Runtime has no builtin functions!");

                    skip += 5;
                    try function.block.calls.append(call);
                }

                if (tokens[i + skip] == .JmpLabel) {
                    if (tokens[i + skip + 1] != .String) return error.InvalidSyntax;
                    try function.block.jmp_labels.put(tokens[i + skip + 1].String, function.block.calls.items.len);
                    skip += 1;
                }

                if (tokens[i + skip] == .JmpSym) {
                    var call: Assembly.Call = .{
                        .name = "jmp",

                        .var_in = .{
                            .name = "",
                            .data = .{ .Void = {} },
                        },
                        .var_out = .{
                            .name = "",
                            .data = .{ .Void = {} },
                        },

                        .builtin = true,
                    };

                    if (tokens[i + skip + 1] != .Colon) return error.InvalidSyntax;
                    switch (tokens[i + skip + 2]) {
                        .Bool => call.var_in = .{ .name = "", .data = .{ .Bool = tokens[i + skip + 2].Bool } },
                        .Ident => call.var_in = .{ .name = tokens[i + skip + 2].Ident, .data = function.block.variables.get(tokens[i + skip + 2].Ident).?.data },
                        else => return error.InvalidSyntax,
                    }
                    if (tokens[i + skip + 3] != .Colon) return error.InvalidSyntax;
                    if (tokens[i + skip + 4] != .String) return error.InvalidSyntax;
                    call.var_out = .{ .name = "", .data = .{ .String = tokens[i + skip + 4].String } };

                    skip += 4;
                    try function.block.calls.append(call);
                }

                if (tokens[i + skip] == .If) {
                    var call: Assembly.Call = .{
                        .name = "if",

                        .var_in = .{
                            .name = "",
                            .data = .{ .Void = {} },
                        },
                        .var_out = .{
                            .name = "",
                            .data = .{ .Void = {} },
                        },

                        .builtin = true,
                    };

                    if (tokens[i + skip + 1] != .Colon) return error.InvalidSyntax;
                    switch (tokens[i + skip + 2]) {
                        .Bool => call.var_in = .{ .name = "", .data = .{ .Bool = tokens[i + skip + 2].Bool } },
                        .Ident => call.var_in = .{ .name = tokens[i + skip + 2].Ident, .data = function.block.variables.get(tokens[i + skip + 2].Ident).?.data },
                        else => return error.InvalidSyntax,
                    }
                    if (tokens[i + skip + 3] != .Colon) return error.InvalidSyntax;
                    if (tokens[i + skip + 4] != .Number) return error.InvalidSyntax;
                    switch (tokens[i + skip + 4]) {
                        .Number => call.var_out = .{ .name = "", .data = .{ .Number = tokens[i + skip + 4].Number.num } },
                        .Ident => call.var_out = .{ .name = tokens[i + skip + 4].Ident, .data = function.block.variables.get(tokens[i + skip + 4].Ident).?.data },
                        else => return error.InvalidSyntax,
                    }

                    skip += 4;
                    try function.block.calls.append(call);
                }
                skip += 1;
            }

            try assembly.addFunction(function);
        }

        skip += 1;
        i += skip;
    }

    return assembly;
}
