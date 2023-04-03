const std = @import("std");
const Allocator = std.mem.Allocator;

const ast = @import("ast.zig");
const Tree = ast.Tree;

const ir = @import("ir.zig");

const builtin_map = std.ComptimeStringMap(usize, .{
    // types
    .{ "void", 0 },
    .{ "num", 1 },
    .{ "dec", 2 },
    .{ "str", 3 },
    .{ "bool", 4 },
    .{ "type", 5 },
    .{ "__placeholder", 6 },
    .{ "__placeholder2", 7 },
    .{ "__placeholder3", 8 },
    .{ "__placeholder4", 9 },
    .{ "fn", 10 },
    .{ "struct", 11 },

    // functions
    .{ "import", 12 },
});

pub fn transform(alloc: Allocator, tree: *const Tree) !ir.Ir {
    var blocks = std.ArrayList(ir.Block).init(alloc);
    var exprs = std.ArrayList(ir.Expr).init(alloc);
    var literals = std.ArrayList(ir.Literal).init(alloc);

    var transformer = Transformer{
        .alloc = alloc,

        .blocks = &blocks,
        .exprs = &exprs,
        .literals = &literals,
    };

    try transformer.transformBlock(null, tree.root);

    return ir.Ir{
        .blocks = blocks,
        .exprs = exprs,
        .literals = literals,
    };
}

pub const Transformer = struct {
    alloc: Allocator,

    blocks: *std.ArrayList(ir.Block),
    exprs: *std.ArrayList(ir.Expr),
    literals: *std.ArrayList(ir.Literal),

    pub fn transformBlock(self: *Transformer, parent_block: ?*ir.Block, ast_block: ast.Block) anyerror!void {
        _ = try self.blocks.addOne();
        const index = self.blocks.items.len - 1;
        var block = ir.Block{
            .index = self.blocks.items.len - 1,

            .parent = if (parent_block) |p| p.index else 0,
            .ops = std.ArrayList(ir.Op).init(self.alloc),

            .ident_map = std.StringArrayHashMap(usize).init(self.alloc),
        };

        for (ast_block.ops) |ast_op| {
            try self.transformOp(&block, ast_op);
        }

        self.blocks.items[index] = block;
    }

    fn transformOp(self: *Transformer, parent_block: *ir.Block, ast_op: ast.Op) !void {
        switch (ast_op) {
            .decl => |op_decl| {
                const type_expr = try self.transformExpr(parent_block, op_decl.type);
                const value_expr = if (op_decl.value) |v| try self.transformExpr(parent_block, v) else blk: {
                    // no value so create a empty expr to fill in later
                    try self.exprs.append(ir.Expr{ .nil = {} });
                    break :blk self.exprs.items.len - 1;
                };

                // add cap to ident_map
                if (op_decl.cap.expr != .ident) std.debug.panic("decl capture must be an ident!", .{});
                if (parent_block.ident_map.get(op_decl.cap.expr.ident)) |_| std.debug.panic("ident `{s}` already exists in ident_map!", .{op_decl.cap.expr.ident});
                try parent_block.ident_map.putNoClobber(op_decl.cap.expr.ident, value_expr);

                try parent_block.ops.append(ir.Op{
                    .kind = .decl,
                    .data = .{
                        .decl = ir.Op.Data.Decl{
                            .type = type_expr,
                            .value = value_expr,
                        },
                    },
                });
            },
            .type => |op_type| {
                const cap_expr = try self.transformExpr(parent_block, op_type.cap);

                const args_expr = blk: {
                    if (op_type.args) |args| {
                        const first_arg_index = self.exprs.items.len;
                        for (args) |_| {
                            try self.exprs.append(ir.Expr{ .nil = {} });
                        }
                        for (args, 0..) |arg, i| {
                            const transformed = try self.transformExprRaw(parent_block, arg);
                            self.exprs.items[first_arg_index + i] = transformed;
                        }
                        break :blk ir.ArgsExpr{
                            .ptr = first_arg_index,
                            .len = args.len,
                        };
                    } else break :blk null;
                };

                try parent_block.ops.append(ir.Op{
                    .kind = .type,
                    .data = .{
                        .type = ir.Op.Data.Type{
                            .cap = cap_expr,
                            .args = args_expr,
                        },
                    },
                });
            },
            .set => |op_set| {
                const cap_expr = try self.transformExpr(parent_block, op_set.cap);

                const first_arg_index = self.exprs.items.len;
                for (op_set.args) |_| {
                    try self.exprs.append(ir.Expr{ .nil = {} });
                }
                for (op_set.args, 0..) |arg, i| {
                    const transformed = try self.transformExprRaw(parent_block, arg);
                    self.exprs.items[first_arg_index + i] = transformed;
                }
                const args_expr = ir.ArgsExpr{
                    .ptr = first_arg_index,
                    .len = op_set.args.len,
                };

                try parent_block.ops.append(ir.Op{
                    .kind = .set,
                    .data = .{
                        .set = ir.Op.Data.Set{
                            .cap = cap_expr,
                            .args = args_expr,
                        },
                    },
                });
            },
            .call => |op_call| {
                const cap_expr = try self.transformExpr(parent_block, op_call.cap);

                const first_arg_index = self.exprs.items.len;
                for (op_call.args) |_| {
                    try self.exprs.append(ir.Expr{ .nil = {} });
                }
                for (op_call.args, 0..) |arg, i| {
                    const transformed = try self.transformExprRaw(parent_block, arg);
                    self.exprs.items[first_arg_index + i] = transformed;
                }
                const args_expr = ir.ArgsExpr{
                    .ptr = first_arg_index,
                    .len = op_call.args.len,
                };

                try parent_block.ops.append(ir.Op{
                    .kind = .call,
                    .data = .{
                        .call = ir.Op.Data.Call{
                            .cap = cap_expr,
                            .args = args_expr,
                        },
                    },
                });
            },
            .builtin => |op_builtin| {
                const cap_expr = try self.transformExpr(parent_block, op_builtin.cap);

                const first_arg_index = self.exprs.items.len;
                for (op_builtin.args) |_| {
                    try self.exprs.append(ir.Expr{ .nil = {} });
                }
                for (op_builtin.args, 0..) |arg, i| {
                    const transformed = try self.transformExprRaw(parent_block, arg);
                    self.exprs.items[first_arg_index + i] = transformed;
                }
                const args_expr = ir.ArgsExpr{
                    .ptr = first_arg_index,
                    .len = op_builtin.args.len,
                };

                try parent_block.ops.append(ir.Op{
                    .kind = .builtin,
                    .data = .{
                        .builtin = ir.Op.Data.Builtin{
                            .cap = cap_expr,
                            .args = args_expr,
                        },
                    },
                });
            },
            .branch => |op_branch| {
                const cond_expr = try self.transformExpr(parent_block, op_branch.cond);
                const if_true_expr = try self.transformExpr(parent_block, op_branch.if_true);
                const if_false_expr = try self.transformExpr(parent_block, op_branch.if_false);

                try parent_block.ops.append(ir.Op{
                    .kind = .branch,
                    .data = .{
                        .branch = ir.Op.Data.Branch{
                            .cond = cond_expr,
                            .if_true = if_true_expr,
                            .if_false = if_false_expr,
                        },
                    },
                });
            },
            .loop => |op_loop| {
                const cond_expr = try self.transformExpr(parent_block, op_loop.cond);
                const body_expr = try self.transformExpr(parent_block, op_loop.body);
                const early_expr = if (op_loop.early) |early| try self.transformExpr(parent_block, early) else null;

                try parent_block.ops.append(ir.Op{
                    .kind = .loop,
                    .data = .{
                        .loop = ir.Op.Data.Loop{
                            .cond = cond_expr,
                            .body = body_expr,
                            .early = early_expr,
                        },
                    },
                });
            },
            .alu => |op_alu| {
                const func = @intToEnum(ir.Op.Data.Alu.Func, @enumToInt(op_alu.func));

                const first_arg_index = self.exprs.items.len;
                for (op_alu.args) |_| {
                    try self.exprs.append(ir.Expr{ .nil = {} });
                }
                for (op_alu.args, 0..) |arg, i| {
                    self.exprs.items[first_arg_index + i] = try self.transformExprRaw(parent_block, arg);
                }
                const args_expr = ir.ArgsExpr{
                    .ptr = first_arg_index,
                    .len = op_alu.args.len,
                };

                try parent_block.ops.append(ir.Op{
                    .kind = .alu,
                    .data = .{
                        .alu = ir.Op.Data.Alu{
                            .func = func,
                            .args = args_expr,
                        },
                    },
                });
            },
        }
    }

    fn transformExpr(self: *Transformer, parent: *ir.Block, expr: *const ast.Expr) !usize {
        const ir_expr = try self.transformExprRaw(parent, expr);
        try self.exprs.append(ir_expr);
        return self.exprs.items.len - 1;
    }

    fn transformExprRaw(self: *Transformer, parent: *ir.Block, expr: *const ast.Expr) !ir.Expr {
        switch (expr.expr) {
            .ident => |ident| {
                // first check if it is a builtin type
                if (builtin_map.get(ident)) |builtin_index| {
                    return ir.Expr{ .builtin = builtin_index };
                }

                return ir.Expr{
                    .cap = parent.ident_map.get(ident) orelse std.debug.panic("unknown ident: `{s}`", .{ident}),
                };
            },
            .literal => |literal| {
                switch (literal) {
                    .string => |lit_string| {
                        try self.literals.append(ir.Literal{
                            .string = lit_string,
                        });
                    },
                    .number => |lit_number| {
                        try self.literals.append(ir.Literal{
                            .number = lit_number,
                        });
                    },
                    .decimal => |lit_decimal| {
                        try self.literals.append(ir.Literal{
                            .decimal = lit_decimal,
                        });
                    },
                }
                return ir.Expr{
                    .literal = self.literals.items.len - 1,
                };
            },
            .block => |block| {
                try self.transformBlock(parent, block);
                return ir.Expr{
                    .block = self.blocks.items.len - 1,
                };
            },
            .scope => |scope| {
                var path = std.ArrayList(ir.ScopePart).init(self.alloc);

                if (scope.root == -1) {
                    try path.append(ir.ScopePart{ .arg = {} });
                } else if (scope.root == 0) {
                    try path.append(ir.ScopePart{ .top = {} });
                } else {
                    try path.append(ir.ScopePart{ .up = scope.upper });
                    for (scope.path) |part| {
                        try path.append(ir.ScopePart{ .ident = part });
                    }
                }

                return ir.Expr{ .scope = .{ .path = path } };
            },
        }
    }
};
