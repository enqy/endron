const std = @import("std");
const log = std.log.scoped(.main);

const tokenizer = @import("tokenizer.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = std.process.args();

    _ = args.skip();
    const filename = args.next() orelse return error.InvalidFilename;
    log.info("filename: {s}", .{filename});

    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();
    const source = try file.reader().readAllAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(source);

    const tokens = try tokenizer.tokenize(allocator, source);
    var current_line: usize = 0;
    var current_column: usize = 0;
    for (tokens) |token| {
        while (current_line < token.line) : (current_line += 1) {
            current_column = 0;
            std.debug.print("\n", .{});
        }
        while (current_column < token.column) : (current_column += 1) {
            std.debug.print(" ", .{});
        }
        current_column += token.end - token.start;
        std.debug.print("{s}", .{source[token.start..token.end]});
    }
    defer allocator.free(tokens);
}
