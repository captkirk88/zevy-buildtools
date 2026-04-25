const std = @import("std");

/// Expansion function for a custom `@macro`.
///
/// Receives the raw argument string between the outer parentheses.
/// For `@myMacro(a, b)` the `args` value is `"a, b"`.
///
/// Returns Zig source code that replaces the entire `@name(...)` call.
/// Allocate the result from `allocator`; `expandMacros` will free it after use.
pub const MacroFn = *const fn (io: std.Io, allocator: std.mem.Allocator, args: []const u8) anyerror![]u8;

/// Defines a custom `@macro` that prebuild will expand in source files.
pub const MacroDefinition = struct {
    /// The macro name **without** the leading `@`.
    /// E.g. `"myMacro"` matches `@myMacro(...)` in source files.
    name: []const u8,
    /// Expansion function — returns the code that replaces `@name(...)`.
    expand: MacroFn,
};
