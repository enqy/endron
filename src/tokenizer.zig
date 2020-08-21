const std = @import("std");
const mem = std.mem;

const CleanupState = enum {
    String,
    None,
};

fn cleanup(allocator: *mem.Allocator, code: []const u8) ![]const u8 {
    var cleaned = std.ArrayList(u8).init(allocator);
    defer cleaned.deinit();

    var state: CleanupState = .None;

    var skip: usize = 0;

    for (code) |char, i| {
        if (skip > 0) {
            skip -= 1;
            continue;
        }

        if (char == 59) {
            while (i + skip < code.len and code[i + skip] != 10) {
                skip += 1;
            }
            continue;
        }

        if (state == .String) {
            if (char == 34) {
                state = .None;
                try cleaned.append(char);
                continue;
            } else if (char == 92) {
                try cleaned.append(char);
                try cleaned.append(code[i + 1]);
                skip += 1;
                continue;
            }
        } else {
            if (char == 34) {
                state = .String;
                try cleaned.append(char);
                continue;
            }
        }

        if (state != .String and char == 9) continue;
        if (state != .String and char == 10) continue;
        if (state != .String and char == 13) continue;
        if (state != .String and char == 32) continue;
        try cleaned.append(char);
    }

    return cleaned.toOwnedSlice();
}

pub const Token = union(enum) {
    String: []const u8,
    Integer: struct { string: []const u8, num: i64 },
    Number: struct { string: []const u8, num: f64 },
    Bool: bool,
    Void: void,
    Ident: []const u8,

    CallSym: void,
    TypeSym: void,
    DeclSym: void,
    SetSym: void,
    IfSym: void,
    WhileSym: void,

    Colon: void,
    Comma: void,

    LParen: void,
    RParen: void,
    LBrace: void,
    RBrace: void,
    LBracket: void,
    RBracket: void,

    None: void,

    pub fn deinit(self: Token, allocator: *mem.Allocator) void {
        switch (self) {
            .String => allocator.free(self.String),
            .Integer => allocator.free(self.Integer.string),
            .Number => allocator.free(self.Number.string),
            .Ident => allocator.free(self.Ident),
            else => {},
        }
    }
};

pub fn tokenize(allocator: *mem.Allocator, code: []const u8) ![]const Token {
    var cleaned = try cleanup(allocator, code);
    defer allocator.free(cleaned);

    var tokens = std.ArrayList(Token).init(allocator);
    defer tokens.deinit();

    var curr_token: Token = .{ .None = {} };

    var skip: usize = 0;

    for (cleaned) |char, i| {
        if (skip > 0) {
            skip -= 1;
            continue;
        }

        // Tokenize Ident
        if ((char >= 65 and char <= 90) or (char >= 97 and char <= 122) or char == 95) {
            if (curr_token == .None) {
                curr_token = .{ .Ident = try mem.join(allocator, "", &[_][]const u8{ "", &[_]u8{char} }) };
                continue;
            } else if (curr_token == .Ident) {
                const tmp = try mem.join(allocator, "", &[_][]const u8{ curr_token.Ident, &[_]u8{char} });
                allocator.free(curr_token.Ident);
                curr_token.Ident = tmp;
                continue;
            }
        } else if (curr_token == .Ident) {
            if (mem.eql(u8, curr_token.Ident, "false")) {
                allocator.free(curr_token.Ident);
                try tokens.append(.{ .Bool = false });
            } else if (mem.eql(u8, curr_token.Ident, "true")) {
                allocator.free(curr_token.Ident);
                try tokens.append(.{ .Bool = true });
            } else if (mem.eql(u8, curr_token.Ident, "void")) {
                allocator.free(curr_token.Ident);
                try tokens.append(.{ .Void = {} });
            } else {
                try tokens.append(curr_token);
            }
            curr_token = .{ .None = {} };
        }

        // Tokenize String
        if (char == 34) {
            if (curr_token == .None) {
                curr_token = .{ .String = try mem.join(allocator, "", &[_][]const u8{""}) };
                continue;
            } else if (curr_token == .String) {
                try tokens.append(curr_token);
                curr_token = .{ .None = {} };
                continue;
            }
        }
        if ((char >= 35 and char <= 126) or char == 32 or char == 33 or char == 10 or char == 9) {
            if (curr_token == .String) {
                if (char == 92) {
                    skip += 1;
                    const tmp = try mem.join(allocator, "", &[_][]const u8{ curr_token.String, &[_]u8{cleaned[i + 1]} });
                    allocator.free(curr_token.String);
                    curr_token.String = tmp;
                    continue;
                } else {
                    const tmp = try mem.join(allocator, "", &[_][]const u8{ curr_token.String, &[_]u8{char} });
                    allocator.free(curr_token.String);
                    curr_token.String = tmp;
                    continue;
                }
            }
        }

        // Tokenize Number & Integer
        if ((char >= 48 and char <= 57) or char == 45 or char == 46) {
            if (char == 46) {
                if (curr_token == .None) {
                    curr_token = .{ .Number = .{ .string = try mem.join(allocator, "", &[_][]const u8{ "", &[_]u8{char} }), .num = 0 } };
                    continue;
                } else if (curr_token == .Number) {
                    const tmp = try mem.join(allocator, "", &[_][]const u8{ curr_token.Number.string, &[_]u8{char} });
                    allocator.free(curr_token.Number.string);
                    curr_token.Number.string = tmp;
                    continue;
                } else if (curr_token == .Integer) {
                    const tmp = try mem.join(allocator, "", &[_][]const u8{ curr_token.Integer.string, &[_]u8{char} });
                    allocator.free(curr_token.Integer.string);
                    curr_token = .{ .Number = .{ .string = tmp, .num = 0 } };
                    continue;
                }
            } else {
                if (curr_token == .None) {
                    curr_token = .{ .Integer = .{ .string = try mem.join(allocator, "", &[_][]const u8{ "", &[_]u8{char} }), .num = 0 } };
                    continue;
                } else if (curr_token == .Number) {
                    const tmp = try mem.join(allocator, "", &[_][]const u8{ curr_token.Number.string, &[_]u8{char} });
                    allocator.free(curr_token.Number.string);
                    curr_token.Number.string = tmp;
                    continue;
                } else if (curr_token == .Integer) {
                    const tmp = try mem.join(allocator, "", &[_][]const u8{ curr_token.Integer.string, &[_]u8{char} });
                    allocator.free(curr_token.Integer.string);
                    curr_token.Integer.string = tmp;
                    continue;
                }
            }
        } else if (curr_token == .Number) {
            curr_token.Number.num = try std.fmt.parseFloat(f64, curr_token.Number.string);
            try tokens.append(curr_token);
            curr_token = .{ .None = {} };
        } else if (curr_token == .Integer) {
            curr_token.Integer.num = try std.fmt.parseInt(i64, curr_token.Integer.string, 10);
            try tokens.append(curr_token);
            curr_token = .{ .None = {} };
        }

        // Tokenize !
        if (char == 33) {
            try tokens.append(Token{ .CallSym = {} });
            continue;
        }

        // Tokenize @
        if (char == 64) {
            try tokens.append(Token{ .DeclSym = {} });
            continue;
        }

        // Tokenize $
        if (char == 36) {
            try tokens.append(Token{ .TypeSym = {} });
            continue;
        }

        // Tokenize ~
        if (char == 126) {
            try tokens.append(Token{ .SetSym = {} });
            continue;
        }

        // Tokenize ?
        if (char == 63) {
            try tokens.append(Token{ .IfSym = {} });
            continue;
        }

        // Tokenize ^
        if (char == 94) {
            try tokens.append(Token{ .WhileSym = {} });
            continue;
        }

        // Tokenize :
        if (char == 58) {
            try tokens.append(Token{ .Colon = {} });
            continue;
        }

        // Tokenize ,
        if (char == 44) {
            try tokens.append(Token{ .Comma = {} });
            continue;
        }

        // Tokenize ~
        if (char == 126) {
            try tokens.append(Token{ .Comma = {} });
            continue;
        }

        // Tokenize (
        if (char == 40) {
            try tokens.append(Token{ .LParen = {} });
            continue;
        }

        // Tokenize )
        if (char == 41) {
            try tokens.append(Token{ .RParen = {} });
            continue;
        }

        // Tokenize {
        if (char == 123) {
            try tokens.append(Token{ .LBrace = {} });
            continue;
        }

        // Tokenize }
        if (char == 125) {
            try tokens.append(Token{ .RBrace = {} });
            continue;
        }

        // Tokenize [
        if (char == 91) {
            try tokens.append(Token{ .LBracket = {} });
            continue;
        }

        // Tokenize ]
        if (char == 93) {
            try tokens.append(Token{ .RBracket = {} });
            continue;
        }

        std.debug.panic("Invalid Token: {c},{}, {}, {}\n", .{ char, char, i, curr_token });
    }

    return tokens.toOwnedSlice();
}
