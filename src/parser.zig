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
    source: []const u8,

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
        if (try self.decl(level)) |node| return node;
        if (try self.set(level)) |node| return node;
        if (try self.call(level)) |node| return node;
        if (try self.builtin(level)) |node| return node;
        if (try self.branch(level)) |node| return node;
        if (try self.macro(level)) |node| return node;
        std.debug.panic("invalid op {}", .{self.tokens[self.index]});
    }

    fn decl(self: *Parser, level: u8) anyerror!?*Node {
        const dollar_tok = self.eatToken(.Dollar) orelse return null;
        const cap = try self.ident();

        if (try self.declWithMods(level, dollar_tok, cap)) |node| return node;
        if (try self.declNoMods(level, dollar_tok, cap)) |node| return node;
        @panic("expected a : or a =");
    }

    fn declWithMods(self: *Parser, level: u8, dollar_tok: usize, cap: *Node) anyerror!?*Node {
        const colon_tok = self.eatToken(.Colon) orelse return null;

        const mods = (try self.expr(level)) orelse @panic("expected a expr");

        const eql_tok = self.eatToken(.Equal) orelse null;
        const value = if (eql_tok) |_| (try self.expr(level)) orelse @panic("expected value") else null;

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

    fn declNoMods(self: *Parser, level: u8, dollar_tok: usize, cap: *Node) anyerror!?*Node {
        const eql_tok = self.eatToken(.Equal) orelse return null;

        const value = (try self.expr(level)) orelse @panic("expected value");

        const node = try self.arena.create(Node.Decl);
        node.* = .{
            .cap = cap,
            .mods = null,
            .value = value,

            .dollar_tok = dollar_tok,
            .colon_tok = null,
            .eql_tok = eql_tok,
        };
        return &node.base;
    }

    fn set(self: *Parser, level: u8) anyerror!?*Node {
        const tilde_tok = self.eatToken(.Tilde) orelse return null;
        const cap = try self.ident();

        const eql_tok = self.eatToken(.Equal) orelse @panic("expected =");

        const value = (try self.expr(level)) orelse @panic("expected value");

        const node = try self.arena.create(Node.Set);
        node.* = .{
            .cap = cap,
            .value = value,

            .tilde_tok = tilde_tok,
            .eql_tok = eql_tok,
        };
        return &node.base;
    }

    fn call(self: *Parser, level: u8) anyerror!?*Node {
        const bang_tok = self.eatToken(.Bang) orelse return null;
        const cap = try self.ident();

        switch (self.tokens[self.index].kind) {
            .LParen, .LAngle => {
                const args = (try self.expr(level)) orelse @panic("expected a map or a tuple");
                const node = try self.arena.create(Node.Call);
                node.* = .{
                    .cap = cap,
                    .args = args,

                    .bang_tok = bang_tok,
                };
                return &node.base;
            },
            else => {
                const node = try self.arena.create(Node.Call);
                node.* = .{
                    .cap = cap,
                    .args = null,

                    .bang_tok = bang_tok,
                };
                return &node.base;
            },
        }
    }

    fn builtin(self: *Parser, level: u8) anyerror!?*Node {
        const at_tok = self.eatToken(.At) orelse return null;
        const cap = try self.ident();

        switch (self.tokens[self.index].kind) {
            .LParen, .LAngle => {
                const args = (try self.expr(level)) orelse @panic("expected a map or a tuple");
                const node = try self.arena.create(Node.BuiltinCall);
                node.* = .{
                    .cap = cap,
                    .args = args,

                    .at_tok = at_tok,
                };
                return &node.base;
            },
            else => {
                const node = try self.arena.create(Node.BuiltinCall);
                node.* = .{
                    .cap = cap,
                    .args = null,

                    .at_tok = at_tok,
                };
                return &node.base;
            },
        }
    }

    fn macro(self: *Parser, level: u8) anyerror!?*Node {
        const percent_tok = self.eatToken(.Percent) orelse return null;
        const cap = try self.ident();

        switch (self.tokens[self.index].kind) {
            .LParen, .LAngle => {
                const args = (try self.expr(level)) orelse @panic("expected a map or a tuple");
                const node = try self.arena.create(Node.MacroCall);
                node.* = .{
                    .cap = cap,
                    .args = args,

                    .percent_tok = percent_tok,
                };
                return &node.base;
            },
            else => {
                const node = try self.arena.create(Node.MacroCall);
                node.* = .{
                    .cap = cap,
                    .args = null,

                    .percent_tok = percent_tok,
                };
                return &node.base;
            },
        }
    }

    fn branch(self: *Parser, level: u8) anyerror!?*Node {
        const caret_tok = self.eatToken(.Caret) orelse return null;
        const cap = try self.ident();

        const args = (try self.expr(level)) orelse @panic("expected a tuple");

        const node = try self.arena.create(Node.Branch);
        node.* = .{
            .cap = cap,
            .args = args,

            .caret_tok = caret_tok,
        };
        return &node.base;
    }

    fn math(self: *Parser, level: u8) anyerror!?*Node {
        if (try self.add(level)) |node| return node;
        return null;
    }

    fn add(self: *Parser, level: u8) anyerror!?*Node {
        const mtok = self.eatToken(.HashAdd) orelse return null;
        _ = self.eatToken(.LParen) orelse std.debug.panic("expected ( found {}", .{self.tokens[self.index]});
        const args = try self.tuple(level);

        const node = try self.arena.create(Node.MathAdd);
        node.* = .{
            .args = args,

            .mtok = mtok,
        };
        return &node.base;
    }

    fn expr(self: *Parser, level: u8) anyerror!?*Node {
        const tok = self.nextToken();
        const kind = self.tokens[tok].kind;
        const e = blk: {
            switch (kind) {
                .Ident => {
                    self.index -= 1;
                    break :blk try self.ident();
                },
                .LiteralFloat, .LiteralInteger, .LiteralString => {
                    const node = try self.arena.create(Node.Literal);
                    node.* = .{
                        .tok = tok,
                    };
                    break :blk &node.base;
                },
                .LParen => break :blk try self.tuple(level + 1),
                .LAngle => break :blk try self.map(level + 1),
                .LBrace => break :blk try self.block(level + 1),
                .At, .Bang, .Percent => {
                    self.index -= 1;
                    break :blk try self.op(level);
                },
                .HashAdd, .HashSub, .HashMul, .HashDiv => {
                    self.index -= 1;
                    break :blk try self.math(level);
                },
                else => break :blk null,
            }
        };

        return e;
    }

    fn ident(self: *Parser) anyerror!*Node {
        const tok = self.nextToken();
        const kind = self.tokens[tok].kind;
        switch (kind) {
            .Ident => {
                if (self.tokens[tok + 1].kind == .Period) {
                    const inode = try self.arena.create(Node.Ident);
                    inode.* = .{
                        .tok = tok,
                    };
                    self.index += 1;
                    const node = try self.arena.create(Node.Scope);
                    node.* = .{
                        .lhs = &inode.base,
                        .rhs = try self.ident(),

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
            .Underscore => {
                const node = try self.arena.create(Node.Discard);
                node.* = .{
                    .tok = tok,
                };
                return &node.base;
            },
            .Period => {
                const itok = self.eatToken(.Ident) orelse std.debug.panic("expected ident found {}", .{self.tokens[self.index]});
                const inode = try self.arena.create(Node.Ident);
                inode.* = .{
                    .tok = itok,
                };
                const node = try self.arena.create(Node.Scope);
                node.* = .{
                    .lhs = null,
                    .rhs = &inode.base,

                    .period_tok = tok,
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
                    try nodes.append((try self.expr(level)) orelse @panic("expected value"));
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
                    const key = try self.ident();
                    const colon_tok = self.eatToken(.Colon) orelse std.debug.panic("expected : found {}", .{self.tokens[tok]});
                    const value = (try self.expr(level)) orelse @panic("expected value");
                    const node = try self.arena.create(Node.MapEntry);
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
