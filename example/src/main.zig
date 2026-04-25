const std = @import("std");
const example = @import("example");
const embeds = @import("embedded_assets");

pub fn main() !void {
    // Project-specific macro: @greeting("World") → "Hello, World!"
    std.debug.print("{s}\n", .{example.greeter.greet()});
    // Module-backed macro: static_greeting_expr.zig defines `main(code, context)`.
    std.debug.print("{s}\n", .{example.greeter.staticGreet()});

    // Built-in macros shipped with buildtools.prebuild.builtins:
    std.debug.print("Built at:   {s}\n", .{example.greeter.builtAt()});
    std.debug.print("Build mode: {s}\n", .{example.greeter.buildMode()});

    for (embeds.list()) |asset| {
        std.debug.print("Embedded Asset: {s}\n", .{asset.path});
    }
}
