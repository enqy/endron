const std = @import("std");
const Allocator = std.mem.Allocator;

const tk = @import("tokenizer.zig");
const Token = tk.Token;

const ast = @import("ast.zig");
const Tree = ast.Tree;
const Node = ast.Node;

pub fn parse(gpa: *Allocator, source: []const u8) !*Tree {
    const tokens = try tk.tokenize(gpa, source);
    errdefer gpa.free(tokens);

    var arena = std.heap.ArenaAllocator.init(gpa);
    errdefer arena.deinit();

    var parser = Parser{
        .tokens = tokens,

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
        .root = root,

        .tokens = tokens,
        .source = source,

        .arena = arena.state,
        .gpa = gpa,
    };
    return tree;
}

pub const Parser = struct {
    tokens: []const Token,

    arena: *Allocator,
    gpa: *Allocator,

    index: usize = 0,

    pub fn block(self: *Parser, level: u8) anyerror!*Node {
        var nodes = std.ArrayList(*Node).init(self.arena);

        while (true) {
            const tok = self.nextToken();
            switch (self.tokens[tok].kind) {
                .RBrace, .Eof => break,
                else => {
                    self.index -= 1;
                    try nodes.append(try self.op(level));
                },
            }
        }

        const node = try self.arena.create(Node.Block);
        node.* = .{
            .nodes = nodes.toOwnedSlice(),
        };
        return &node.base;
    }

    pub fn op(self: *Parser, level: u8) anyerror!*Node {
        if (try self.write(level)) |node| return node;
        if (try self.call(level)) |node| return node;
        if (try self.builtinCall(level)) |node| return node;
        if (try self.ret(level)) |node| return node;
        std.debug.panic("invalid op {}", .{self.tokens[self.index]});
    }

    fn ret(self: *Parser, level: u8) anyerror!?*Node {
        const tilde_tok = self.eatToken(.Tilde) orelse return null;
        const cap = try self.primaryExpr();

        const node = try self.arena.create(Node.Ret);
        node.* = .{
            .cap = cap,

            .tilde_tok = tilde_tok,
        };
        return &node.base;
    }

    fn builtinCall(self: *Parser, level: u8) anyerror!?*Node {
        const at_tok = self.eatToken(.At) orelse return null;
        const builtin = try self.primaryExpr();
        const colon_tok = self.eatToken(.Colon) orelse @panic("expected :");

        const args = try self.expr(level);

        const node = try self.arena.create(Node.BuiltinCall);
        node.* = .{
            .builtin = builtin,
            .args = args,

            .at_tok = at_tok,
            .colon_tok = colon_tok,
        };
        return &node.base;
    }

    fn call(self: *Parser, level: u8) anyerror!?*Node {
        const bang_tok = self.eatToken(.Bang) orelse return null;
        const cap = try self.primaryExpr();

        if (self.eatToken(.Colon)) |colon_tok| {
            const args = try self.expr(level);
            const node = try self.arena.create(Node.Call);
            node.* = .{
                .cap = cap,
                .args = args,

                .bang_tok = bang_tok,
                .colon_tok = colon_tok,
            };
            return &node.base;
        } else {
            const node = try self.arena.create(Node.Call);
            node.* = .{
                .cap = cap,
                .args = null,

                .bang_tok = bang_tok,
                .colon_tok = null,
            };
            return &node.base;
        }
    }

    fn write(self: *Parser, level: u8) anyerror!?*Node {
        const dollar_tok = self.eatToken(.Dollar) orelse return null;
        const cap = try self.primaryExpr();

        if (try self.decl(level, dollar_tok, cap)) |node| return node;
        if (try self.assign(level, dollar_tok, cap)) |node| return node;
        @panic("expected a : or a =");
    }

    fn decl(self: *Parser, level: u8, dollar_tok: usize, cap: *Node) anyerror!?*Node {
        const colon_tok = self.eatToken(.Colon) orelse return null;

        const mods = try self.expr(level);

        const eql_tok = self.eatToken(.Equal) orelse null;
        const value = if (eql_tok) |_| try self.expr(level) else null;

        const node = try self.arena.create(Node.Decl);
        node.* = .{
            .cap = cap,
            .mods = mods,
            .value = value,

            .dollar_tok = dollar_tok,
            .colon_tok = colon_tok,
            .eql_tok = eql_tok,
        };
        return &node.base;
    }

    fn assign(self: *Parser, level: u8, dollar_tok: usize, cap: *Node) anyerror!?*Node {
        const eql_tok = self.eatToken(.Equal) orelse return null;

        const value = try self.expr(level);

        const node = try self.arena.create(Node.Assign);
        node.* = .{
            .cap = cap,
            .value = value,

            .dollar_tok = dollar_tok,
            .eql_tok = eql_tok,
        };
        return &node.base;
    }

    fn expr(self: *Parser, level: u8) anyerror!*Node {
        const tok = self.nextToken();
        const kind = self.tokens[tok].kind;
        switch (kind) {
            .Ident => {
                self.index -= 1;
                return self.primaryExpr();
            },
            .LiteralFloat, .LiteralInteger, .LiteralString => {
                const node = try self.arena.create(Node.Literal);
                node.* = .{
                    .tok = tok,
                };
                return &node.base;
            },
            .Keyword_type, .Keyword_struct, .Keyword_fn, .Keyword_void => {
                const node = try self.arena.create(Node.Type);
                node.* = .{
                    .tok = tok,
                };
                return &node.base;
            },
            .Keyword_pub, .Keyword_mut, .Keyword_comptime => {
                const node = try self.arena.create(Node.Mod);
                node.* = .{
                    .tok = tok,
                };
                return &node.base;
            },
            .LParen => return self.tuple(level + 1),
            .LAngle => return self.map(level + 1),
            .LBrace => return self.block(level + 1),
            .At, .Bang => {
                self.index -= 1;
                return self.op(level);
            },
            else => std.debug.panic("invalid expr token {}", .{self.tokens[tok]}),
        }
    }

    fn primaryExpr(self: *Parser) anyerror!*Node {
        const tok = self.nextToken();
        const kind = self.tokens[tok].kind;
        switch (kind) {
            .Ident => {
                if (self.tokens[tok + 1].kind == .Period) {
                    const ident = try self.arena.create(Node.Ident);
                    ident.* = .{
                        .tok = tok,
                    };
                    self.index += 1;
                    const node = try self.arena.create(Node.Scope);
                    node.* = .{
                        .lhs = &ident.base,
                        .rhs = try self.primaryExpr(),

                        .period_tok = tok,
                    };
                    return &node.base;
                } else {
                    const node = try self.arena.create(Node.Ident);
                    node.* = .{
                        .tok = tok,
                    };
                    return &node.base;
                }
            },
            .Period => {
                const itok = self.eatToken(.Ident) orelse std.debug.panic("expected ident found {}", .{self.tokens[self.index]});
                const ident = try self.arena.create(Node.Ident);
                ident.* = .{
                    .tok = itok,
                };
                const node = try self.arena.create(Node.Scope);
                node.* = .{
                    .lhs = null,
                    .rhs = &ident.base,

                    .period_tok = tok,
                };
                return &node.base;
            },
            .Keyword_struct, .Keyword_fn => {
                const node = try self.arena.create(Node.Type);
                node.* = .{
                    .tok = tok,
                };
                return &node.base;
            },
            else => std.debug.panic("invalid primary expr {}", .{self.tokens[tok]}),
        }
    }

    fn tuple(self: *Parser, level: u8) anyerror!*Node {
        var nodes = std.ArrayList(*Node).init(self.arena);
        while (true) {
            const tok = self.nextToken();
            switch (self.tokens[tok].kind) {
                .Comma => {},
                .RAngle, .RParen => break,
                else => {
                    self.index -= 1;
                    try nodes.append(try self.expr(level));
                },
            }
        }
        const node = try self.arena.create(Node.Tuple);
        node.* = .{
            .nodes = nodes.toOwnedSlice(),
        };
        return &node.base;
    }

    fn map(self: *Parser, level: u8) anyerror!*Node {
        var nodes = std.ArrayList(*Node).init(self.arena);
        while (true) {
            const tok = self.nextToken();
            switch (self.tokens[tok].kind) {
                .Comma => {},
                .RAngle => break,
                else => {
                    self.index -= 1;
                    const key = try self.primaryExpr();
                    const colon_tok = self.eatToken(.Colon) orelse std.debug.panic("expected : found {}", .{self.tokens[tok]});
                    const value = try self.expr(level);
                    const node = try self.arena.create(Node.MapItem);
                    node.* = .{
                        .key = key,
                        .value = value,

                        .colon_tok = colon_tok,
                    };
                    try nodes.append(&node.base);
                },
            }
        }
        const node = try self.arena.create(Node.Map);
        node.* = .{
            .nodes = nodes.toOwnedSlice(),
        };
        return &node.base;
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
};
