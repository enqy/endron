const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Token = struct {
    kind: Kind,
    start: usize,
    end: usize,

    pub const Kind = enum {
        Eof,
        Ident,
        LiteralString,
        LiteralInteger,
        LiteralFloat,
        LineComment,
        DocComment,

        LParen,
        RParen,
        LBrace,
        RBrace,
        LBracket,
        RBracket,
        LAngle,
        RAngle,

        Colon,
        Comma,
        Period,
        Pipe,
        Underscore,

        Asterisk,
        Ampersand,

        Dollar,
        Bang,
        Tilde,
        At,
        Percent,
        Caret,

        Equal,

        HashAdd,
        HashSub,
    };
};

pub fn tokenize(allocator: *Allocator, source: []const u8) ![]const Token {
    const estimated = source.len / 4;
    var tokenizer = Tokenizer{
        .tokens = try std.ArrayList(Token).initCapacity(allocator, estimated),
        .source = source,
    };
    errdefer tokenizer.tokens.deinit();
    while (true) {
        const tok = try tokenizer.tokens.addOne();
        tok.* = tokenizer.next();
        if (tok.kind == .Eof) {
            return tokenizer.tokens.toOwnedSlice();
        }
    }
}

pub const Tokenizer = struct {
    tokens: std.ArrayList(Token),
    source: []const u8,
    index: usize = 0,

    const State = enum {
        Start,

        Ident,
        String,
        Zero,
        Integer,
        Float,

        Slash,
        LineComment,
        DocComment,

        Equal,

        Hash,
    };

    fn isIdentChar(c: u8) bool {
        return std.ascii.isAlNum(c) or c == '_';
    }

    pub fn next(self: *Tokenizer) Token {
        var state: State = .Start;
        var res = Token{
            .kind = .Eof,
            .start = self.index,
            .end = 0,
        };

        while (self.index < self.source.len) : (self.index += 1) {
            const c = self.source[self.index];
            switch (state) {
                .Start => switch (c) {
                    ' ', '\n', '\t', '\r' => res.start = self.index + 1,
                    '"' => {
                        state = .String;
                        res.kind = .LiteralString;
                    },
                    'a'...'z', 'A'...'Z', '_' => {
                        state = .Ident;
                        res.kind = .Ident;
                    },
                    '0' => {
                        state = .Zero;
                    },
                    '1'...'9' => {
                        state = .Integer;
                    },
                    '=' => {
                        state = .Equal;
                    },
                    '#' => {
                        state = .Hash;
                    },
                    '/' => {
                        state = .Slash;
                    },
                    '$' => {
                        res.kind = .Dollar;
                        self.index += 1;
                        break;
                    },
                    '~' => {
                        res.kind = .Tilde;
                        self.index += 1;
                        break;
                    },
                    '!' => {
                        res.kind = .Bang;
                        self.index += 1;
                        break;
                    },
                    '@' => {
                        res.kind = .At;
                        self.index += 1;
                        break;
                    },
                    '%' => {
                        res.kind = .Percent;
                        self.index += 1;
                        break;
                    },
                    '^' => {
                        res.kind = .Caret;
                        self.index += 1;
                        break;
                    },
                    ':' => {
                        res.kind = .Colon;
                        self.index += 1;
                        break;
                    },
                    '(' => {
                        res.kind = .LParen;
                        self.index += 1;
                        break;
                    },
                    ')' => {
                        res.kind = .RParen;
                        self.index += 1;
                        break;
                    },
                    '{' => {
                        res.kind = .LBrace;
                        self.index += 1;
                        break;
                    },
                    '}' => {
                        res.kind = .RBrace;
                        self.index += 1;
                        break;
                    },
                    '[' => {
                        res.kind = .LBracket;
                        self.index += 1;
                        break;
                    },
                    ']' => {
                        res.kind = .RBracket;
                        self.index += 1;
                        break;
                    },
                    '<' => {
                        res.kind = .LAngle;
                        self.index += 1;
                        break;
                    },
                    '>' => {
                        res.kind = .RAngle;
                        self.index += 1;
                        break;
                    },
                    ',' => {
                        res.kind = .Comma;
                        self.index += 1;
                        break;
                    },
                    '.' => {
                        res.kind = .Period;
                        self.index += 1;
                        break;
                    },
                    '|' => {
                        res.kind = .Pipe;
                        self.index += 1;
                        break;
                    },
                    '*' => {
                        res.kind = .Asterisk;
                        self.index += 1;
                        break;
                    },
                    '&' => {
                        res.kind = .Ampersand;
                        self.index += 1;
                        break;
                    },
                    else => std.debug.panic("invalid character {c}", .{@truncate(u8, c)}),
                },
                .Ident => switch (c) {
                    'a'...'z', 'A'...'Z', '0'...'9', '_' => {},
                    else => {
                        if (std.mem.eql(u8, self.source[res.start..self.index], "_")) res.kind = .Underscore;
                        break;
                    },
                },
                .Zero => switch (c) {
                    '.' => {
                        state = .Float;
                    },
                    '0'...'9' => {
                        state = .Integer;
                    },
                    else => {
                        res.kind = .LiteralInteger;
                        break;
                    },
                },
                .Integer => switch (c) {
                    '0'...'9' => {},
                    else => {
                        res.kind = .LiteralInteger;
                        break;
                    },
                },
                .Float => switch (c) {
                    '0'...'9' => {},
                    else => {
                        res.kind = .LiteralFloat;
                        break;
                    },
                },
                .Equal => switch (c) {
                    else => {
                        res.kind = .Equal;
                        break;
                    },
                },
                .Hash => switch (c) {
                    '+' => {
                        res.kind = .HashAdd;
                        self.index += 1;
                        break;
                    },
                    '-' => {
                        res.kind = .HashSub;
                        self.index += 1;
                        break;
                    },
                    else => std.debug.panic("invalid math op {c}", .{@truncate(u8, c)}),
                },
                .Slash => switch (c) {
                    '/' => state = .LineComment,
                    else => @panic("unexpected /"),
                },
                // TODO: implment more checking
                .LineComment => switch (c) {
                    '/' => state = .DocComment,
                    '\n' => {
                        res.kind = .LineComment;
                        self.index += 1;
                        break;
                    },
                    else => {},
                },
                // TODO: implment more checking
                .DocComment => switch (c) {
                    '/' => state = .LineComment,
                    '\n' => {
                        res.kind = .DocComment;
                        self.index += 1;
                        break;
                    },
                    else => {},
                },
                // TODO: implment more checking
                .String => switch (c) {
                    '"' => {
                        res.kind = .LiteralString;
                        self.index += 1;
                        break;
                    },
                    else => {},
                },
            }
        } else {
            switch (state) {
                .Start => {},
                .Ident => {
                    res.kind = .Ident;
                    if (std.mem.eql(u8, self.source[res.start..self.index], "_")) res.kind = .Underscore;
                },
                .LineComment => res.kind = .LineComment,
                .DocComment => res.kind = .DocComment,
                .String => std.debug.panic("untermiated string", .{}),
                .Zero => res.kind = .LiteralInteger,
                .Integer => res.kind = .LiteralInteger,
                .Float => res.kind = .LiteralFloat,
                else => std.debug.panic("unexpected EOF", .{}),
            }
        }

        res.end = self.index;
        return res;
    }
};

fn expectTokens(source: []const u8, tokens: []const Token.Kind) void {
    var tokenizer = Tokenizer{
        .tokens = undefined,
        .source = source,
    };
    for (tokens) |t| std.testing.expectEqual(t, tokenizer.next().kind);
    std.testing.expect(tokenizer.next().kind == .Eof);
}

test "symbols" {
    expectTokens(
        \\! ~ $ @ % ^
        \\& *
        \\#+ #- #* #/
        \\( ) { } < > [ ]
        \\=
        \\, . | : _
    , &[_]Token.Kind{
        .Bang,
        .Tilde,
        .Dollar,
        .At,
        .Percent,
        .Caret,
        .Ampersand,
        .Asterisk,
        .HashAdd,
        .HashSub,
        .HashMul,
        .HashDiv,
        .LParen,
        .RParen,
        .LBrace,
        .RBrace,
        .LAngle,
        .RAngle,
        .LBracket,
        .RBracket,
        .Equal,
        .Comma,
        .Period,
        .Pipe,
        .Colon,
        .Underscore,
    });
}

test "literals" {
    expectTokens(
        \\"test"
        \\00123
        \\0123
        \\1230
        \\0.939
    , &[_]Token.Kind{
        .LiteralString,
        .LiteralInteger,
        .LiteralInteger,
        .LiteralInteger,
        .LiteralFloat,
    });
}

test "other" {
    expectTokens(
        \\ident
        \\//line
        \\///doc
    , &[_]Token.Kind{
        .Ident,
        .LineComment,
        .DocComment,
    });
}
