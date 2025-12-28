const std = @import("std");
const utils = @import("utils.zig");

pub fn addFmtStep(b: *std.Build, check: ?bool) !void {
    const allocator = std.heap.page_allocator;
    var files = try utils.getFilesFromPath(allocator, b, b.path("src"));
    defer files.deinit(allocator);
    const fmt = b.addFmt(.{
        .check = if (check) |c| c else false,
        .paths = files.items,
    });

    const fmt_step = b.step("fmt", "Check code formatting");
    fmt_step.dependOn(&fmt.step);
}
