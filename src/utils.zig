const std = @import("std");
const builtin = @import("builtin");

/// List all build dependencies.
pub fn listBuildDependencies(b: *std.Build) void {
    if (!builtin.is_test) {
        std.debug.print("Stored dependencies:\n", .{});
        for (b.available_deps) |depid| {
            std.debug.print("DEP: {s}\n", .{depid.@"0"});
            listDependencies(b.dependency(depid.@"0", .{}));
        }
    }
}

/// List all dependencies of a given dependency.
pub fn listDependencies(dependency: *std.Build.Dependency) void {
    if (!builtin.is_test) {
        std.debug.print("Dependencies: {s}\n", .{dependency.builder.build_root.path orelse "unknown"});
        var iter = dependency.builder.modules.iterator();
        while (iter.next()) |entry| {
            std.debug.print("- {s}\n", .{entry.key_ptr.*});
        }
    }
}

/// List all dependencies of a given module.
pub fn listModuleDependencies(module: *std.Build.Module) void {
    if (!builtin.is_test) {
        std.debug.print("Module dependencies for {s}:\n", .{module.getGraph().names[0]});
        for (module.owner.available_deps) |dep| {
            std.debug.print("  - {s}\n", .{dep.@"0"});
        }
    }
}

pub fn getFilesFromPath(allocator: std.mem.Allocator, b: *std.Build, path: std.Build.LazyPath) !std.ArrayList([]const u8) {
    const fs = std.fs;
    const base_file_path = path.getPath(b);
    var dir = fs.openDirAbsolute(base_file_path, .{ .iterate = true }) catch return std.ArrayList([]const u8).initCapacity(allocator, 0);
    defer dir.close();

    var files = try std.ArrayList([]const u8).initCapacity(allocator, 16);

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
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
