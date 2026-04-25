const std = @import("std");
const macro_mod = @import("macro.zig");
const MacroDefinition = macro_mod.MacroDefinition;
const MacroContext = macro_mod.MacroContext;
const CodeBuilder = macro_mod.CodeBuilder;

// ── @buildTimestamp() ────────────────────────────────────────────────────────

/// Expands `@buildTimestamp()` to an ISO-8601 UTC date-time string literal,
/// e.g. `"2026-04-25T14:30:00Z"`.
pub const build_timestamp: MacroDefinition = .{
    .name = "buildTimestamp",
    .expand = expandBuildTimestamp,
};

fn expandBuildTimestamp(code: *CodeBuilder, context: MacroContext) anyerror!void {
    const ts = std.Io.Timestamp.now(context.io, std.Io.Clock.real);
    const epoch_s = std.time.epoch.EpochSeconds{ .secs = @intCast(@max(0, ts.toSeconds())) };
    const year_day = epoch_s.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_secs = epoch_s.getDaySeconds();
    const rendered = try std.fmt.allocPrint(
        context.allocator,
        "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z",
        .{
            year_day.year,
            month_day.month.numeric(),
            @as(u32, month_day.day_index) + 1,
            day_secs.getHoursIntoDay(),
            day_secs.getMinutesIntoHour(),
            day_secs.getSecondsIntoMinute(),
        },
    );
    defer context.allocator.free(rendered);
    try code.stringLiteral(rendered);
}

// ── @envVar(NAME) ────────────────────────────────────────────────────────────

/// Expands `@envVar(MY_VAR)` to the value of `MY_VAR` as a string literal.
/// If the variable is not set, the expansion emits a `@compileError(...)` so
/// the downstream compile fails with a clear message.
pub const env_var: MacroDefinition = .{
    .name = "envVar",
    .expand = expandEnvVar,
};

fn expandEnvVar(code: *CodeBuilder, context: MacroContext) anyerror!void {
    const name = std.mem.trim(u8, context.args, " \t\"");
    const block = std.process.Environ.GlobalBlock.global;
    const environ = std.process.Environ{ .block = block };
    const value = std.process.Environ.getAlloc(environ, context.allocator, name) catch |err| switch (err) {
        error.EnvironmentVariableMissing => {
            const message = try std.fmt.allocPrint(context.allocator, "prebuild: environment variable '{s}' is not set", .{name});
            defer context.allocator.free(message);
            try code.compileError(message);
            return;
        },
        else => return err,
    };
    defer context.allocator.free(value);
    try code.stringLiteral(value);
}

// ── @buildMode() ─────────────────────────────────────────────────────────────

/// Expands `@buildMode(debug|safe|small|fast)` to the matching
/// `std.builtin.OptimizeMode` tag name as a string literal for embedding.
///
/// The single argument is the optimize tag passed from `build.zig`:
/// ```zig
/// .{ .name = "buildMode", .expand = buildtools.prebuild.builtins.buildModeExpander(optimize) },
/// ```
/// Because `MacroFn` is stateless, use `buildModeExpander` to capture the
/// optimize value and return a ready-to-register `MacroDefinition`.
pub fn buildModeExpander(optimize: std.builtin.OptimizeMode) MacroDefinition {
    const tag: *const fn (*CodeBuilder, MacroContext) anyerror!void = switch (optimize) {
        .Debug => struct {
            fn f(code: *CodeBuilder, _: MacroContext) anyerror!void {
                try code.stringLiteral("Debug");
            }
        }.f,
        .ReleaseSafe => struct {
            fn f(code: *CodeBuilder, _: MacroContext) anyerror!void {
                try code.stringLiteral("ReleaseSafe");
            }
        }.f,
        .ReleaseSmall => struct {
            fn f(code: *CodeBuilder, _: MacroContext) anyerror!void {
                try code.stringLiteral("ReleaseSmall");
            }
        }.f,
        .ReleaseFast => struct {
            fn f(code: *CodeBuilder, _: MacroContext) anyerror!void {
                try code.stringLiteral("ReleaseFast");
            }
        }.f,
    };
    return .{ .name = "buildMode", .expand = tag };
}

// ── Tests ─────────────────────────────────────────────────────────────────────

test "build_timestamp produces a quoted ISO-8601 string" {
    const expandMacros = @import("root.zig").expandMacros;
    const result = try expandMacros(
        std.testing.io,
        std.testing.allocator,
        "const ts = @buildTimestamp();",
        &.{build_timestamp},
    );
    defer std.testing.allocator.free(result);
    // Should start with `const ts = "` and end with `Z";`
    try std.testing.expect(std.mem.startsWith(u8, result, "const ts = \""));
    try std.testing.expect(std.mem.endsWith(u8, result, "Z\";"));
    // Length sanity: YYYY-MM-DDTHH:MM:SSZ = 20 chars + 2 quotes = 22
    const quoted_len = result.len - "const ts = ".len - ";".len;
    try std.testing.expectEqual(@as(usize, 22), quoted_len);
}

test "env_var emits compileError when variable not set" {
    const expandMacros = @import("root.zig").expandMacros;
    // Use a name that will certainly not be set.
    const result = try expandMacros(
        std.testing.io,
        std.testing.allocator,
        "@envVar(__ZEVY_BUILDTOOLS_SURELY_NOT_SET__)",
        &.{env_var},
    );
    defer std.testing.allocator.free(result);
    try std.testing.expect(std.mem.startsWith(u8, result, "@compileError("));
}

test "buildModeExpander Debug" {
    const expandMacros = @import("root.zig").expandMacros;
    const def = buildModeExpander(.Debug);
    const result = try expandMacros(
        std.testing.io,
        std.testing.allocator,
        "const mode = @buildMode();",
        &.{def},
    );
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("const mode = \"Debug\";", result);
}
