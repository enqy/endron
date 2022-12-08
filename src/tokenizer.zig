const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Token = struct {
    kind: Kind,
    start: usize,
    end: usize,
    column: usize,
    line: usize,

    pub const Kind = enum {
        eof,
        ident,
        line_comment,
        doc_comment,
        literal_decimal,
        literal_number,
        literal_string,

        lbrace,
        rbrace,
        lparen,
        rparen,

        comma,
        semicolon,

        caret,
        colon,
        period,
        underscore,

        at,
        bang,
        dollar,
        pipe,
        question_mark,
        tilde,

        number_sign,
        plus,
        minus,
        asterisk,
        double_asterisk,
        slash,
        greater_than,
        less_than,
        equal,
    };
};

pub fn tokenize(alloc: Allocator, source: []const u8) ![]const Token {
    var tokenizer = Tokenizer{
        .source = source,
        .tokens = try std.ArrayList(Token).initCapacity(alloc, source.len / 4),
    };
    errdefer tokenizer.tokens.deinit();
    while (true) {
        const token = try tokenizer.tokens.addOne();
        token.* = tokenizer.next();
        if (token.kind == Token.Kind.eof) return tokenizer.tokens.toOwnedSlice();
    }
}

pub fn detokenize(allocator: Allocator, source: []const u8, tokens: []const Token) ![]const u8 {
    var str = std.ArrayList(u8).init(allocator);
    errdefer str.deinit();

    var current_line: usize = 0;
    var current_column: usize = 0;

    for (tokens) |token| {
        while (current_line < token.line - 1) : (current_line += 1) {
            current_column = 0;
            try str.append('\n');
        }

        while (current_column < token.column - 1) : (current_column += 1) {
            try str.append(' ');
        }

        current_column += token.end - token.start;
        try str.appendSlice(source[token.start..token.end]);
    }

    return str.toOwnedSlice();
}

pub const Tokenizer = struct {
    source: []const u8,
    index: usize = 0,
    line: usize = 0,
    column: usize = 0,
    tokens: std.ArrayList(Token),

    // TODO: implement negative numbers
    const State = enum {
        start,

        ident,

        string,
        zero,
        minus,
        number,
        decimal,

        slash,
        line_comment,
        line_comment_locked,
        doc_comment,
        doc_comment_locked,

        asterisk,
    };

    pub fn next(self: *Tokenizer) Token {
        var state: State = .start;
        var res = Token{
            .kind = Token.Kind.eof,
            .start = self.index,
            .end = self.index,
            .column = self.column,
            .line = self.line,
        };

        while (self.index < self.source.len) {
            const c = self.source[self.index];
            switch (state) {
                .start => switch (c) {
                    ' ' => {
                        res.column += 1;
                        res.start += 1;
                        self.column += 1;
                        self.index += 1;
                    },
                    '\n' => {
                        res.line += 1;
                        res.column = 0;
                        res.start += 1;
                        self.line += 1;
                        self.column = 0;
                        self.index += 1;
                    },
                    'a'...'z', 'A'...'Z', '_' => {
                        state = .ident;
                        res.kind = Token.Kind.ident;
                        self.column += 1;
                        self.index += 1;
                    },
                    '0'...'9' => {
                        state = .number;
                        res.kind = Token.Kind.literal_number;
                        self.column += 1;
                        self.index += 1;
                    },
                    '/' => {
                        state = .slash;
                        res.kind = Token.Kind.slash;
                        self.column += 1;
                        self.index += 1;
                    },
                    '"' => {
                        state = .string;
                        res.kind = Token.Kind.literal_string;
                        self.column += 1;
                        self.index += 1;
                    },
                    '{' => {
                        res.kind = Token.Kind.lbrace;
                        self.column += 1;
                        self.index += 1;
                        break;
                    },
                    '}' => {
                        res.kind = Token.Kind.rbrace;
                        self.column += 1;
                        self.index += 1;
                        break;
                    },
                    '(' => {
                        res.kind = Token.Kind.lparen;
                        self.column += 1;
                        self.index += 1;
                        break;
                    },
                    ')' => {
                        res.kind = Token.Kind.rparen;
                        self.column += 1;
                        self.index += 1;
                        break;
                    },
                    ',' => {
                        res.kind = Token.Kind.comma;
                        self.column += 1;
                        self.index += 1;
                        break;
                    },
                    ';' => {
                        res.kind = Token.Kind.semicolon;
                        self.column += 1;
                        self.index += 1;
                        break;
                    },
                    '^' => {
                        res.kind = Token.Kind.caret;
                        self.column += 1;
                        self.index += 1;
                        break;
                    },
                    ':' => {
                        res.kind = Token.Kind.colon;
                        self.column += 1;
                        self.index += 1;
                        break;
                    },
                    '.' => {
                        res.kind = Token.Kind.period;
                        self.column += 1;
                        self.index += 1;
                        break;
                    },
                    // underscore not handled here because it is also a valid ident char so its handled in ident
                    '@' => {
                        res.kind = Token.Kind.at;
                        self.column += 1;
                        self.index += 1;
                        break;
                    },
                    '!' => {
                        res.kind = Token.Kind.bang;
                        self.column += 1;
                        self.index += 1;
                        break;
                    },
                    '$' => {
                        res.kind = Token.Kind.dollar;
                        self.column += 1;
                        self.index += 1;
                        break;
                    },
                    '|' => {
                        res.kind = Token.Kind.pipe;
                        self.column += 1;
                        self.index += 1;
                        break;
                    },
                    '?' => {
                        res.kind = Token.Kind.question_mark;
                        self.column += 1;
                        self.index += 1;
                        break;
                    },
                    '~' => {
                        res.kind = Token.Kind.tilde;
                        self.column += 1;
                        self.index += 1;
                        break;
                    },
                    '#' => {
                        res.kind = Token.Kind.number_sign;
                        self.column += 1;
                        self.index += 1;
                        break;
                    },
                    '+' => {
                        res.kind = Token.Kind.plus;
                        self.column += 1;
                        self.index += 1;
                        break;
                    },
                    '-' => {
                        state = .minus;
                        res.kind = Token.Kind.minus;
                        self.column += 1;
                        self.index += 1;
                    },
                    '*' => {
                        state = .asterisk;
                        res.kind = Token.Kind.asterisk;
                        self.column += 1;
                        self.index += 1;
                    },
                    // slash handled above
                    '>' => {
                        res.kind = Token.Kind.greater_than;
                        self.column += 1;
                        self.index += 1;
                        break;
                    },
                    '<' => {
                        res.kind = Token.Kind.less_than;
                        self.column += 1;
                        self.index += 1;
                        break;
                    },
                    '=' => {
                        res.kind = Token.Kind.equal;
                        self.column += 1;
                        self.index += 1;
                        break;
                    },
                    else => std.debug.panic("invalid character: {c} at {}:{}", .{ c, self.line, self.column }),
                },
                .ident => switch (c) {
                    'a'...'z', 'A'...'Z', '0'...'9', '_' => {
                        self.column += 1;
                        self.index += 1;
                    },
                    else => {
                        if (self.source[res.start..self.index].len == 1 and self.source[res.start] == '_') res.kind = .underscore;
                        break;
                    },
                },
                .minus => switch (c) {
                    '0'...'9' => {
                        state = .number;
                        res.kind = .literal_number;
                        self.column += 1;
                        self.index += 1;
                    },
                    else => break,
                },
                .number => switch (c) {
                    '0'...'9' => {
                        self.column += 1;
                        self.index += 1;
                    },
                    '.' => {
                        state = .decimal;
                        res.kind = Token.Kind.literal_decimal;
                        self.column += 1;
                        self.index += 1;
                    },
                    else => break,
                },
                .decimal => switch (c) {
                    '0'...'9' => {
                        self.column += 1;
                        self.index += 1;
                    },
                    else => break,
                },
                .string => switch (c) {
                    '"' => {
                        self.column += 1;
                        self.index += 1;
                        break;
                    },
                    '\\' => {
                        self.column += 2;
                        self.index += 2;
                    },
                    '\n' => {
                        self.line += 1;
                        self.column = 0;
                        self.index += 1;
                    },
                    else => {
                        self.column += 1;
                        self.index += 1;
                    },
                },
                .slash => switch (c) {
                    '/' => {
                        state = .line_comment;
                        res.kind = Token.Kind.line_comment;
                        self.column += 1;
                        self.index += 1;
                    },
                    else => break,
                },
                .line_comment => switch (c) {
                    '/' => {
                        state = .doc_comment;
                        res.kind = Token.Kind.doc_comment;
                        self.column += 1;
                        self.index += 1;
                    },
                    '\n' => break,
                    else => {
                        state = .line_comment_locked;
                        self.column += 1;
                        self.index += 1;
                    },
                },
                .line_comment_locked => switch (c) {
                    '\n' => break,
                    else => {
                        self.column += 1;
                        self.index += 1;
                    },
                },
                .doc_comment => switch (c) {
                    '\n' => break,
                    else => {
                        state = .doc_comment_locked;
                        self.column += 1;
                        self.index += 1;
                    },
                },
                .doc_comment_locked => switch (c) {
                    '\n' => break,
                    else => {
                        self.column += 1;
                        self.index += 1;
                    },
                },
                .asterisk => switch (c) {
                    '*' => {
                        res.kind = Token.Kind.double_asterisk;
                        self.column += 1;
                        self.index += 1;
                        break;
                    },
                    else => break,
                },
                else => unreachable,
            }
        }

        res.end = self.index;
        res.column += 1;
        res.line += 1;
        return res;
    }
};
