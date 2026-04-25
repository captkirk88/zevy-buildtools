const std = @import("std");
const builtin = @import("builtin");

/// List all build dependencies recursively as a tree.
pub fn listBuildDependencies(b: *std.Build) void {
    var visited = std.StringHashMap(void).init(b.allocator);
    defer {
        var iter = visited.iterator();
        while (iter.next()) |entry| {
            // Free the key string
            b.allocator.free(entry.key_ptr.*);
        }
        visited.deinit();
    }

    const deps = getBuildDependencies(b) catch return;
    for (deps) |dep| {
        listBuildDependenciesRecursive(b, dep, 0, &visited) catch continue;
    }
}

/// Recursively list dependencies with tree formatting.
fn listBuildDependenciesRecursive(
    b: *std.Build,
    dep_name: []const u8,
    depth: usize,
    visited: *std.StringHashMap(void),
) !void {
    // Check if already visited to avoid cycles
    if (visited.contains(dep_name)) {
        printIndent(depth);
        std.debug.print("- {s} (circular)\n", .{dep_name});
        return;
    }

    try visited.put(dep_name, {});

    // Print current dependency with tree formatting
    if (depth == 0) {
        std.debug.print("{s}\n", .{dep_name});
    } else {
        printIndent(depth);
        std.debug.print("- {s}\n", .{dep_name});
    }

    // Get sub-dependencies only when not running under the test runner
    if (!builtin.is_test) {
        if (b.lazyDependency(dep_name, .{})) |dep| {
            const sub_deps = getBuildDependenciesFromDependency(dep) catch return;

            for (sub_deps) |sub_dep| {
                try listBuildDependenciesRecursive(b, sub_dep, depth + 1, visited);
            }
        }
    }
}

/// Print indentation for tree formatting.
fn printIndent(depth: usize) void {
    for (0..depth) |_| {
        std.debug.print("  ", .{});
    }
}

/// Get dependencies from a specific dependency.
fn getBuildDependenciesFromDependency(dep: *std.Build.Dependency) ![]const []const u8 {
    const allocator = dep.builder.allocator;
    const available = dep.builder.available_deps;
    var deps = try std.ArrayList([]const u8).initCapacity(allocator, available.len);

    for (dep.builder.available_deps) |depid| {
        try deps.append(allocator, depid.@"0");
    }

    return try deps.toOwnedSlice(allocator);
}

pub fn getBuildDependencies(b: *std.Build) error{OutOfMemory}![]const []const u8 {
    const allocator = b.allocator;
    const available = b.available_deps;
    var deps = try std.ArrayList([]const u8).initCapacity(allocator, available.len);

    for (b.available_deps) |depid| {
        try deps.append(allocator, depid.@"0");
    }

    return try deps.toOwnedSlice(allocator);
}

/// List all dependencies of a given dependency.
pub fn listDependencies(dependency: *std.Build.Dependency) void {
    const modules = getDependencyModules(dependency) catch return;
    for (modules) |module| {
        std.debug.print("\tModule: {s}\n", .{module.name});
        listModuleDependencies(module.module);
    }
    std.debug.print("\t{s}\n", .{dependency.builder.build_root.path orelse "."});
}

const DepModule = struct {
    name: []const u8,
    module: *std.Build.Module,
};
pub fn getDependencyModules(dependency: *std.Build.Dependency) error{OutOfMemory}![]DepModule {
    const allocator = dependency.builder.allocator;
    var modules = try std.ArrayList(DepModule).initCapacity(allocator, dependency.builder.modules.count());
    var iter = dependency.builder.modules.iterator();
    while (iter.next()) |entry| {
        try modules.append(allocator, .{
            .name = entry.key_ptr.*,
            .module = entry.value_ptr.*,
        });
    }
    return try modules.toOwnedSlice(allocator);
}

/// List all dependencies of a given module.
pub fn listModuleDependencies(module: *std.Build.Module) void {
    if (!builtin.is_test) {
        for (module.owner.available_deps) |dep| {
            std.debug.print("\t- {s}\n", .{dep.@"0"});
        }
    }
}

pub fn getFilesFromPath(allocator: std.mem.Allocator, b: *std.Build, path: std.Build.LazyPath) !std.ArrayList([]const u8) {
    const base_file_path = path.getPath(b);
    const io = b.graph.io;
    var dir = std.Io.Dir.openDirAbsolute(io, base_file_path, .{ .iterate = true }) catch return std.ArrayList([]const u8).initCapacity(allocator, 0);
    defer dir.close(io);

    var files = try std.ArrayList([]const u8).initCapacity(allocator, 16);

    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
        if (entry.kind == .file) {
            const full_path = try std.fs.path.join(allocator, &[_][]const u8{ base_file_path, entry.name });
            files.append(allocator, full_path) catch {
                allocator.free(full_path);
                files.deinit(allocator);
                return error.OutOfMemory;
            };
        }
    }
    return files;
}

/// Check if the build is running in this project
pub fn isSelf(b: *std.Build) bool {
    // Return true if this build's `build.zig` is inside the builder's build_root
    // If we can't find a build_root, fall back to true
    if (b.build_root.path) |root| {
        const my_build_zig = b.path("build.zig").getPath(b);
        return std.mem.startsWith(u8, my_build_zig, root);
    } else {
        return true;
    }
}
