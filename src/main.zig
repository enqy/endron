const std = @import("std");
const process = std.process;
const mem = std.mem;

const tk = @import("tokenizer.zig");
const pa = @import("parser.zig");
const rt = @import("runtime.zig");

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(!gpa.deinit());
    var allocator = &gpa.allocator;

    var arg_it = process.args();

    _ = arg_it.skip();
    const filename = try (arg_it.next(allocator).?);
    defer allocator.free(filename);

    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();
    const code = try file.reader().readAllAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(code);

    const tokens = try tk.tokenize(allocator, code);
    defer {
        for (tokens) |t| t.deinit(allocator);
        allocator.free(tokens);
    }

    var parsed = try pa.parse(allocator, tokens);
    defer parsed.deinit();

    try rt.SimpleRuntime.run(&parsed);
}
