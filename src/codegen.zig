const std = @import("std");
const Allocator = std.mem.Allocator;

const ir = @import("ir.zig");

// transform an ir module into C code
pub fn generate(alloc: Allocator, mod: ir.Ir, writer: anytype) !void {
    for (mod.literals.items, 0..) |literal, i| {
        switch (literal) {
            .string => |str_lit| {
                try writer.print("const char *literal{} = \"{s}\";", .{ i, str_lit });
            },
            .number => |num_lit| {
                try writer.print("const int literal{} = {};", .{ i, num_lit });
            },
            .decimal => |dec_lit| {
                try writer.print("const double literal{} = {d};", .{ i, dec_lit });
            },
        }
        try writer.writeAll("\n");
    }

    for (mod.exprs.items, 0..) |expr, i| {
        try generateExpr(alloc, mod, i, expr, writer);
        try writer.writeAll("\n");
    }
}

fn generateExpr(alloc: Allocator, mod: ir.Ir, i: usize, expr: ir.Expr, writer: anytype) !void {
    _ = alloc;
    switch (expr) {
        .literal => |lit| {
            switch (mod.literals.items[lit]) {
                .string => {
                    try writer.print("char *expr{} = literal{};", .{ i, lit });
                },
                .number => {
                    try writer.print("int expr{} = literal{};", .{ i, lit });
                },
                .decimal => {
                    try writer.print("double expr{} = literal{};", .{ i, lit });
                },
            }
        },
        .block => |block| {
            try writer.print("void expr{}() {{\n", .{i});
            for (mod.blocks.items[block].ops.items) |op| {
                switch (op.kind) {
                    .call => {
                        try writer.print("expr{}(", .{op.data.call.cap});
                        for (op.data.call.args.ptr..op.data.call.args.ptr + op.data.call.args.len, 0..) |arg, j| {
                            if (j != 0) try writer.writeAll(", ");
                            try writer.print("expr{}", .{arg});
                        }
                        try writer.writeAll(");");
                    },
                    else => {},
                }
                try writer.writeAll("\n");
            }
            try writer.writeAll("}");
        },
        .nil => {
            try writer.print("void *expr{} = NULL;", .{i});
        },
        else => {},
    }
}
