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
    var nodes = std.ArrayList(*Node).init(gpa);
    defer nodes.deinit();

    while (true) switch (tokens[parser.index].kind) {
        .LineComment, .DocComment => parser.index += 1,
        else => break,
    };

    while (true) {
        if (parser.eatToken(.Eof)) |_| break;
        try nodes.append(try parser.op(0));
    }

    const tree = try parser.arena.create(Tree);
    tree.* = Tree{
        .nodes = try parser.arena.dupe(*Node, nodes.items),

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

    /// op
    ///     : decl expr ":" expr ("<<" expr)?
    ///     | set expr ":" expr
    ///     | call expr ":" expr
    fn op(self: *Parser, level: u16) anyerror!*Node {
        if (try self.decl(level)) |node| return node;
        //if (parser.set(level)) |node| return node;
        //return parser.call(level);
        unreachable;
    }

    /// decl : "$" expr ":" [ expr ] ("<<" expr)?
    fn decl(self: *Parser, level: u16) anyerror!?*Node {
        const tok = self.eatToken(.Dollar) orelse return null;
        const cap = try self.primaryExpr(level);
        const colon = self.eatToken(.Colon) orelse @panic("Invalid token");

        const node = try self.arena.create(Node.Decl);
        node.* = .{
            .tok = tok,
            .cap = cap,
            .colon = colon,
        };
        return &node.base;
    }

    fn primaryExpr(self: *Parser, level: u16) anyerror!*Node {
        const tok = self.nextToken();
        const kind = self.tokens[tok].kind;

        switch (kind) {
            .Ident => {
                const node = try self.arena.create(Node.Ident);
                node.* = .{
                    .tok = tok,
                };
                return &node.base;
            },
            else => @panic("not implemented"),
        }
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
