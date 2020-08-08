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
    Number: struct { string: []const u8, num: f64 },
    Bool: bool,
    Ident: []const u8,
    CallSym: void,
    DefSym: void,
    DeclSym: void,
    TypeSym: void,
    If: void,
    Colon: void,
    Comma: void,
    BlockStart: void,
    BlockEnd: void,
    TupleStart: void,
    TupleEnd: void,
    IndexStart: void,
    IndexEnd: void,
    JmpLabel: void,
    JmpSym: void,
    Void: void,
    None: void,
};

pub fn tokenize(allocator: *mem.Allocator, code: []const u8) ![]const Token {
    var cleaned = try cleanup(allocator, code);

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
        if ((char >= 65 and char <= 90) or (char >= 97 and char <= 122)) {
            if (curr_token == .None) {
                curr_token = .{ .Ident = try mem.join(allocator, "", &[_][]const u8{ "", &[_]u8{char} }) };
                continue;
            } else if (curr_token == .Ident) {
                curr_token.Ident = try mem.join(allocator, "", &[_][]const u8{ curr_token.Ident, &[_]u8{char} });
                continue;
            }
        } else if (curr_token == .Ident) {
            if (mem.eql(u8, curr_token.Ident, "false")) {
                try tokens.append(.{ .Bool = false });
            } else if (mem.eql(u8, curr_token.Ident, "true")) {
                try tokens.append(.{ .Bool = true });
            } else {
                try tokens.append(curr_token);
            }
            curr_token = .{ .None = {} };
        }

        // Tokenize String
        if (char == 34) {
            if (curr_token == .None) {
                curr_token = .{ .String = "" };
                continue;
            } else if (curr_token == .String) {
                try tokens.append(curr_token);
                curr_token = .{ .None = {} };
                continue;
            }
        }
        if ((char >= 35 and char <= 126) or char == 32 or char == 33) {
            if (curr_token == .String) {
                if (char == 92) {
                    skip += 1;
                    curr_token.String = try mem.join(allocator, "", &[_][]const u8{ curr_token.String, &[_]u8{cleaned[i + 1]} });
                    continue;
                } else {
                    curr_token.String = try mem.join(allocator, "", &[_][]const u8{ curr_token.String, &[_]u8{char} });
                    continue;
                }
            }
        }

        // Tokenize Number
        if ((char >= 48 and char <= 57) or char == 45 or char == 46) {
            if (curr_token == .None) {
                curr_token = .{ .Number = .{ .string = try mem.join(allocator, "", &[_][]const u8{ "", &[_]u8{char} }), .num = 0 } };
                continue;
            } else if (curr_token == .Number) {
                curr_token.Number.string = try mem.join(allocator, "", &[_][]const u8{ curr_token.Number.string, &[_]u8{char} });
                continue;
            }
        } else if (curr_token == .Number) {
            curr_token.Number.num = try std.fmt.parseFloat(f64, curr_token.Number.string);
            try tokens.append(curr_token);
            curr_token = .{ .None = {} };
        }

        // Tokenize #
        if (char == 35) {
            try tokens.append(Token{ .DefSym = {} });
            continue;
        }

        // Tokenize !
        if (char == 33) {
            try tokens.append(Token{ .CallSym = {} });
            continue;
        }

        // Tokenize :
        if (char == 58) {
            try tokens.append(Token{ .Colon = {} });
            continue;
        }

        // Tokenize &
        if (char == 38) {
            try tokens.append(Token{ .If = {} });
            continue;
        }

        // Tokenize ,
        if (char == 44) {
            try tokens.append(Token{ .Comma = {} });
            continue;
        }

        // Tokenize {
        if (char == 123) {
            try tokens.append(Token{ .BlockStart = {} });
            continue;
        }

        // Tokenize }
        if (char == 125) {
            try tokens.append(Token{ .BlockEnd = {} });
            continue;
        }

        // Tokenize (
        if (char == 40) {
            try tokens.append(Token{ .TupleStart = {} });
            continue;
        }

        // Tokenize )
        if (char == 41) {
            try tokens.append(Token{ .TupleEnd = {} });
            continue;
        }

        // Tokenize [
        if (char == 91) {
            try tokens.append(Token{ .IndexStart = {} });
            continue;
        }

        // Tokenize ]
        if (char == 93) {
            try tokens.append(Token{ .IndexEnd = {} });
            continue;
        }

        // Tokenize _
        if (char == 95) {
            try tokens.append(Token{ .Void = {} });
            continue;
        }

        // Tokenize @
        if (char == 64) {
            try tokens.append(Token{ .TypeSym = {} });
            continue;
        }

        // Tokenize $
        if (char == 36) {
            try tokens.append(Token{ .DeclSym = {} });
            continue;
        }

        //Tokenize %
        if (char == 37) {
            try tokens.append(Token{ .JmpLabel = {} });
            continue;
        }

        //Tokenize ^
        if (char == 94) {
            try tokens.append(Token{ .JmpSym = {} });
            continue;
        }
        std.debug.panic("Invalid Token: {c}\n", .{char});
    }

    return tokens.toOwnedSlice();
}