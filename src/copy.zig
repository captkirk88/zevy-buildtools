const std = @import("std");

/// Copy all files from a source folder to the build output directory.
pub fn copyFolder(b: *std.Build, src: []const u8) !void {
    const allocator = b.allocator;
    const io = b.graph.io;

    var src_dir = try std.Io.Dir.cwd().openDir(io, b.path(src).cwd_relative, .{ .access_sub_paths = true, .iterate = true });
    defer src_dir.close(io);
    std.log.info("Copying assets from {s} to {s}", .{ b.path(src).cwd_relative, b.exe_dir });
    try copyDirRecursive(io, src_dir, b.exe_dir, allocator);
}

fn copyDirRecursive(io: std.Io, dir: std.Io.Dir, dest_root: []const u8, allocator: std.mem.Allocator) !void {
    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
        if (entry.kind == .file) {
            const dest_path = try std.fs.path.join(allocator, &[_][]const u8{ dest_root, entry.name });
            defer allocator.free(dest_path);

            try std.Io.Dir.cwd().createDirPath(io, std.fs.path.dirname(dest_path) orelse ".");
            var src_file = try dir.openFile(io, entry.name, .{ .mode = .read_only });
            defer src_file.close(io);
            const dest_file = try std.Io.Dir.cwd().createFile(io, dest_path, .{ .truncate = true });
            defer dest_file.close(io);
            var buffer: [4096]u8 = undefined;
            while (true) {
                const bytes_read = try src_file.readStreaming(io, &.{buffer[0..]});
                if (bytes_read == 0) break;
                try dest_file.writeStreamingAll(io, buffer[0..bytes_read]);
            }
        }
        // Ignore directories
    }
}
