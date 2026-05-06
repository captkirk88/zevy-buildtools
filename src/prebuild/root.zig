const std = @import("std");
const macro_mod = @import("macro.zig");
pub const MacroDefinition = macro_mod.MacroDefinition;
pub const MacroFn = macro_mod.MacroFn;
pub const MacroContext = macro_mod.MacroContext;
pub const CodeBuilder = macro_mod.CodeBuilder;
pub const moduleDefinition = macro_mod.moduleDefinition;

/// Ready-to-use `MacroDefinition` values shipped with zevy-buildtools.
/// Include any of these directly in your `PrebuildOptions.macros` slice.
pub const builtins = @import("builtins.zig");

/// Options for `addPrebuildStep`.
pub const PrebuildOptions = struct {
    /// Directory to scan for `.zig` files, relative to the build root.
    src_dir: []const u8 = "src",
    /// Macros to expand.  An empty slice means every file is copied verbatim.
    macros: []const MacroDefinition = &.{},
    /// Maximum single-file size accepted by `readFileAlloc`.  Default: 16 MiB.
    max_file_bytes: usize = 16 * 1024 * 1024,
};

/// Returned by `addPrebuildStep`.  Provides `LazyPath`s into the generated
/// source tree where all custom `@macro` calls have been expanded.
pub const PrebuildResult = struct {
    wf: *std.Build.Step.WriteFile,

    /// Returns a `LazyPath` for the expanded version of a single source file.
    ///
    /// `relative_path` is relative to the original `src_dir`,
    /// e.g. `"root.zig"` or `"sub/module.zig"`.
    pub fn file(self: PrebuildResult, b: *std.Build, relative_path: []const u8) std.Build.LazyPath {
        return self.wf.getDirectory().path(b, relative_path);
    }

    /// Returns a `LazyPath` to the generated directory that mirrors `src_dir`.
    pub fn directory(self: PrebuildResult) std.Build.LazyPath {
        return self.wf.getDirectory();
    }
};

/// Register a prebuild macro-expansion step.
///
/// All `.zig` files under `options.src_dir` are scanned.  Any `@macroName(...)`
/// call whose name matches a registered `MacroDefinition` is replaced by the
/// code written by that definition's `expand` function.  The results are
/// written through a `WriteFile` build step so that Zig's cache system tracks
/// them automatically.
///
/// Files that contain no matching macro calls are copied verbatim using
/// `WriteFile.addCopyFile` — their source bytes are never read into memory.
///
/// ```zig
/// const pre = try buildtools.prebuild.addMacrosStep(b, .{
///     .src_dir = "src",
///     .macros  = &.{
///         .{ .name = "genFields", .expand = myGenFieldsFn },
///     },
/// });
/// const mod = b.addModule("mylib", .{
///     .root_source_file = pre.file(b, "root.zig"),
/// });
/// ```
pub fn addMacrosStep(b: *std.Build, options: PrebuildOptions) anyerror!PrebuildResult {
    const allocator = b.allocator;
    const io = b.graph.io;
    const wf = b.addWriteFiles();

    var src_dir = try std.Io.Dir.cwd().openDir(io, options.src_dir, .{
        .iterate = true,
        .access_sub_paths = true,
    });
    defer src_dir.close(io);

    var path_buf: std.ArrayListUnmanaged(u8) = .empty;
    defer path_buf.deinit(allocator);

    try processDirectory(allocator, io, &src_dir, &path_buf, options, wf);

    return .{ .wf = wf };
}

// ── Internal helpers ─────────────────────────────────────────────────────────

fn processDirectory(
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: *std.Io.Dir,
    path_buf: *std.ArrayListUnmanaged(u8),
    options: PrebuildOptions,
    wf: *std.Build.Step.WriteFile,
) anyerror!void {
    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
        switch (entry.kind) {
            .directory => {
                const saved = path_buf.items.len;
                if (saved > 0) try path_buf.append(allocator, '/');
                try path_buf.appendSlice(allocator, entry.name);
                var child = try dir.openDir(io, entry.name, .{
                    .iterate = true,
                    .access_sub_paths = true,
                });
                defer child.close(io);
                try processDirectory(allocator, io, &child, path_buf, options, wf);
                path_buf.shrinkRetainingCapacity(saved);
            },
            .file => {
                if (!std.mem.endsWith(u8, entry.name, ".zig")) continue;
                const saved = path_buf.items.len;
                if (saved > 0) try path_buf.append(allocator, '/');
                try path_buf.appendSlice(allocator, entry.name);
                try processFile(allocator, io, path_buf.items, options, wf);
                path_buf.shrinkRetainingCapacity(saved);
            },
            else => {},
        }
    }
}

fn processFile(
    allocator: std.mem.Allocator,
    io: std.Io,
    /// Path relative to `src_dir`, using forward slashes.
    relative_path: []const u8,
    options: PrebuildOptions,
    wf: *std.Build.Step.WriteFile,
) anyerror!void {
    // Build the full source path.  Forward slashes work on all supported OSes.
    // Allocated from b.allocator so its lifetime covers the WriteFile step.
    const full_path = try std.mem.concat(allocator, u8, &.{ options.src_dir, "/", relative_path });

    if (options.macros.len == 0) {
        // Fast path: no macros configured — copy without reading file content.
        _ = wf.addCopyFile(.{ .cwd_relative = full_path }, relative_path);
        return;
    }

    const source = try std.Io.Dir.cwd().readFileAlloc(
        io,
        full_path,
        allocator,
        .limited(options.max_file_bytes),
    );
    defer allocator.free(source);

    if (!sourceHasMacros(source, options.macros)) {
        // No macro call sites found — copy verbatim.
        _ = wf.addCopyFile(.{ .cwd_relative = full_path }, relative_path);
        return;
    }

    // Expand macros.  `wf.add` dups the bytes internally, so we can free
    // `expanded` as soon as the call returns.
    const expanded = try expandMacros(io, allocator, source, options.macros);
    defer allocator.free(expanded);
    _ = wf.add(relative_path, expanded);
}

/// Quick pre-scan: returns `true` when `source` contains at least one
/// `@macroName` token so that we can skip full expansion for clean files.
fn sourceHasMacros(source: []const u8, macros: []const MacroDefinition) bool {
    for (macros) |m| {
        // Build "@name" on the stack to avoid a heap allocation per file.
        var buf: [256]u8 = undefined;
        if (1 + m.name.len > buf.len) continue;
        buf[0] = '@';
        @memcpy(buf[1..][0..m.name.len], m.name);
        if (std.mem.indexOf(u8, source, buf[0 .. 1 + m.name.len]) != null) return true;
    }
    return false;
}

/// Expand all registered macros in `source`.
///
/// The scanner honours Zig line comments (`//`), regular string literals,
/// character literals, and multiline string literals (`\\`) so that macro
/// tokens inside those constructs are **not** expanded.
///
/// Caller owns the returned slice.
pub fn expandMacros(
    io: std.Io,
    allocator: std.mem.Allocator,
    source: []const u8,
    macros: []const MacroDefinition,
) anyerror![]u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    try out.ensureTotalCapacity(allocator, source.len);

    var pos: usize = 0;
    while (pos < source.len) {
        const c = source[pos];

        // ── Line comment: `//` … EOL ──────────────────────────────────────
        if (c == '/' and pos + 1 < source.len and source[pos + 1] == '/') {
            const eol = std.mem.indexOfScalarPos(u8, source, pos, '\n') orelse source.len;
            try out.appendSlice(allocator, source[pos..eol]);
            pos = eol;
            continue;
        }

        // ── Zig multiline string literal: `\\` … EOL ─────────────────────
        if (c == '\\' and pos + 1 < source.len and source[pos + 1] == '\\') {
            const eol = std.mem.indexOfScalarPos(u8, source, pos, '\n') orelse source.len;
            try out.appendSlice(allocator, source[pos..eol]);
            pos = eol;
            continue;
        }

        // ── Regular string literal: `"…"` ─────────────────────────────────
        if (c == '"') {
            const end = skipStringLiteral(source, pos);
            try out.appendSlice(allocator, source[pos..end]);
            pos = end;
            continue;
        }

        // ── Character literal: `'.'` ──────────────────────────────────────
        if (c == '\'') {
            const end = skipCharLiteral(source, pos);
            try out.appendSlice(allocator, source[pos..end]);
            pos = end;
            continue;
        }

        // ── Potential macro invocation: `@name(…)` ────────────────────────
        if (c == '@') {
            if (try tryExpandMacro(io, allocator, source, pos, macros, &out)) |new_pos| {
                pos = new_pos;
                continue;
            }
        }

        // Default: copy the character unchanged.
        try out.append(allocator, c);
        pos += 1;
    }

    return out.toOwnedSlice(allocator);
}

/// Attempt to match a registered macro at `source[at]` (which must be `@`).
///
/// On success, appends the expanded text to `out` and returns the new scan
/// position (one past the closing `)`).  Returns `null` if no macro matches.
fn tryExpandMacro(
    io: std.Io,
    allocator: std.mem.Allocator,
    source: []const u8,
    at: usize,
    macros: []const MacroDefinition,
    out: *std.ArrayListUnmanaged(u8),
) anyerror!?usize {
    std.debug.assert(source[at] == '@');
    const after_at = at + 1;

    for (macros) |macro| {
        const name = macro.name;
        if (after_at + name.len > source.len) continue;
        if (!std.mem.eql(u8, source[after_at..][0..name.len], name)) continue;

        const after_name = after_at + name.len;

        // Reject if followed by further identifier characters — it's a longer name.
        if (after_name < source.len and isIdentChar(source[after_name])) continue;

        // Must be immediately followed by `(`.
        if (after_name >= source.len or source[after_name] != '(') continue;

        const close = try findMatchingParen(source, after_name);
        const args = source[after_name + 1 .. close];

        var code = CodeBuilder.init(allocator);
        defer code.deinit();

        try macro.expand(&code, .{
            .io = io,
            .allocator = allocator,
            .args = args,
        });

        const replacement = try code.toOwnedSlice();
        defer allocator.free(replacement);
        try out.appendSlice(allocator, replacement);
        return close + 1;
    }

    return null;
}

/// Returns the index of the `)` that closes the `(` at `source[open]`.
/// Properly skips nested parentheses, string literals, char literals, and
/// multiline string lines so that balanced parens inside those are ignored.
fn findMatchingParen(source: []const u8, open: usize) !usize {
    std.debug.assert(source[open] == '(');
    var depth: usize = 0;
    var pos: usize = open;
    while (pos < source.len) {
        switch (source[pos]) {
            '(' => depth += 1,
            ')' => {
                depth -= 1;
                if (depth == 0) return pos;
            },
            '"' => pos = skipStringLiteral(source, pos) - 1,
            '\'' => pos = skipCharLiteral(source, pos) - 1,
            '\\' => if (pos + 1 < source.len and source[pos + 1] == '\\') {
                // Multiline string inside argument list — skip to EOL.
                const eol = std.mem.indexOfScalarPos(u8, source, pos, '\n') orelse source.len;
                pos = eol - 1; // incremented at loop bottom
            },
            else => {},
        }
        pos += 1;
    }
    return error.UnmatchedParen;
}

inline fn isIdentChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

/// Returns the position just past the closing `"` of a string literal.
/// `start` must point at the opening `"`.
fn skipStringLiteral(source: []const u8, start: usize) usize {
    var pos = start + 1;
    while (pos < source.len) : (pos += 1) {
        if (source[pos] == '\\') {
            pos += 1; // skip the escaped character
        } else if (source[pos] == '"') {
            return pos + 1;
        }
    }
    return pos;
}

/// Returns the position just past the closing `'` of a char literal.
/// `start` must point at the opening `'`.
fn skipCharLiteral(source: []const u8, start: usize) usize {
    var pos = start + 1;
    while (pos < source.len) : (pos += 1) {
        if (source[pos] == '\\') {
            pos += 1;
        } else if (source[pos] == '\'') {
            return pos + 1;
        }
    }
    return pos;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

test "expandMacros: no macros defined, source unchanged" {
    const src = "const x = @import(\"std\");\n";
    const result = try expandMacros(std.testing.io, std.testing.allocator, src, &.{});
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings(src, result);
}

test "expandMacros: simple substitution" {
    const macros = [_]MacroDefinition{.{
        .name = "hello",
        .expand = struct {
            fn f(code: *CodeBuilder, _: MacroContext) anyerror!void {
                try code.stringLiteral("world");
            }
        }.f,
    }};
    const result = try expandMacros(std.testing.io, std.testing.allocator, "const s = @hello();\n", &macros);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("const s = \"world\";\n", result);
}

test "expandMacros: args passed to expand function" {
    const macros = [_]MacroDefinition{.{
        .name = "rep",
        .expand = struct {
            fn f(code: *CodeBuilder, context: MacroContext) anyerror!void {
                try code.raw(context.args);
                try code.raw(context.args);
            }
        }.f,
    }};
    const result = try expandMacros(std.testing.io, std.testing.allocator, "const x = @rep(hi);\n", &macros);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("const x = hihi;\n", result);
}

test "expandMacros: skips line comments" {
    const macros = [_]MacroDefinition{.{
        .name = "boom",
        .expand = struct {
            fn f(_: *CodeBuilder, _: MacroContext) anyerror!void {
                return error.ShouldNotExpand;
            }
        }.f,
    }};
    const src = "// @boom()\nconst x = 1;\n";
    const result = try expandMacros(std.testing.io, std.testing.allocator, src, &macros);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings(src, result);
}

test "expandMacros: skips string literals" {
    const macros = [_]MacroDefinition{.{
        .name = "boom",
        .expand = struct {
            fn f(_: *CodeBuilder, _: MacroContext) anyerror!void {
                return error.ShouldNotExpand;
            }
        }.f,
    }};
    const src = "const s = \"@boom()\";\n";
    const result = try expandMacros(std.testing.io, std.testing.allocator, src, &macros);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings(src, result);
}

test "expandMacros: skips multiline string literals" {
    const macros = [_]MacroDefinition{.{
        .name = "boom",
        .expand = struct {
            fn f(_: *CodeBuilder, _: MacroContext) anyerror!void {
                return error.ShouldNotExpand;
            }
        }.f,
    }};
    const src = "const s =\n    \\\\@boom()\n    ;\n";
    const result = try expandMacros(std.testing.io, std.testing.allocator, src, &macros);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings(src, result);
}

test "expandMacros: does not match name prefix of longer identifier" {
    const macros = [_]MacroDefinition{.{
        .name = "foo",
        .expand = struct {
            fn f(code: *CodeBuilder, _: MacroContext) anyerror!void {
                try code.raw("EXPANDED");
            }
        }.f,
    }};
    // @fooBar must NOT match @foo
    const src = "const x = @fooBar();\n";
    const result = try expandMacros(std.testing.io, std.testing.allocator, src, &macros);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings(src, result);
}

test "expandMacros: multiple macros expanded in order" {
    const macros = [_]MacroDefinition{
        .{
            .name = "a",
            .expand = struct {
                fn f(code: *CodeBuilder, _: MacroContext) anyerror!void {
                    try code.raw("1");
                }
            }.f,
        },
        .{
            .name = "b",
            .expand = struct {
                fn f(code: *CodeBuilder, _: MacroContext) anyerror!void {
                    try code.raw("2");
                }
            }.f,
        },
    };
    const result = try expandMacros(std.testing.io, std.testing.allocator, "@a() + @b()", &macros);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("1 + 2", result);
}

test "expandMacros: nested parens in args" {
    const macros = [_]MacroDefinition{.{
        .name = "wrap",
        .expand = struct {
            fn f(code: *CodeBuilder, context: MacroContext) anyerror!void {
                try code.raw("(");
                try code.raw(context.args);
                try code.raw(")");
            }
        }.f,
    }};
    const result = try expandMacros(std.testing.io, std.testing.allocator, "@wrap(foo(1, 2))", &macros);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("(foo(1, 2))", result);
}

test "expandMacros: code builder escapes string literals" {
    const macros = [_]MacroDefinition{.{
        .name = "quoted",
        .expand = struct {
            fn f(code: *CodeBuilder, _: MacroContext) anyerror!void {
                try code.stringLiteral("line 1\n\"quoted\"");
            }
        }.f,
    }};
    const result = try expandMacros(std.testing.io, std.testing.allocator, "const s = @quoted();", &macros);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("const s = \"line 1\\n\\\"quoted\\\"\";", result);
}

test "expandMacros: code builder imports raw file" {
    const macros = [_]MacroDefinition{.{
        .name = "fromFile",
        .expand = struct {
            fn f(code: *CodeBuilder, context: MacroContext) anyerror!void {
                try code.file(context, "test_data/prebuild/raw_expr.zig");
            }
        }.f,
    }};
    const result = try expandMacros(std.testing.io, std.testing.allocator, "@fromFile()", &macros);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("pub const fragment = \"raw file macro\";\n", result);
}

test "expandMacros: module-backed macro definition" {
    const impl = struct {
        pub fn main(code: *CodeBuilder, _: MacroContext) !void {
            try code.stringLiteral("module-backed macro");
        }
    };
    const result = try expandMacros(
        std.testing.io,
        std.testing.allocator,
        "const x = @fromModule();",
        &.{moduleDefinition("fromModule", impl)},
    );
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("const x = \"module-backed macro\";", result);
}
