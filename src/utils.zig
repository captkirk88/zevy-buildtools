const std = @import("std");
const builtin = @import("builtin");

/// List all build dependencies.
pub fn listBuildDependencies(b: *std.Build) void {
    const deps = getBuildDependencies(b) catch return;
    for (deps) |dep| {
        std.debug.print("{s}\n", .{dep});
        const mod_deps = getDependencyModules(b.dependency(dep, .{})) catch continue;
        for (mod_deps) |module| {
            listModuleDependencies(module.module);
        }
    }
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
