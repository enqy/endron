const std = @import("std");
const mem = std.mem;

const tk = @import("tokenizer.zig");

pub const Parsed = struct {
    pub const Operation = struct {
        pub const Kind = enum {
            Decl,
            Set,
            Call,
            If,
            While,
        };

        kind: Kind,

        pub const Input = union(enum) {
            Literal: Literal,
            Variable: Variable,
            Operation: *Operation,
        };

        pub const Decl = struct {
            base: Operation = .{ .kind = .Decl },

            kind: Variable.Kind,
            decls: [][]const u8,
        };

        pub const Set = struct {
            base: Operation = .{ .kind = .Set },

            input: Input,
            outputs: []Variable,
        };

        pub const Call = struct {
            base: Operation = .{ .kind = .Call },

            func: []const u8,
            inputs: []Input,
        };

        pub const If = struct {
            base: Operation = .{ .kind = .If },

            input: Input,
            comp: Input,

            ifblock: Block,
            elseblock: ?Block,
        };

        pub const While = struct {
            base: Operation = .{ .kind = .While },

            input: Input,
            comp: Input,

            block: Block,
        };
    };

    pub const Literal = union(Variable.Kind) {
        Integer: i64,
        Number: f64,
        String: []const u8,
        Bool: bool,

        Void: void,

        Block: Block,
    };

    pub const Variable = struct {
        pub const Kind = enum {
            Integer,
            Number,
            String,
            Bool,

            Void,

            Block,
        };

        name: []const u8,

        kind: ?Kind,
    };

    pub const Block = struct {
        var_in: std.StringHashMap(Variable.Kind),
        var_out: ?Variable,
        operations: std.ArrayList(*Operation),

        fn init(allocator: *mem.Allocator) Block {
            return Block{
                .var_in = std.StringHashMap(Variable.Kind).init(allocator),
                .var_out = null,
                .operations = std.ArrayList(*Operation).init(allocator),
            };
        }
    };

    arena: std.heap.ArenaAllocator,

    block: Block,

    fn init(arena: std.heap.ArenaAllocator, block: Block) Parsed {
        return Parsed{
            .arena = arena,

            .block = block,
        };
    }

    pub fn deinit(self: *Parsed) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

const BuiltinTypeMap = std.ComptimeStringMap(Parsed.Variable.Kind, .{
    .{ "int", Parsed.Variable.Kind.Integer },
    .{ "num", Parsed.Variable.Kind.Number },
    .{ "str", Parsed.Variable.Kind.String },
    .{ "bool", Parsed.Variable.Kind.Bool },

    .{ "block", Parsed.Variable.Kind.Block },
});

pub fn parse(allocator: *mem.Allocator, tokens: []const tk.Token) !Parsed {
    var arena = std.heap.ArenaAllocator.init(allocator);
    var block = try parseBlock(&arena.allocator, tokens, 0, tokens.len);
    var parsed = Parsed.init(arena, block);

    (try typeCheckBlock(allocator, &parsed, &parsed.block)).deinit();

    return parsed;
}

fn typeCheckBlock(allocator: *mem.Allocator, parsed: *Parsed, block: *Parsed.Block) !std.StringHashMap(Parsed.Variable.Kind) {
    var variables = std.StringHashMap(Parsed.Variable.Kind).init(allocator);

    for (block.operations.items) |opp| {
        switch (opp.kind) {
            .Decl => {
                const op = @fieldParentPtr(Parsed.Operation.Decl, "base", opp);
                for (op.decls) |decl| try variables.put(decl, op.kind);
            },
            .Set => {
                const op = @fieldParentPtr(Parsed.Operation.Set, "base", opp);
                for (op.outputs) |out| {
                    if (!variables.contains(out.name)) std.debug.panic("Variable {} does not exist!", .{out.name});
                    switch (op.input) {
                        .Literal => |l| {
                            if (@enumToInt(variables.get(out.name).?) != @enumToInt(l))
                                std.debug.panic("Type mismatch between {} and {}!", .{ variables.get(out.name).?, l });
                        },
                        .Variable => |v| {
                            if (!variables.contains(v.name)) std.debug.panic("Variable {} does not exist!", .{v.name});
                            if (@enumToInt(variables.get(out.name).?) != @enumToInt(variables.get(v.name).?))
                                std.debug.panic("Type mismatch between {} and {}!", .{ variables.get(out.name).?, variables.get(v.name).? });
                        },
                        .Operation => {},
                    }
                }
            },
            else => {},
        }
    }

    for (variables.items()) |entry| {
        std.debug.print("{}: {}\n", .{ entry.key, entry.value });
    }

    return variables;
}

fn parseBlock(allocator: *mem.Allocator, tokens: []const tk.Token, blockStart: usize, blockEnd: usize) anyerror!Parsed.Block {
    var block = Parsed.Block.init(allocator);

    var i: usize = blockStart;
    while (i < blockEnd) {
        switch (tokens[i]) {
            .DeclSym => {
                i += 1;

                if (tokens[i] != .LParen) std.debug.panic("Expected LParen `(` token, found {} at index {}", .{ tokens[i], i });
                i += 1;

                const operation = try allocator.create(Parsed.Operation.Decl);
                operation.*.base = .{ .kind = .Decl };

                if (tokens[i] != .TypeSym) std.debug.panic("Expected TypeSym `$` token, found {} at index {}", .{ tokens[i], i });
                i += 1;

                if (tokens[i] != .Ident) std.debug.panic("Expected Ident token, found {} at index {}", .{ tokens[i], i });
                operation.*.kind = BuiltinTypeMap.get(tokens[i].Ident) orelse std.debug.panic("Expected a type, found {} at index {}", .{ tokens[i], i });
                i += 1;

                if (tokens[i] != .Comma) std.debug.panic("Expected Comma `,` token, found {} at index {}", .{ tokens[i], i });
                i += 1;

                var decls = std.ArrayList([]const u8).init(allocator);
                defer decls.deinit();
                while (true) {
                    switch (tokens[i]) {
                        .Ident => if (mem.startsWith(u8, tokens[i].Ident, "__")) {
                            try block.var_in.put(tokens[i].Ident, operation.*.kind);
                        } else if (mem.startsWith(u8, tokens[i].Ident, "_")) {
                            if (block.var_out == null) {
                                block.var_out = .{ .name = tokens[i].Ident, .kind = operation.*.kind };
                                try decls.append(tokens[i].Ident);
                            } else std.debug.panic("Out variable already exists!", .{});
                        } else {
                            try decls.append(tokens[i].Ident);
                        },

                        .Comma => {},
                        else => std.debug.panic("Expected Ident or Comma `,` token, found {} at index {}", .{ tokens[i], i }),
                    }
                    i += 1;
                    if (tokens[i] == .RParen) break;
                }
                operation.*.decls = decls.toOwnedSlice();
                i += 1;

                if (operation.*.decls.len == 0) {
                    allocator.destroy(operation);
                    continue;
                }
                try block.operations.append(&operation.base);
            },
            .SetSym => {
                i += 1;

                if (tokens[i] != .LParen) std.debug.panic("Expected LParen `(` token, found {} at index {}", .{ tokens[i], i });
                i += 1;

                const operation = try allocator.create(Parsed.Operation.Set);
                operation.*.base = .{ .kind = .Set };

                switch (tokens[i]) {
                    .Ident => operation.*.input = .{ .Variable = .{ .name = tokens[i].Ident, .kind = null } },

                    .Integer => operation.*.input = .{ .Literal = .{ .Integer = tokens[i].Integer.num } },
                    .Number => operation.*.input = .{ .Literal = .{ .Number = tokens[i].Number.num } },
                    .String => operation.*.input = .{ .Literal = .{ .String = tokens[i].String } },
                    .Bool => operation.*.input = .{ .Literal = .{ .Bool = tokens[i].Bool } },

                    .Void => operation.*.input = .{ .Literal = .{ .Void = {} } },

                    .LBrace => {
                        var end: usize = 1;
                        var seen_start = false;
                        while (i + end < blockEnd) {
                            if (tokens[i + end] == .RBrace and !seen_start) break;
                            if (tokens[i + end] == .LBrace) seen_start = true;
                            if (tokens[i + end] == .RBrace and seen_start) seen_start = false;
                            end += 1;
                        }
                        operation.*.input = .{ .Literal = .{ .Block = try parseBlock(allocator, tokens, i + 1, i + end) } };
                        i += end;
                    },

                    .CallSym => operation.*.input = .{ .Operation = try parseOpCall(allocator, tokens, &i) },

                    else => std.debug.panic("Expected CallSym `!`, Ident, LBrace `{{`, or Literal token, found {} at index {}", .{ tokens[i], i }),
                }
                i += 1;

                if (tokens[i] != .Comma) std.debug.panic("Expected Comma `,` token, found {} at index {}", .{ tokens[i], i });
                i += 1;

                var outputs = std.ArrayList(Parsed.Variable).init(allocator);
                defer outputs.deinit();
                while (true) {
                    switch (tokens[i]) {
                        .Ident => try outputs.append(.{ .name = tokens[i].Ident, .kind = null }),

                        .Comma => {},
                        else => std.debug.panic("Expected Ident or Comma `,` token, found {} at index {}", .{ tokens[i], i }),
                    }
                    i += 1;
                    if (tokens[i] == .RParen) break;
                }
                operation.*.outputs = outputs.toOwnedSlice();
                i += 1;

                try block.operations.append(&operation.base);
            },
            .CallSym => {
                try block.operations.append(try parseOpCall(allocator, tokens, &i));
                i += 1;
            },
            .IfSym => {
                i += 1;

                if (tokens[i] != .LParen) std.debug.panic("Expected LParen `(` token, found {} at index {}", .{ tokens[i], i });
                i += 1;

                const operation = try allocator.create(Parsed.Operation.If);
                operation.*.base = .{ .kind = .If };

                switch (tokens[i]) {
                    .Ident => operation.*.input = .{ .Variable = .{ .name = tokens[i].Ident, .kind = null } },

                    .Integer => operation.*.input = .{ .Literal = .{ .Integer = tokens[i].Integer.num } },
                    .Number => operation.*.input = .{ .Literal = .{ .Number = tokens[i].Number.num } },
                    .String => operation.*.input = .{ .Literal = .{ .String = tokens[i].String } },
                    .Bool => operation.*.input = .{ .Literal = .{ .Bool = tokens[i].Bool } },

                    .CallSym => operation.*.input = .{ .Operation = try parseOpCall(allocator, tokens, &i) },

                    else => std.debug.panic("Expected CallSym `!`, Ident, LBrace `{{`, or Literal token, found {} at index {}", .{ tokens[i], i }),
                }
                i += 1;

                if (tokens[i] != .Comma) std.debug.panic("Expected Comma `,` token, found {} at index {}", .{ tokens[i], i });
                i += 1;

                switch (tokens[i]) {
                    .Ident => operation.*.comp = .{ .Variable = .{ .name = tokens[i].Ident, .kind = null } },

                    .Integer => operation.*.comp = .{ .Literal = .{ .Integer = tokens[i].Integer.num } },
                    .Number => operation.*.comp = .{ .Literal = .{ .Number = tokens[i].Number.num } },
                    .String => operation.*.comp = .{ .Literal = .{ .String = tokens[i].String } },
                    .Bool => operation.*.comp = .{ .Literal = .{ .Bool = tokens[i].Bool } },

                    .CallSym => operation.*.comp = .{ .Operation = try parseOpCall(allocator, tokens, &i) },

                    else => std.debug.panic("Expected CallSym `!`, Ident, LBrace `{{`, or Literal token, found {} at index {}", .{ tokens[i], i }),
                }
                i += 1;

                if (tokens[i] != .Comma) std.debug.panic("Expected Comma `,` token, found {} at index {}", .{ tokens[i], i });
                i += 1;

                if (tokens[i] == .LBrace) {
                    var end: usize = 1;
                    var seen_start = false;
                    while (i + end < blockEnd) {
                        if (tokens[i + end] == .RBrace and !seen_start) break;
                        if (tokens[i + end] == .LBrace) seen_start = true;
                        if (tokens[i + end] == .RBrace and seen_start) seen_start = false;
                        end += 1;
                    }
                    operation.*.ifblock = try parseBlock(allocator, tokens, i + 1, i + end);
                    i += end;
                } else std.debug.panic("Expected LBrace `{{` token, found {} at index {}", .{ tokens[i], i });
                i += 1;

                if (tokens[i] == .Comma) {
                    i += 1;
                    if (tokens[i] == .LBrace) {
                        var end: usize = 1;
                        var seen_start = false;
                        while (i + end < blockEnd) {
                            if (tokens[i + end] == .RBrace and !seen_start) break;
                            if (tokens[i + end] == .LBrace) seen_start = true;
                            if (tokens[i + end] == .RBrace and seen_start) seen_start = false;
                            end += 1;
                        }
                        operation.*.elseblock = try parseBlock(allocator, tokens, i + 1, i + end);
                        i += end;
                    } else std.debug.panic("Expected LBrace `{{` token, found {} at index {}", .{ tokens[i], i });
                    i += 1;
                }

                if (tokens[i] != .RParen) std.debug.panic("Expected RParen `)` token, found {} at index {}", .{ tokens[i], i });
                i += 1;

                try block.operations.append(&operation.base);
            },
            .WhileSym => {
                i += 1;

                if (tokens[i] != .LParen) std.debug.panic("Expected LParen `(` token, found {} at index {}", .{ tokens[i], i });
                i += 1;

                const operation = try allocator.create(Parsed.Operation.While);
                operation.*.base = .{ .kind = .While };

                switch (tokens[i]) {
                    .Ident => operation.*.input = .{ .Variable = .{ .name = tokens[i].Ident, .kind = null } },

                    .Integer => operation.*.input = .{ .Literal = .{ .Integer = tokens[i].Integer.num } },
                    .Number => operation.*.input = .{ .Literal = .{ .Number = tokens[i].Number.num } },
                    .String => operation.*.input = .{ .Literal = .{ .String = tokens[i].String } },
                    .Bool => operation.*.input = .{ .Literal = .{ .Bool = tokens[i].Bool } },

                    .CallSym => operation.*.input = .{ .Operation = try parseOpCall(allocator, tokens, &i) },

                    else => std.debug.panic("Expected CallSym `!`, Ident, LBrace `{{`, or Literal token, found {} at index {}", .{ tokens[i], i }),
                }
                i += 1;

                if (tokens[i] != .Comma) std.debug.panic("Expected Comma `,` token, found {} at index {}", .{ tokens[i], i });
                i += 1;

                switch (tokens[i]) {
                    .Ident => operation.*.comp = .{ .Variable = .{ .name = tokens[i].Ident, .kind = null } },

                    .Integer => operation.*.comp = .{ .Literal = .{ .Integer = tokens[i].Integer.num } },
                    .Number => operation.*.comp = .{ .Literal = .{ .Number = tokens[i].Number.num } },
                    .String => operation.*.comp = .{ .Literal = .{ .String = tokens[i].String } },
                    .Bool => operation.*.comp = .{ .Literal = .{ .Bool = tokens[i].Bool } },

                    .CallSym => operation.*.comp = .{ .Operation = try parseOpCall(allocator, tokens, &i) },

                    else => std.debug.panic("Expected CallSym `!`, Ident, LBrace `{{`, or Literal token, found {} at index {}", .{ tokens[i], i }),
                }
                i += 1;

                if (tokens[i] != .Comma) std.debug.panic("Expected Comma `,` token, found {} at index {}", .{ tokens[i], i });
                i += 1;

                if (tokens[i] == .LBrace) {
                    var end: usize = 1;
                    var seen_start = false;
                    while (i + end < blockEnd) {
                        if (tokens[i + end] == .RBrace and !seen_start) break;
                        if (tokens[i + end] == .LBrace) seen_start = true;
                        if (tokens[i + end] == .RBrace and seen_start) seen_start = false;
                        end += 1;
                    }
                    operation.*.block = try parseBlock(allocator, tokens, i + 1, i + end);
                    i += end;
                } else std.debug.panic("Expected LBrace `{{` token, found {} at index {}", .{ tokens[i], i });
                i += 1;

                if (tokens[i] != .RParen) std.debug.panic("Expected RParen `)` token, found {} at index {}", .{ tokens[i], i });
                i += 1;

                try block.operations.append(&operation.base);
            },

            else => std.debug.panic("Unexpected Token: {} at index {}\n", .{ tokens[i], i }),
        }
    }

    return block;
}

fn parseOpCall(allocator: *mem.Allocator, tokens: []const tk.Token, i: *usize) anyerror!*Parsed.Operation {
    i.* += 1;

    if (tokens[i.*] != .LParen) std.debug.panic("Expected LParen `(` token, found {} at index {}", .{ tokens[i.*], i.* });
    i.* += 1;

    const operation = try allocator.create(Parsed.Operation.Call);
    operation.*.base = .{ .kind = .Call };

    if (tokens[i.*] != .Ident) std.debug.panic("Expected Ident token, found {} at index {}", .{ tokens[i.*], i.* });
    operation.*.func = tokens[i.*].Ident;
    i.* += 1;

    if (tokens[i.*] != .Comma) std.debug.panic("Expected Comma `,` token, found {} at index {}", .{ tokens[i.*], i.* });
    i.* += 1;

    var inputs = std.ArrayList(Parsed.Operation.Input).init(allocator);
    defer inputs.deinit();
    while (true) {
        switch (tokens[i.*]) {
            .Ident => try inputs.append(.{ .Variable = .{ .name = tokens[i.*].Ident, .kind = null } }),

            .Integer => try inputs.append(.{ .Literal = .{ .Integer = tokens[i.*].Integer.num } }),
            .Number => try inputs.append(.{ .Literal = .{ .Number = tokens[i.*].Number.num } }),
            .String => try inputs.append(.{ .Literal = .{ .String = tokens[i.*].String } }),
            .Bool => try inputs.append(.{ .Literal = .{ .Bool = tokens[i.*].Bool } }),

            .Void => try inputs.append(.{ .Literal = .{ .Void = {} } }),

            .CallSym => try inputs.append(.{ .Operation = try parseOpCall(allocator, tokens, i) }),

            .Comma => {},
            else => std.debug.panic("Expected CallSym `!`, Ident, Literal, or Comma `,` token, found {} at index {}", .{ tokens[i.*], i.* }),
        }
        i.* += 1;
        if (tokens[i.*] == .RParen) break;
    }
    operation.*.inputs = inputs.toOwnedSlice();

    return &operation.base;
}
