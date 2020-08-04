const std = @import("std");
const process = std.process;
const mem = std.mem;

const as = @import("assembler.zig");
const rt = @import("runtime.zig");

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = &arena.allocator;

    var arg_it = process.args();

    _ = arg_it.skip();

    const file = try std.fs.cwd().openFile(try (arg_it.next(allocator).?), .{});
    defer file.close();
    const code = try file.reader().readAllAlloc(allocator, std.math.maxInt(usize));

    var assembly = try as.assemble(rt.SimpleRuntime, allocator, code);

    try rt.SimpleRuntime.run(allocator, assembly, "main");
}
