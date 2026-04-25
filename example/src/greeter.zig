const std = @import("std");

/// Returns a greeting string (project-specific @greeting macro).
pub fn greet() []const u8 {
    return @greeting("World");
}

/// Returns the ISO-8601 UTC timestamp recorded at build time
/// via the built-in @buildTimestamp() macro.
pub fn builtAt() []const u8 {
    return @buildTimestamp();
}

/// Returns the optimize mode recorded at build time
/// via the built-in @buildMode() macro.
pub fn buildMode() []const u8 {
    return @buildMode();
}
