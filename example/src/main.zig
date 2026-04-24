const std = @import("std");
const example = @import("example");
const embeds = @import("embedded_assets");

pub fn main() !void {
    // Prints to stderr, ignoring potential errors.
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
    try example.bufferedPrint();

    for (embeds.list()) |asset| {
        std.debug.print("Embedded Asset: {s}\n", .{asset.path});
    }
}
