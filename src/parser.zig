const std = @import("std");
const Allocator = std.mem.Allocator;

const tk = @import("tokenizer.zig");
const Token = tk.Token;

const ast = @import("ast.zig");
const Tree = ast.Tree;

pub fn parse(gpa: *Allocator, source: []const u8) !*Tree {
    const tokens = try tk.tokenize(gpa, source);
    errdefer gpa.free(tokens);

    var arena = std.heap.ArenaAllocator.init(gpa);
    errdefer arena.deinit();

    var parser = Parser{
        .tokens = tokens,
        .source = source,

        .arena = &arena.allocator,
        .gpa = gpa,
    };

    while (true) switch (tokens[parser.index].kind) {
        .LineComment, .DocComment => parser.index += 1,
        else => break,
    };

    const root = try parser.block(0);

    const tree = try parser.arena.create(Tree);
    tree.* = Tree{
        .tokens = tokens,
        .source = source,

        .arena = arena.state,
        .gpa = gpa,

        .types = std.StringArrayHashMap(ast.Type).init(gpa),

        .root = root,
    };
    return tree;
}

pub const Parser = struct {
    tokens: []const Token,
    source: []const u8,

    arena: *Allocator,
    gpa: *Allocator,

    index: usize = 0,

    pub fn block(self: *Parser, level: u8) anyerror!ast.Block {
        var ops = std.ArrayList(ast.Op).init(self.arena);
        defer ops.deinit();

        while (true) {
            const tok = self.peekToken();
            switch (self.tokens[tok].kind) {
                .RBrace, .Eof => {
                    _ = self.nextToken();
                    break;
                },
                else => try ops.append(try self.op(level)),
            }
        }

        return ast.Block{
            .ops = ops.toOwnedSlice(),
        };
    }

    pub fn op(self: *Parser, level: u8) anyerror!ast.Op {
        if (try self.write(level)) |o| return o;
        if (try self.call(level)) |o| return o;
        if (try self.builtin(level)) |o| return o;
        if (try self.branch(level)) |o| return o;
        if (try self.macro(level)) |o| return o;
        std.debug.panic("invalid op {}", .{self.tokens[self.index]});
    }

    fn write(self: *Parser, level: u8) anyerror!?ast.Op {
        const first_tok = self.eatToken(.Dollar) orelse return null;
        const c = try self.cap();
        const wtype = (try self.expr(level)) orelse @panic("expected a type");

        _ = self.eatToken(.Colon) orelse @panic("expected a :");

        const value = if (self.eatToken(.Equal)) |_| (try self.expr(level)) orelse @panic("expected value") else null;

        return ast.Op{
            .Write = .{
                .cap = c,
                .wtype = wtype,

                .value = value,
            },
        };
    }

    fn call(self: *Parser, level: u8) anyerror!?ast.Op {
        const first_tok = self.eatToken(.Bang) orelse return null;
        const c = try self.cap();

        switch (self.tokens[self.index].kind) {
            .LParen, .LAngle => {
                _ = self.nextToken();
                const args = try self.tuple(level);

                return ast.Op{
                    .Call = .{
                        .cap = c,

                        .args = args,
                    },
                };
            },
            else => {
                return ast.Op{
                    .Call = .{
                        .cap = c,

                        .args = null,
                    },
                };
            },
        }
    }

    fn builtin(self: *Parser, level: u8) anyerror!?ast.Op {
        const first_tok = self.eatToken(.At) orelse return null;
        const c = try self.cap();

        switch (self.tokens[self.index].kind) {
            .LParen, .LAngle => {
                _ = self.nextToken();
                const args = try self.tuple(level);

                return ast.Op{
                    .BuiltinCall = .{
                        .cap = c,

                        .args = args,
                    },
                };
            },
            else => {
                return ast.Op{
                    .BuiltinCall = .{
                        .cap = c,

                        .args = null,
                    },
                };
            },
        }
    }

    fn macro(self: *Parser, level: u8) anyerror!?ast.Op {
        const first_tok = self.eatToken(.Percent) orelse return null;
        const c = try self.cap();

        switch (self.tokens[self.index].kind) {
            .LParen, .LAngle => {
                _ = self.nextToken();
                const args = try self.tuple(level);
                return ast.Op{
                    .MacroCall = .{
                        .cap = c,

                        .args = args,
                    },
                };
            },
            else => {
                return ast.Op{
                    .MacroCall = .{
                        .cap = c,

                        .args = null,
                    },
                };
            },
        }
    }

    fn branch(self: *Parser, level: u8) anyerror!?ast.Op {
        const first_tok = self.eatToken(.Caret) orelse return null;
        const c = try self.cap();

        _ = self.eatToken(.LParen) orelse std.debug.panic("expected ( found {}", .{self.tokens[self.index]});
        const args = try self.tuple(level);

        return ast.Op{
            .Branch = .{
                .cap = c,

                .args = args,
            },
        };
    }

    fn add(self: *Parser, level: u8) anyerror!?ast.Op {
        const first_tok = self.eatToken(.HashAdd) orelse return null;

        _ = self.eatToken(.LParen) orelse std.debug.panic("expected ( found {}", .{self.tokens[self.index]});
        const args = try self.tuple(level);

        return ast.Op{
            .Add = .{
                .args = args,
            },
        };
    }

    fn sub(self: *Parser, level: u8) anyerror!?ast.Op {
        const first_tok = self.eatToken(.HashSub) orelse return null;

        _ = self.eatToken(.LParen) orelse std.debug.panic("expected ( found {}", .{self.tokens[self.index]});
        const args = try self.tuple(level);

        return ast.Op{
            .Sub = .{
                .args = args,
            },
        };
    }

    fn expr(self: *Parser, level: u8) anyerror!?*ast.Expr {
        const e = try self.arena.create(ast.Expr);

        const tok = self.peekToken();
        switch (self.tokens[tok].kind) {
            // Literals
            .LiteralFloat => {
                _ = self.nextToken();
                e.* = .{ .expr = .{ .Literal = .{ .Float = try std.fmt.parseFloat(f64, self.getTokSource(tok)) } } };
            },
            .LiteralInteger => {
                _ = self.nextToken();
                e.* = .{ .expr = .{ .Literal = .{ .Integer = try std.fmt.parseInt(i64, self.getTokSource(tok), 10) } } };
            },
            .LiteralString => {
                _ = self.nextToken();
                e.* = .{ .expr = .{ .Literal = .{ .String = self.getTokSource(tok) } } };
            },
            .Ident => {
                _ = self.nextToken();
                e.* = .{ .expr = .{ .Ident = self.getTokSource(tok) } };
            },
            // Groups
            .LParen => {
                _ = self.nextToken();
                e.* = .{ .expr = .{ .Tuple = try self.tuple(level + 1) } };
            },
            .LBrace => {
                _ = self.nextToken();
                e.* = .{ .expr = .{ .Block = try self.block(level + 1) } };
            },
            .LBracket => {
                _ = self.nextToken();
                e.* = .{ .expr = .{ .Array = try self.array(level + 1) } };
            },

            // Ops
            .At => e.* = .{ .expr = .{ .Op = (try self.builtin(level)) orelse unreachable } },
            .Bang => e.* = .{ .expr = .{ .Op = (try self.call(level)) orelse unreachable } },
            .Percent => e.* = .{ .expr = .{ .Op = (try self.macro(level)) orelse unreachable } },
            .HashAdd => e.* = .{ .expr = .{ .Op = (try self.add(level)) orelse unreachable } },
            .HashSub => e.* = .{ .expr = .{ .Op = (try self.sub(level)) orelse unreachable } },

            else => {
                self.arena.destroy(e);
                return null;
            },
        }

        if (self.tokens[tok + 1].kind == .Period) {
            self.index += 1;

            const s = try self.arena.create(ast.Expr);
            s.* = .{ .expr = .{
                .Scope = .{
                    .lhs = e,
                    .rhs = (try self.expr(level)) orelse @panic("random . at end of expr"),
                },
            }};
            return s;
        }

        return e;
    }

    fn cap(self: *Parser) anyerror!*ast.Cap {
        const c = try self.arena.create(ast.Cap);

        const tok = self.nextToken();
        switch (self.tokens[tok].kind) {
            .Ident => {
                if (self.tokens[tok + 1].kind == .Period) {
                    const ic = try self.arena.create(ast.Cap);
                    ic.* = .{ .Ident = self.getTokSource(tok) };
                    c.* = .{
                        .Scope = .{
                            .lhs = ic,
                            .rhs = try self.cap(),
                        },
                    };
                } else {
                    c.* = .{ .Ident = self.getTokSource(tok) };
                }
            },
            .Period => {
                const itok = self.eatToken(.Ident) orelse std.debug.panic("expected ident found {}", .{self.tokens[self.index]});
                const ic = try self.arena.create(ast.Cap);
                ic.* = .{ .Ident = self.getTokSource(itok) };
                c.* = .{
                    .Scope = .{
                        .lhs = null,
                        .rhs = ic,
                    },
                };
            },
            else => std.debug.panic("invalid cap {}", .{self.tokens[tok]}),
        }

        return c;
    }

    fn array(self: *Parser, level: u8) anyerror!ast.Array {
        var items = std.ArrayList(*ast.Expr).init(self.arena);
        defer items.deinit();

        while (true) {
            const tok = self.nextToken();
            switch (self.tokens[tok].kind) {
                .Comma => {},
                .RBracket => break,
                else => {
                    self.index -= 1;
                    try items.append((try self.expr(level)) orelse @panic("expected expr for item in tuple"));
                },
            }
        }
        
        return ast.Array{
            .items = items.toOwnedSlice(),
        };
    }

    fn tuple(self: *Parser, level: u8) anyerror!ast.Tuple {
        var items = std.ArrayList(*ast.Expr).init(self.arena);
        defer items.deinit();

        while (true) {
            const tok = self.nextToken();
            switch (self.tokens[tok].kind) {
                .Comma => {},
                .RParen => break,
                else => {
                    self.index -= 1;
                    try items.append((try self.expr(level)) orelse @panic("expected expr for item in tuple"));
                },
            }
        }
        
        return ast.Tuple{
            .items = items.toOwnedSlice(),
        };
    }

    fn eatToken(self: *Parser, kind: Token.Kind) ?usize {
        return if (self.tokens[self.index].kind == kind) self.nextToken() else null;
    }

    fn nextToken(self: *Parser) usize {
        const res = self.index;
        self.index += 1;

        if (self.index >= self.tokens.len) return res;
        while (true) {
            switch (self.tokens[self.index].kind) {
                .LineComment, .DocComment => {},
                else => break,
            }
            self.index += 1;
        }

        return res;
    }

    fn peekToken(self: *Parser) usize {
        const curr_index = self.index;
        const tok = self.nextToken();
        self.index = curr_index;
        return tok;
    }

    pub fn getTokSource(self: *Parser, tok: usize) []const u8 {
        return self.source[self.tokens[tok].start..self.tokens[tok].end];
    }
};
