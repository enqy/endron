const std = @import("std");
const Allocator = std.mem.Allocator;

const tokenizer = @import("tokenizer.zig");
const Token = tokenizer.Token;

const ast = @import("ast.zig");
const Tree = ast.Tree;

pub fn parse(alloc: Allocator, source: []const u8, tokens: []const Token) !*Tree {
    var arena = std.heap.ArenaAllocator.init(alloc);
    errdefer arena.deinit();

    var parser = Parser{
        .alloc = alloc,
        .arena = arena.allocator(),

        .source = source,
        .tokens = tokens,
    };

    // skip initial comments
    while (true) switch (tokens[parser.token_index].kind) {
        .line_comment, .doc_comment => parser.token_index += 1,
        else => break,
    };

    const root = try parser.block(0);

    const tree = try parser.arena.create(Tree);
    tree.* = Tree{
        .alloc = alloc,
        .arena = arena.state,

        .source = source,
        .tokens = tokens,

        .root = root,
    };
    return tree;
}

pub const Parser = struct {
    alloc: Allocator,
    arena: Allocator,

    source: []const u8,
    tokens: []const Token,

    token_index: usize = 0,

    pub fn block(self: *Parser, level: usize) anyerror!ast.Block {
        var ops = std.ArrayList(ast.Op).init(self.arena);
        defer ops.deinit();

        while (true) {
            const token = self.peekToken();
            switch (self.tokens[token].kind) {
                .rbrace, .eof => {
                    _ = self.nextToken();
                    break;
                },
                else => try ops.append(try self.op(level)),
            }
        }

        return ast.Block{
            .ops = try ops.toOwnedSlice(),
        };
    }

    fn op(self: *Parser, level: usize) !ast.Op {
        if (try self.opDecl(level)) |o| return o;
        if (try self.opType(level)) |o| return o;
        if (try self.opSet(level)) |o| return o;
        if (try self.opCall(level)) |o| return o;
        if (try self.opBuiltin(level)) |o| return o;
        if (try self.opBranch(level)) |o| return o;
        if (try self.opLoop(level)) |o| return o;
        if (try self.opAlu(level)) |o| return o;
        std.debug.panic("unexpected `{s}` at {}:{}", .{ self.getTokenSource(self.token_index), self.tokens[self.token_index].line, self.tokens[self.token_index].column });
    }

    fn opDecl(self: *Parser, level: usize) !?ast.Op {
        _ = self.eatToken(.at) orelse return null;

        const cap = try self.expr(level);

        _ = self.eatToken(.semicolon) orelse {
            std.debug.panic("expected `;` at {}:{}", .{ self.tokens[self.token_index].line, self.tokens[self.token_index].column });
        };

        const type_expr = try self.expr(level);

        _ = self.eatToken(.comma) orelse return ast.Op{ .decl = .{
            .cap = cap,
            .type = type_expr,
            .value = null,
        } };

        const value = try self.expr(level);

        return ast.Op{ .decl = .{
            .cap = cap,
            .type = type_expr,
            .value = value,
        } };
    }

    fn opType(self: *Parser, level: usize) anyerror!?ast.Op {
        _ = self.eatToken(.dollar) orelse return null;

        const cap = try self.expr(level);

        _ = self.eatToken(.semicolon) orelse return ast.Op{ .type = .{
            .cap = cap,
            .args = null,
        } };

        var args = std.ArrayList(*ast.Expr).init(self.arena);
        defer args.deinit();

        try args.append(try self.expr(level));

        var maybe_comma_token = self.peekToken();
        while (self.tokens[maybe_comma_token].kind == .comma) {
            _ = self.nextToken();
            try args.append(try self.expr(level));
            maybe_comma_token = self.peekToken();
        }

        return ast.Op{ .type = .{
            .cap = cap,
            .args = try args.toOwnedSlice(),
        } };
    }

    fn opSet(self: *Parser, level: usize) !?ast.Op {
        _ = self.eatToken(.tilde) orelse return null;

        const cap = try self.expr(level);

        _ = self.eatToken(.semicolon) orelse {
            std.debug.panic("expected `;` at {}:{}", .{ self.tokens[self.token_index].line, self.tokens[self.token_index].column });
        };

        var args = std.ArrayList(*ast.Expr).init(self.arena);
        defer args.deinit();

        try args.append(try self.expr(level));

        var maybe_comma_token = self.peekToken();
        while (self.tokens[maybe_comma_token].kind == .comma) {
            _ = self.nextToken();
            try args.append(try self.expr(level));
            maybe_comma_token = self.peekToken();
        }

        return ast.Op{ .set = .{
            .cap = cap,
            .args = try args.toOwnedSlice(),
        } };
    }

    fn opCall(self: *Parser, level: usize) !?ast.Op {
        _ = self.eatToken(.bang) orelse return null;

        const cap = try self.expr(level);

        _ = self.eatToken(.semicolon) orelse {
            std.debug.panic("expected `;` at {}:{}", .{ self.tokens[self.token_index].line, self.tokens[self.token_index].column });
        };

        var args = std.ArrayList(*ast.Expr).init(self.arena);
        defer args.deinit();

        try args.append(try self.expr(level));

        var maybe_comma_token = self.peekToken();
        while (self.tokens[maybe_comma_token].kind == .comma) {
            _ = self.nextToken();
            try args.append(try self.expr(level));
            maybe_comma_token = self.peekToken();
        }

        return ast.Op{ .call = .{
            .cap = cap,
            .args = try args.toOwnedSlice(),
        } };
    }

    fn opBuiltin(self: *Parser, level: usize) !?ast.Op {
        _ = self.eatToken(.pipe) orelse return null;

        const cap = try self.expr(level);

        _ = self.eatToken(.semicolon) orelse {
            std.debug.panic("expected `;` at {}:{}", .{ self.tokens[self.token_index].line, self.tokens[self.token_index].column });
        };

        var args = std.ArrayList(*ast.Expr).init(self.arena);
        defer args.deinit();

        try args.append(try self.expr(level));

        var maybe_comma_token = self.peekToken();
        while (self.tokens[maybe_comma_token].kind == .comma) {
            _ = self.nextToken();
            try args.append(try self.expr(level));
            maybe_comma_token = self.peekToken();
        }

        return ast.Op{ .builtin = .{
            .cap = cap,
            .args = try args.toOwnedSlice(),
        } };
    }

    fn opBranch(self: *Parser, level: usize) !?ast.Op {
        _ = self.eatToken(.question_mark) orelse return null;

        const cond = try self.expr(level);

        _ = self.eatToken(.semicolon) orelse {
            std.debug.panic("expected `;` at {}:{}", .{ self.tokens[self.token_index].line, self.tokens[self.token_index].column });
        };

        const if_true = try self.expr(level);

        _ = self.eatToken(.comma) orelse {
            std.debug.panic("expected `,` at {}:{}", .{ self.tokens[self.token_index].line, self.tokens[self.token_index].column });
        };

        const if_false = try self.expr(level);

        return ast.Op{ .branch = .{
            .cond = cond,
            .if_true = if_true,
            .if_false = if_false,
        } };
    }

    fn opLoop(self: *Parser, level: usize) !?ast.Op {
        _ = self.eatToken(.percent) orelse return null;

        const cond = try self.expr(level);

        _ = self.eatToken(.semicolon) orelse {
            std.debug.panic("expected `;` at {}:{}", .{ self.tokens[self.token_index].line, self.tokens[self.token_index].column });
        };

        const body = try self.expr(level);

        _ = self.eatToken(.comma) orelse return ast.Op{ .loop = .{
            .cond = cond,
            .body = body,
            .early = null,
        } };

        const early = try self.expr(level);

        return ast.Op{ .loop = .{
            .cond = cond,
            .body = body,
            .early = early,
        } };
    }

    fn opAlu(self: *Parser, level: usize) !?ast.Op {
        _ = self.eatToken(.number_sign) orelse return null;

        const func = try self.aluFunc();

        _ = self.eatToken(.semicolon) orelse {
            std.debug.panic("expected `;` at {}:{}", .{ self.tokens[self.token_index].line, self.tokens[self.token_index].column });
        };

        var args = std.ArrayList(*ast.Expr).init(self.arena);
        defer args.deinit();

        try args.append(try self.expr(level));

        var maybe_comma_token = self.peekToken();
        while (self.tokens[maybe_comma_token].kind == .comma) {
            _ = self.nextToken();
            try args.append(try self.expr(level));
            maybe_comma_token = self.peekToken();
        }

        return ast.Op{ .alu = .{
            .func = func,
            .args = try args.toOwnedSlice(),
        } };
    }

    fn aluFunc(self: *Parser) !ast.Op.Alu.Func {
        const token = self.nextToken();
        switch (self.tokens[token].kind) {
            .plus => return ast.Op.Alu.Func.add,
            .minus => return ast.Op.Alu.Func.sub,
            .asterisk => return ast.Op.Alu.Func.mul,
            .double_asterisk => return ast.Op.Alu.Func.pow,
            .slash => return ast.Op.Alu.Func.div,
            .greater_than => return ast.Op.Alu.Func.gt,
            .less_than => return ast.Op.Alu.Func.lt,
            .equal => return ast.Op.Alu.Func.eql,
            else => std.debug.panic("unexpected `{s}` at {}:{}", .{ self.getTokenSource(token), self.tokens[token].line, self.tokens[token].column }),
        }
    }

    fn expr(self: *Parser, level: usize) !*ast.Expr {
        const e = try self.arena.create(ast.Expr);

        var token = self.peekToken();
        switch (self.tokens[token].kind) {
            .ident => {
                token = self.nextToken();
                e.* = ast.Expr{ .expr = .{ .ident = self.getTokenSource(token) } };
            },
            .literal_string => {
                token = self.nextToken();
                const string = self.getTokenSource(token);
                e.* = ast.Expr{ .expr = .{ .literal = .{ .string = string[1 .. string.len - 1] } } };
            },
            .literal_number => {
                token = self.nextToken();
                e.* = ast.Expr{ .expr = .{ .literal = .{ .number = try std.fmt.parseInt(i64, self.getTokenSource(token), 10) } } };
            },
            .literal_decimal => {
                token = self.nextToken();
                e.* = ast.Expr{ .expr = .{ .literal = .{ .decimal = try std.fmt.parseFloat(f64, self.getTokenSource(token)) } } };
            },
            .lbrace => {
                token = self.nextToken();
                e.* = ast.Expr{ .expr = .{ .block = try self.block(level + 1) } };
            },
            .dollar => {
                var ops = try self.arena.alloc(ast.Op, 1);
                ops[0] = (try self.opType(level)) orelse unreachable;

                e.* = ast.Expr{ .expr = .{ .block = .{ .ops = ops } } };
            },
            .colon => {
                e.* = ast.Expr{ .expr = .{ .scope = try self.scope(level) } };
            },
            else => std.debug.panic("unexpected `{s}` at {}:{}", .{ self.getTokenSource(self.token_index), self.tokens[self.token_index].line, self.tokens[self.token_index].column }),
        }

        return e;
    }

    fn scope(self: *Parser, level: usize) !ast.Scope {
        _ = self.eatToken(.colon) orelse {
            std.debug.panic("expected `:` at {}:{}", .{
                self.tokens[self.token_index].line,
                self.tokens[self.token_index].column,
            });
        };

        var path = std.ArrayList(ast.Ident).init(self.arena);
        defer path.deinit();
        var root: i64 = @intCast(i64, level);
        var upper: usize = 0;

        const token = self.peekToken();
        switch (self.tokens[token].kind) {
            .period => {
                _ = self.nextToken();
                root -= 1;
                while (self.tokens[self.peekToken()].kind == .period) {
                    _ = self.nextToken();
                    root -= 1;
                    upper += 1;
                }
            },
            .caret => {
                _ = self.nextToken();
                root = 0;
            },
            .underscore => {
                _ = self.nextToken();
                root = -1;
            },
            .ident => {
                _ = self.nextToken();
                try path.append(self.getTokenSource(token));
                root = @intCast(i64, level);
            },
            else => std.debug.panic("unexpected `{s}` at {}:{}", .{ self.getTokenSource(self.token_index), self.tokens[self.token_index].line, self.tokens[self.token_index].column }),
        }

        _ = self.eatToken(.period);

        const root_path_token = self.eatToken(.ident) orelse {
            std.debug.panic("expected identifier after `{s}` at {}:{}", .{ self.getTokenSource(self.token_index - 1), self.tokens[self.token_index].line, self.tokens[self.token_index].column });
        };
        try path.append(self.getTokenSource(root_path_token));

        var period_token = self.peekToken();
        while (self.tokens[period_token].kind == .period) {
            _ = self.nextToken();
            const ident_token = self.eatToken(.ident) orelse {
                std.debug.panic("expected identifier after `.` at {}:{}", .{ self.tokens[self.token_index].line, self.tokens[self.token_index].column });
            };
            try path.append(self.getTokenSource(ident_token));
            period_token = self.peekToken();
        }

        return ast.Scope{
            .root = root,
            .upper = upper,
            .path = try path.toOwnedSlice(),
        };
    }

    fn eatToken(self: *Parser, kind: Token.Kind) ?usize {
        return if (self.tokens[self.token_index].kind == kind) self.nextToken() else null;
    }

    // skip comments
    fn nextToken(self: *Parser) usize {
        const res = self.token_index;
        self.token_index += 1;

        if (self.token_index >= self.tokens.len) return res;
        while (true) {
            switch (self.tokens[self.token_index].kind) {
                .line_comment, .doc_comment => {},
                else => break,
            }
            self.token_index += 1;
        }

        return res;
    }

    fn peekToken(self: *Parser) usize {
        const curr_index = self.token_index;
        const tok = self.nextToken();
        self.token_index = curr_index;
        return tok;
    }

    fn getTokenSource(self: *Parser, tok: usize) []const u8 {
        return self.source[self.tokens[tok].start..self.tokens[tok].end];
    }
};
