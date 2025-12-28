const std = @import("std");
const Build = std.Build;
const zon = std.zon;

fn findSubstring(hay: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0) {
        return 0;
    }
    var i: usize = 0;
    while (i + needle.len <= hay.len) {
        if (std.mem.eql(u8, hay[i .. i + needle.len], needle)) return i;
        i += 1;
    }

    return null;
}

/// Create a Run step that, when executed, will fetch URLs found in
/// `build.zig.zon`. This function *does not* register a top-level step; it
/// only creates and returns the Run step and its dependent fetch tasks. The
/// caller can decide to attach this Run to a top-level `fetch` step if desired.
pub fn createFetchStep(b: *Build, zon_path: Build.LazyPath) error{ OutOfMemory, ZonNotFound, ReadError, ParseZon }!*std.Build.Step {
    // Create a *container* Step (top-level style) that does not run a process
    // itself but depends on per-URL Run steps. This avoids creating a Run step
    // with no argv which would panic the runner.
    const container = b.allocator.create(std.Build.Step) catch return error.OutOfMemory;
    container.* = std.Build.Step.init(.{
        .id = .top_level,
        .name = "fetch: run fetches",
        .owner = b,
    });

    // Try to open the zon file. If it doesn't exist, return ZonNotFound.
    const zonPath = zon_path.getPath(b);
    var file = std.fs.cwd().openFile(zonPath, .{}) catch |err| switch (err) {
        error.FileNotFound => return error.ZonNotFound,
        else => return error.ReadError,
    };
    defer file.close();

    const data = file.readToEndAlloc(b.allocator, 16 * 1024) catch return error.ReadError;
    defer b.allocator.free(data);

    var remaining = data[0..];
    var urls = std.ArrayList([]const u8).initCapacity(b.allocator, 8) catch return error.OutOfMemory;
    defer urls.deinit(b.allocator);

    while (true) {
        const pos = findSubstring(remaining, "url") orelse break;
        remaining = remaining[pos + 3 ..]; // move past "url"

        // find '='
        var eq_idx: usize = 0;
        while (eq_idx < remaining.len and (remaining[eq_idx] != '=')) eq_idx += 1;
        if (eq_idx >= remaining.len) break;
        remaining = remaining[eq_idx + 1 ..];

        // skip whitespace
        var s: usize = 0;
        while (s < remaining.len and (remaining[s] == ' ' or remaining[s] == '\t' or remaining[s] == '\n' or remaining[s] == '\r')) s += 1;
        if (s >= remaining.len) break;
        remaining = remaining[s..];

        // Expect a quoted string (" or ') - use numeric codes to avoid escaping issues
        const quote = remaining[0];
        if (quote != 34 and quote != 39) continue;
        var m: usize = 1;
        while (m < remaining.len) {
            if (remaining[m] == quote) break;
            // simple escape handling
            if (remaining[m] == '\\') m += 1; // skip escaped char
            m += 1;
        }
        if (m >= remaining.len) break;

        const url_slice = remaining[1..m];
        // strip fragment after '#'
        var hash_pos: ?usize = null;
        var idx: usize = 0;
        while (idx < url_slice.len) {
            if (url_slice[idx] == '#') {
                hash_pos = idx;
                break;
            }
            idx += 1;
        }
        const url_trim = if (hash_pos) |p| url_slice[0..p] else url_slice;

        // store slice (the actual bytes are owned by `data`); use append with allocator
        urls.append(b.allocator, url_trim) catch continue;

        remaining = remaining[m + 1 ..];
    }

    // Create a Run step per url that runs `zig fetch --save <url>` and make the
    // container depend on them. The container is NOT registered as a top-level
    // step by this function; the caller can attach it to the build as they like.
    var i: usize = 0;
    while (i < urls.items.len) {
        const url = urls.items[i];
        const name = b.fmt("fetch: {s}", .{url});
        const run = std.Build.Step.Run.create(b, name);
        run.addArg("zig");
        run.addArg("fetch");
        run.addArg("--save");
        run.addArg(url);
        run.stdio = .inherit;
        run.has_side_effects = true;
        std.Build.Step.dependOn(container, &run.step);
        i += 1;
    }

    return container;
}

/// Convenience wrapper that creates the fetch container step and registers a
/// top-level `fetch` step that depends on it.
pub fn addFetchStep(b: *Build, zon_path: Build.LazyPath) error{ OutOfMemory, ZonNotFound, ReadError, ParseZon }!void {
    const container = createFetchStep(b, zon_path) catch |err| return err;
    const top = b.step("fetch", "Fetch external dependencies");
    top.dependOn(container);
}
