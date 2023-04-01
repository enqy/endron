const std = @import("std");
const log = std.log.scoped(.main);

const tokenizer = @import("tokenizer.zig");
const parser = @import("parser.zig");
const transformer = @import("transformer.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var args = std.process.args();

    _ = args.skip();
    const filename = args.next() orelse return error.InvalidFilename;

    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    const source = try file.reader().readAllAlloc(alloc, std.math.maxInt(usize));
    defer alloc.free(source);

    const tokens = try tokenizer.tokenize(alloc, source);
    defer alloc.free(tokens);

    var tree = try parser.parse(alloc, source, tokens);
    defer tree.deinit();
    try tree.root.render(std.io.getStdOut().writer(), 0);

    var ir = try transformer.transform(alloc, tree);
    defer ir.deinit();

    for (ir.blocks.items) |block| {
        log.info("block {}:", .{block.index});
        for (block.ops.items) |op| {
            switch (op.kind) {
                .decl => {
                    log.info("  decl: {} = {}", .{ op.data.decl.type, ir.exprs.items[op.data.decl.value] });
                },
                .type => {
                    if (op.data.type.args) |cargs| {
                        log.info("  type: {} <- {}", .{ ir.exprs.items[op.data.type.cap], ir.exprs.items[cargs.ptr] });
                    } else {
                        log.info("  type: {}", .{ir.exprs.items[op.data.type.cap]});
                    }
                },
                .set => {
                    log.info("  set: {} = {}", .{ ir.exprs.items[op.data.set.cap], ir.exprs.items[op.data.set.args.ptr] });
                },
                .call => {
                    log.info("  call: {}({})", .{ ir.exprs.items[op.data.call.cap], ir.exprs.items[op.data.call.args.ptr] });
                },
                .builtin => {
                    log.info("  builtin: {}({})", .{ ir.exprs.items[op.data.builtin.cap], ir.exprs.items[op.data.builtin.args.ptr] });
                },
                else => log.info("  {}", .{op}),
            }
        }
    }
}
