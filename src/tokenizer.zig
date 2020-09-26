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

        Asterisk,
        Ampersand,
        Underscore,

        Dollar,
        Bang,
        Tilde,
        At,

        Equal,

        HashPlus,
        HashMinus,
        HashAsterisk,
        HashSlash,
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

        LiteralString,
        LiteralInteger,
        LiteralFloat,

        Ident,
        Zero,
        Number,

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
                        state = .LiteralString;
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
                        state = .Number;
                    },
                    '=' => {
                        state = .Equal;
                    },
                    '/' => {
                        state = .Slash;
                    },
                    '#' => {
                        state = .Hash;
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
                        if (std.mem.eql(u8, self.source[res.start..self.index], "_")) {
                            res.kind = .Underscore;
                        }
                        break;
                    },
                },
                // TODO: support floats
                .Zero => switch (c) {
                    else => {
                        res.kind = .LiteralInteger;
                        break;
                    },
                },
                // TODO: support floats
                .Number => switch (c) {
                    '0'...'9' => {},
                    else => {
                        res.kind = .LiteralInteger;
                        break;
                    },
                },
                .Equal => switch (c) {
                    else => {
                        res.kind = .Equal;
                        break;
                    },
                },
                .Slash => switch (c) {
                    '/' => state = .LineComment,
                    else => std.debug.panic("unexpected single slash", .{}),
                },
                .Hash => switch (c) {
                    '+' => {
                        res.kind = .HashPlus;
                        self.index += 1;
                        break;
                    },
                    '-' => {
                        res.kind = .HashMinus;
                        self.index += 1;
                        break;
                    },
                    '*' => {
                        res.kind = .HashAsterisk;
                        self.index += 1;
                        break;
                    },
                    '/' => {
                        res.kind = .HashSlash;
                        self.index += 1;
                        break;
                    },
                    else => std.debug.panic("unexpected math operator {c}", .{@truncate(u8, c)}),
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
                .LiteralString => switch (c) {
                    '"' => {
                        res.kind = .LiteralString;
                        self.index += 1;
                        break;
                    },
                    else => {},
                },
                else => std.debug.panic("not implemented {}", .{state}),
            }
        } else {
            switch (state) {
                .Start => {},
                .Ident => {
                    res.kind = .Ident;
                },
                .LineComment => res.kind = .LineComment,
                .DocComment => res.kind = .DocComment,
                .LiteralString => std.debug.panic("untermiated string", .{}),
                .Zero => res.kind = .LiteralInteger,
                .Number => res.kind = .LiteralInteger,
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

test "tokenizer" {
    expectTokens(
        \\! ~ $
        \\& *
        \\=+ =- =* =/
        \\( ) { } < > [ ]
        \\<<
        \\, . | :
    , &[_]Token.Kind{
        .Bang,
        .Tilde,
        .Dollar,
        .Ampersand,
        .Asterisk,
        .EqualPlus,
        .EqualDash,
        .EqualAsterisk,
        .EqualSlash,
        .LParen,
        .RParen,
        .LBrace,
        .RBrace,
        .LAngle,
        .RAngle,
        .LBracket,
        .RBracket,
        .LAngleLAngle,
        .Comma,
        .Period,
        .Pipe,
        .Colon,
    });
}
