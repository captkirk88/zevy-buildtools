const std = @import("std");

const Util = @This();

/// Options for embedding assets into the binary.
pub const EmbedAssetsOptions = struct {
    /// Filesystem path that will be scanned for assets (relative to repository root).
    assets_dir: []const u8 = "src/embedded_assets",
    /// Import name that will be attached to the owning module.
    import_name: []const u8 = "embedded_assets",
    /// Generated Zig file path (relative inside zig cache) containing lookup helpers.
    generated_file: []const u8 = "embedded_assets/generated.zig",
    /// Optional list of additional file paths to include (relative to repository root).
    additional_files: ?[]const []const u8 = null,
    /// Optional regex pattern for files to ignore (e.g., ".*\\.tmp$").
    ignore_regex: ?[]const u8 = null,
};

/// Add a module that embeds assets from a specified directory into the binary.
pub fn addEmbeddedAssetsModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    owner: *std.Build.Module,
    options: EmbedAssetsOptions,
) anyerror!*std.Build.Module {
    const allocator = b.allocator;

    var asset_paths = try std.ArrayList([]const u8).initCapacity(allocator, 8);
    defer {
        for (asset_paths.items) |path| allocator.free(path);
        asset_paths.deinit(allocator);
    }

    const assets_root_opt = try collectEmbeddedAssets(allocator, options, &asset_paths);
    defer if (assets_root_opt) |root| allocator.free(root);

    const generated_file = try writeEmbeddedModule(b, options, asset_paths.items, assets_root_opt);

    const embedded_module = b.createModule(.{
        .root_source_file = generated_file,
        .optimize = optimize,
        .target = target,
    });

    owner.addImport(options.import_name, embedded_module);

    return embedded_module;
}

fn collectEmbeddedAssets(
    allocator: std.mem.Allocator,
    options: EmbedAssetsOptions,
    asset_paths: *std.ArrayList([]const u8),
) anyerror!?[]const u8 {
    var dir = std.fs.cwd().openDir(options.assets_dir, .{ .iterate = true, .access_sub_paths = true }) catch |err| switch (err) {
        error.FileNotFound => {
            // If directory doesn't exist but we have additional files, that's still valid
            if (options.additional_files != null and options.additional_files.?.len > 0) {
                return null;
            }
            return err;
        },
        else => return err,
    };
    defer dir.close();

    const abs_dir = try std.fs.cwd().realpathAlloc(allocator, options.assets_dir);
    errdefer allocator.free(abs_dir);

    var path_buffer = std.ArrayListUnmanaged(u8){};
    defer path_buffer.deinit(allocator);

    try walkEmbeddedAssets(allocator, &dir, &path_buffer, asset_paths, options.ignore_regex);

    // Add optional additional files
    if (options.additional_files) |additional| {
        for (additional) |file_path| {
            // Check if file should be ignored
            if (shouldIgnorePath(file_path, options.ignore_regex)) {
                continue;
            }
            const duplicated = try allocator.dupe(u8, file_path);
            errdefer allocator.free(duplicated);
            try asset_paths.append(allocator, duplicated);
        }
    }

    if (asset_paths.items.len > 1) {
        std.sort.heap([]const u8, asset_paths.items, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.lessThan);
    }

    return abs_dir;
}

fn walkEmbeddedAssets(
    allocator: std.mem.Allocator,
    dir: *std.fs.Dir,
    path_buffer: *std.ArrayList(u8),
    asset_paths: *std.ArrayList([]const u8),
    ignore_regex: ?[]const u8,
) anyerror!void {
    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        switch (entry.kind) {
            .directory => {
                const original_len = path_buffer.items.len;
                if (original_len != 0) try path_buffer.append(allocator, '/');
                try path_buffer.appendSlice(allocator, entry.name);
                var child = try dir.openDir(entry.name, .{ .iterate = true, .access_sub_paths = true });
                defer child.close();
                try walkEmbeddedAssets(allocator, &child, path_buffer, asset_paths, ignore_regex);
                path_buffer.shrinkRetainingCapacity(original_len);
            },
            .file => {
                const original_len = path_buffer.items.len;
                if (original_len != 0) try path_buffer.append(allocator, '/');
                try path_buffer.appendSlice(allocator, entry.name);

                // Check if file should be ignored
                if (shouldIgnorePath(path_buffer.items, ignore_regex)) {
                    path_buffer.shrinkRetainingCapacity(original_len);
                    continue;
                }

                const relative_path = try allocator.dupe(u8, path_buffer.items);
                errdefer allocator.free(relative_path);
                try asset_paths.append(allocator, relative_path);
                path_buffer.shrinkRetainingCapacity(original_len);
            },
            else => {},
        }
    }
}

/// Check if a file path should be ignored based on a glob-like pattern.
/// Supports simple patterns: *.ext, prefix*, *suffix, dir/*, etc.
fn shouldIgnorePath(path: []const u8, pattern_opt: ?[]const u8) bool {
    if (pattern_opt == null) return false;
    const pattern = pattern_opt.?;

    // Empty pattern ignores nothing
    if (pattern.len == 0) return false;

    // Simple glob pattern matching
    // Supports: *.txt, *.*, dir/*, **/pattern, etc.

    // If pattern starts with *, match suffix
    if (std.mem.startsWith(u8, pattern, "*")) {
        const suffix = pattern[1..];
        if (suffix.len == 0) return true; // * matches everything
        if (std.mem.startsWith(u8, suffix, "*")) {
            // Handle ** patterns (match any path component)
            if (suffix.len == 1) return true;
            // ** followed by something - simplified: check if path contains the pattern
            return std.mem.containsAtLeast(u8, path, 1, suffix[1..]);
        }
        return std.mem.endsWith(u8, path, suffix);
    }

    // If pattern ends with *, match prefix
    if (std.mem.endsWith(u8, pattern, "*")) {
        const prefix = pattern[0 .. pattern.len - 1];
        return std.mem.startsWith(u8, path, prefix);
    }

    // Exact match
    return std.mem.eql(u8, path, pattern);
}

fn writeEmbeddedModule(
    b: *std.Build,
    options: EmbedAssetsOptions,
    asset_paths: []const []const u8,
    assets_root_opt: ?[]const u8,
) anyerror!std.Build.LazyPath {
    const allocator = b.allocator;

    if (asset_paths.len != 0 and assets_root_opt == null) {
        @panic("embedded assets root missing but files discovered");
    }

    var buffer = std.ArrayListUnmanaged(u8){};
    defer buffer.deinit(allocator);

    var embed_paths = std.ArrayListUnmanaged([]const u8){};
    defer {
        for (embed_paths.items) |path| allocator.free(path);
        embed_paths.deinit(allocator);
    }

    const write_files = b.addWriteFiles();

    if (assets_root_opt) |abs_root| {
        for (asset_paths) |relative_path| {
            const embed_rel_path = try std.mem.concat(allocator, u8, &[_][]const u8{ "assets/", relative_path });

            const copy_sub_path = try std.mem.concat(allocator, u8, &[_][]const u8{ "embedded_assets/", embed_rel_path });
            defer allocator.free(copy_sub_path);

            const source_sub_path = b.pathJoin(&.{ abs_root, relative_path });
            _ = write_files.addCopyFile(.{ .cwd_relative = source_sub_path }, copy_sub_path);

            embed_paths.append(allocator, embed_rel_path) catch |err| {
                allocator.free(embed_rel_path);
                return err;
            };
        }
    }

    try buffer.appendSlice(
        allocator,
        "const std = @import(\"std\");\n" ++
            "pub const scheme = \"embedded://\";\n" ++
            "pub const Asset = struct { path: []const u8, data: []const u8 };\n" ++
            "pub fn get(path: []const u8) ?[]const u8 {\n" ++
            "    return assets.get(path);\n" ++
            "}\n" ++
            "pub fn getUri(uri: []const u8) ?[]const u8 {\n" ++
            "    if (!std.mem.startsWith(u8, uri, scheme)) return null;\n" ++
            "    return get(uri[scheme.len..]);\n" ++
            "}\n" ++
            "pub fn list() []const Asset {\n" ++
            "    return assets_list[0..];\n" ++
            "}\n" ++
            "pub fn contains(path: []const u8) bool {\n" ++
            "    return assets.has(path);\n" ++
            "}\n" ++
            "pub fn uriAlloc(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {\n" ++
            "    return std.fmt.allocPrint(allocator, \"{s}{s}\", .{ scheme, path });\n" ++
            "}\n" ++
            "const assets = std.StaticStringMap([]const u8).initComptime(.{\n",
    );

    if (assets_root_opt) |_| {
        for (asset_paths, embed_paths.items) |relative_path, embed_rel_path| {
            try buffer.appendSlice(allocator, "    .{ ");
            try appendStringLiteral(&buffer, allocator, relative_path);
            try buffer.appendSlice(allocator, ", @embedFile(");
            try appendStringLiteral(&buffer, allocator, embed_rel_path);
            try buffer.appendSlice(allocator, ") },\n");
        }
    }

    try buffer.appendSlice(allocator, "});\n\nconst assets_list = [_]Asset{\n");
    if (assets_root_opt) |_| {
        for (asset_paths, embed_paths.items) |relative_path, embed_rel_path| {
            try buffer.appendSlice(allocator, "    .{ .path = ");
            try appendStringLiteral(&buffer, allocator, relative_path);
            try buffer.appendSlice(allocator, ", .data = @embedFile(");
            try appendStringLiteral(&buffer, allocator, embed_rel_path);
            try buffer.appendSlice(allocator, ") },\n");
        }
    }
    try buffer.appendSlice(allocator, "};\n");

    const content = try buffer.toOwnedSlice(allocator);
    return write_files.add(options.generated_file, content);
}

fn appendStringLiteral(buffer: *std.ArrayList(u8), allocator: std.mem.Allocator, value: []const u8) error{OutOfMemory}!void {
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
