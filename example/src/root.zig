//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

pub const greeter = @import("greeter.zig");

pub fn bufferedPrint() !void {
    // Stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    var threaded = std.Io.Threaded.init_single_threaded;
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file = std.Io.File.stdout();
    var stdout_writer = stdout_file.writer(threaded.io(), &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print("Hello, World!\n", .{});

    try stdout.flush(); // Don't forget to flush!
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}
