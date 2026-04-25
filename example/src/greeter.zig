/// Returns a greeting string (project-specific @greeting macro).
pub fn greet() []const u8 {
    return @greeting("Macro Users");
}

/// Returns a greeting string loaded from a module-backed macro file
/// via the project-specific @staticGreeting macro.
pub fn staticGreet() []const u8 {
    return @staticGreeting();
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
