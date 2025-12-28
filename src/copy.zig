const std = @import("std");

/// Copy all files from a source folder to the build output directory.
pub fn copyFolder(b: *std.Build, src: []const u8) !void {
    const fs = std.fs;
    const allocator = b.allocator;

    var src_dir = try fs.cwd().openDir(b.path(src).cwd_relative, .{ .access_sub_paths = true, .iterate = true });
    defer src_dir.close();
    std.log.info("Copying assets from {s} to {s}", .{ b.path(src).cwd_relative, b.exe_dir });
    try copyDirRecursive(src_dir, b.exe_dir, allocator);
}

fn copyDirRecursive(dir: std.fs.Dir, dest_root: []const u8, allocator: std.mem.Allocator) !void {
    const fs = std.fs;

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        const src_path = try std.fs.path.join(allocator, &[_][]const u8{ dest_root, entry.name });
        defer allocator.free(src_path);

        if (entry.kind == .file) {
            const dest_path = try std.fs.path.join(allocator, &[_][]const u8{ dest_root, entry.name });
            defer allocator.free(dest_path);

            try fs.cwd().makePath(std.fs.path.dirname(dest_path) orelse ".");
            var src_file = try dir.openFile(entry.name, .{ .mode = .read_only });
            defer src_file.close();
            const dest_file = try fs.cwd().createFile(dest_path, .{ .truncate = true });
            defer dest_file.close();
            var buffer: [4096]u8 = undefined;
            while (true) {
                const bytes_read = try src_file.read(&buffer);
                if (bytes_read == 0) break;
                _ = try dest_file.write(buffer[0..bytes_read]);
            }
        }
        // Ignore directories
    }
}
