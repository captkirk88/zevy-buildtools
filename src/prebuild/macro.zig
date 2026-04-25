const std = @import("std");

pub const MacroContext = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    args: []const u8,

    pub fn trimmedArgs(self: MacroContext) []const u8 {
        return std.mem.trim(u8, self.args, " \t\r\n");
    }

    pub fn stringLiteralArg(self: MacroContext) ?[]const u8 {
        const trimmed = self.trimmedArgs();
        if (trimmed.len < 2 or trimmed[0] != '"' or trimmed[trimmed.len - 1] != '"') {
            return null;
        }
        return trimmed[1 .. trimmed.len - 1];
    }
};

pub const CodeBuilder = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8) = .empty,

    pub const default_file_max_bytes: usize = 16 * 1024 * 1024;

    pub fn init(allocator: std.mem.Allocator) CodeBuilder {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *CodeBuilder) void {
        self.buffer.deinit(self.allocator);
    }

    pub fn raw(self: *CodeBuilder, code: []const u8) error{OutOfMemory}!void {
        try self.buffer.appendSlice(self.allocator, code);
    }

    /// Read a `.zig` fragment from disk and append it verbatim.
    ///
    /// `path` is resolved relative to the build root / current working
    /// directory of the running build.
    pub fn file(self: *CodeBuilder, context: MacroContext, path: []const u8) anyerror!void {
        const source = try std.Io.Dir.cwd().readFileAlloc(
            context.io,
            path,
            context.allocator,
            .limited(default_file_max_bytes),
        );
        defer context.allocator.free(source);
        try self.raw(source);
    }

    pub fn stringLiteral(self: *CodeBuilder, value: []const u8) error{OutOfMemory}!void {
        try appendStringLiteral(&self.buffer, self.allocator, value);
    }

    pub fn stringLiteralFmt(self: *CodeBuilder, comptime fmt: []const u8, args: anytype) anyerror!void {
        const rendered = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(rendered);
        try self.stringLiteral(rendered);
    }

    pub fn compileError(self: *CodeBuilder, message: []const u8) error{OutOfMemory}!void {
        try self.raw("@compileError(");
        try self.stringLiteral(message);
        try self.raw(");");
    }

    pub fn toOwnedSlice(self: *CodeBuilder) error{OutOfMemory}![]u8 {
        const allocator = self.allocator;
        const owned = try self.buffer.toOwnedSlice(allocator);
        self.* = .{ .allocator = allocator };
        return owned;
    }
};

fn appendStringLiteral(
    buffer: *std.ArrayListUnmanaged(u8),
    allocator: std.mem.Allocator,
    value: []const u8,
) error{OutOfMemory}!void {
    try buffer.append(allocator, '"');
    for (value) |byte| {
        switch (byte) {
            '\\' => try buffer.appendSlice(allocator, "\\\\"),
            '\n' => try buffer.appendSlice(allocator, "\\n"),
            '\r' => try buffer.appendSlice(allocator, "\\r"),
            '\t' => try buffer.appendSlice(allocator, "\\t"),
            '"' => try buffer.appendSlice(allocator, "\\\""),
            else => if (byte < 0x20 or byte >= 0x7f) {
                const hex_str = try std.fmt.allocPrint(allocator, "\\x{X:0>2}", .{byte});
                defer allocator.free(hex_str);
                try buffer.appendSlice(allocator, hex_str);
            } else {
                try buffer.append(allocator, byte);
            },
        }
    }
    try buffer.append(allocator, '"');
}

/// Expansion function for a custom `@macro`.
///
/// Receives the raw argument string between the outer parentheses.
/// For `@myMacro(a, b)` the `args` value is `"a, b"`.
///
/// Writes Zig source code that replaces the entire `@name(...)` call.
/// Use `CodeBuilder` helpers to avoid manual string escaping.
pub const MacroFn = *const fn (code: *CodeBuilder, context: MacroContext) anyerror!void;

/// Defines a custom `@macro` that prebuild will expand in source files.
pub const MacroDefinition = struct {
    /// The macro name **without** the leading `@`.
    /// E.g. `"myMacro"` matches `@myMacro(...)` in source files.
    name: []const u8,
    /// Expansion function — writes the code that replaces `@name(...)`.
    expand: MacroFn,
};

/// Create a `MacroDefinition` from an imported Zig module.
///
/// The imported module must expose:
/// `pub fn main(code: *CodeBuilder, context: MacroContext) !void`
pub fn moduleDefinition(comptime name: []const u8, comptime module: type) MacroDefinition {
    comptime {
        if (!@hasDecl(module, "main")) {
            @compileError("module-backed macro must define `pub fn main(code, context) !void`");
        }
        const check: MacroFn = module.main;
        _ = check;
    }

    return .{
        .name = name,
        .expand = struct {
            fn expand(code: *CodeBuilder, context: MacroContext) anyerror!void {
                try module.main(code, context);
            }
        }.expand,
    };
}
