const std = @import("std");
const Build = std.Build;
const zon = std.zon;

pub const ParsedDependency = struct {
    url: []const u8,
};

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

fn urlWithoutFragment(url: []const u8) []const u8 {
    if (findSubstring(url, "#")) |p| {
        return url[0..p];
    } else {
        return url;
    }
}

fn parseZonFile(b: *Build, zon_path: Build.LazyPath) error{ OutOfMemory, ZonFileReadError, ParseZon }!std.ArrayList(ParsedDependency) {
    var deps = std.ArrayList(ParsedDependency).initCapacity(b.allocator, 8) catch return error.OutOfMemory;

    const zonPath = zon_path.getPath(b);
    var file = std.fs.cwd().openFile(zonPath, .{}) catch return error.ZonFileReadError;
    defer file.close();

    const data = file.readToEndAlloc(b.allocator, 64 * 1024) catch return error.ZonFileReadError;
    defer b.allocator.free(data);

    // Ensure null-terminated source for the parser
    var src_buf = try b.allocator.alloc(u8, data.len + 1);
    defer b.allocator.free(src_buf);
    var idx: usize = 0;
    while (idx < data.len) {
        src_buf[idx] = data[idx];
        idx += 1;
    }
    src_buf[data.len] = 0;
    const src: [:0]const u8 = @ptrCast(src_buf[0..data.len :0]);

    // Parse the whole file using std.zon.parse.fromSlice so we get diagnostics and ZOIR ownership
    var diag: std.zon.parse.Diagnostics = .{};
    const Root = struct {
        name: ?std.zig.Zoir.Node.Index = null,
        version: ?std.zig.Zoir.Node.Index = null,
        fingerprint: ?std.zig.Zoir.Node.Index = null,
        minimum_zig_version: ?std.zig.Zoir.Node.Index = null,
        dependencies: ?std.zig.Zoir.Node.Index = null,
        paths: ?std.zig.Zoir.Node.Index = null,
    };

    const root = std.zon.parse.fromSlice(Root, b.allocator, src, &diag, .{}) catch |err| {
        // print diagnostics into an allocating writer and emit via debug
        var aw: std.io.Writer.Allocating = .init(b.allocator);
        diag.format(&aw.writer) catch {};
        const out = aw.toOwnedSlice() catch |err2| {
            aw.deinit();
            diag.deinit(b.allocator);
            return err2;
        };
        std.debug.print("ZON parse failed: {s}\n", .{out});
        b.allocator.free(out);
        aw.deinit();
        diag.deinit(b.allocator);
        return err;
    };

    // Use diag.zoir and diag.ast to inspect the dependencies node
    if (root.dependencies) |deps_node| {
        switch (deps_node.get(diag.zoir)) {
            .struct_literal => |deps_fields| {
                var di: usize = 0;
                const DepEntry = struct {
                    url: ?[]const u8 = null,
                    path: ?[]const u8 = null,
                    hash: ?[]const u8 = null,
                    ignore: ?bool = null,
                };

                while (di < deps_fields.names.len) {
                    const val_node = deps_fields.vals.at(@intCast(di));
                    const entry = try std.zon.parse.fromZoirNode(DepEntry, b.allocator, diag.ast, diag.zoir, val_node, null, .{});

                    const ignored = if (entry.ignore) |v| v else false;
                    if (!ignored) {
                        if (entry.url) |u| {
                            const url_trim = urlWithoutFragment(u);
                            try deps.append(b.allocator, ParsedDependency{ .url = url_trim });
                        }
                    }

                    di += 1;
                }
            },
            else => {},
        }
    }

    // free diag (owns ast/zoir)
    diag.deinit(b.allocator);

    return deps;
}

/// Create a Run step that, when executed, will fetch URLs found in
/// `build.zig.zon`. This function *does not* register a top-level step; it
/// only creates and returns the Run step and its dependent fetch tasks. The
/// caller can decide to attach this Run to a top-level `fetch` step if desired.
pub fn createFetchStep(b: *Build, zon_path: Build.LazyPath) error{ OutOfMemory, ZonNotFound, ZonFileReadError, ParseZon }!*std.Build.Step {
    const container = b.allocator.create(std.Build.Step) catch @panic("OOM");
    container.* = std.Build.Step.init(.{
        .id = .custom,
        .name = "fetch: run fetches",
        .owner = b,
        .makeFn = makeFetchStep,
    });

    // Try to open the zon file. If it doesn't exist, return ZonNotFound.
    const zonPath = zon_path.getPath(b);
    var file = std.fs.cwd().openFile(zonPath, .{}) catch |err| switch (err) {
        error.FileNotFound => return error.ZonNotFound,
        else => return error.ZonFileReadError,
    };
    defer file.close();

    const data = file.readToEndAlloc(b.allocator, 16 * 1024) catch return error.ZonFileReadError;
    defer b.allocator.free(data);

    // Use the helper parser above to get parsed dependencies
    var deps = parseZonFile(b, zon_path) catch |err| return err;
    defer deps.deinit(b.allocator);

    var i: usize = 0;
    for (deps.items) |d| {
        const name = b.fmt("fetch: {s}", .{d.url});
        const run = std.Build.Step.Run.create(b, name);
        run.addArg("zig");
        run.addArg("fetch");
        run.addArg("--save");
        run.addArg(d.url);
        run.stdio = .inherit;
        run.has_side_effects = true;
        std.Build.Step.dependOn(container, &run.step);
        i += 1;
    }

    return container;
}

fn makeFetchStep(step: *std.Build.Step, options: std.Build.Step.MakeOptions) !void {
    // The dependencies are already set up, so just run them
    for (step.dependencies.items) |dep| {
        dep.make(options) catch |err| return err;
    }
}

/// Convenience wrapper that creates the fetch container step and registers a
/// top-level `fetch` step that depends on it.
pub fn addFetchStep(b: *Build, zon_path: Build.LazyPath) error{ OutOfMemory, ZonNotFound, ZonFileReadError, ParseZon }!void {
    const container = createFetchStep(b, zon_path) catch |err| return err;
    const top = b.step("fetch", "Fetch external dependencies");
    top.dependOn(container);
}

/// Create a Run step that fetches a specific URL using `zig fetch --save`.
/// The URL is parsed from the command line arguments (b.args) when the step runs.
/// If the URL contains "github.com" and does not end with ".tar.gz", it prefixes it with "git+".
pub fn createGetStep(b: *Build) *std.Build.Step {
    const step = b.allocator.create(std.Build.Step) catch @panic("OOM");
    step.* = std.Build.Step.init(.{
        .id = .custom,
        .name = "get",
        .makeFn = makeGetStep,
        .owner = b,
    });
    return step;
}

/// Permitted domains for fetching - only these domains are allowed.
const permitted_domains = [_][]const u8{
    "github.com", // tested
    "gitlab.com", //untested
    "bitbucket.org", // untested
    "codeberg.org", //untested
};

fn isPermittedDomain(url: []const u8) bool {
    for (permitted_domains) |domain| {
        if (std.mem.indexOf(u8, url, domain) != null) return true;
    }
    return false;
}

fn makeGetStep(step: *std.Build.Step, options: std.Build.Step.MakeOptions) !void {
    _ = options;
    const b = step.owner;
    const args = b.args orelse {
        std.debug.print("No URL provided. Use: zig build get -- <url>\n", .{});
        return error.NoUrl;
    };
    if (args.len == 0) {
        std.debug.print("No URL provided. Use: zig build get -- <url>\n", .{});
        return error.NoUrl;
    }
    const url = args[0];
    const modified_url = if (std.mem.endsWith(u8, url, ".tar.gz")) url else if (isPermittedDomain(url)) b.fmt("git+{s}", .{url}) else url;

    const argv = [_][]const u8{ "zig", "fetch", "--save", modified_url };

    var child = std.process.Child.init(&argv, b.allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    const result = try child.spawnAndWait();

    // Read and print stdout
    if (child.stdout) |stdout| {
        var stdout_data = try b.allocator.alloc(u8, 1024 * 1024);
        defer b.allocator.free(stdout_data);
        const n = try stdout.readAll(stdout_data);
        if (n > 0) {
            std.debug.print("{s}", .{stdout_data[0..n]});
        }
    }

    // Read and print stderr
    if (child.stderr) |stderr| {
        var stderr_data = try b.allocator.alloc(u8, 1024 * 1024);
        defer b.allocator.free(stderr_data);
        const n = try stderr.readAll(stderr_data);
        if (n > 0) {
            std.debug.print("{s}", .{stderr_data[0..n]});
        }
    }

    if (result != .Exited or result.Exited != 0) {
        std.debug.print("zig fetch failed\n", .{});
        return error.FetchFailed;
    }
}

/// Convenience wrapper that creates the get step and registers a
/// top-level `get` step that depends on it.
///
/// Requires args to be passed to the build system when invoking `zig build get -- <url>`.
pub fn addGetStep(b: *Build) void {
    const step = createGetStep(b);
    const top = b.step("get", "Fetch a specific dependency");
    top.dependOn(step);
}
