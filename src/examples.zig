const std = @import("std");
const utils = @import("utils.zig");

pub const Example = struct {
    name: []const u8,
    path: []const u8,
    module: *std.Build.Module,
};
/// Recursively setup and add all examples found in the `examples/` directory
///
/// Sets up the build step for each example found and one top-level step to run
/// them all called `examples`.
pub fn setupExamples(b: *std.Build, modules: []const std.Build.Module.Import, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) struct { step: *std.Build.Step, examples: []const Example } {
    if (utils.isSelf(b) == false) return &[_]Example{};

    var examples_step: ?*std.Build.Step = null;
    var iter = b.top_level_steps.iterator();
    while (iter.next()) |step| {
        if (std.mem.eql(u8, step.key_ptr.*, "examples")) {
            examples_step = &step.value_ptr.*.step;
            break;
        }
    }

    // Examples
    if (examples_step == null) examples_step = b.step("examples", "Run all examples");

    var examples_dir = std.fs.openDirAbsolute(b.path("examples").getPath(b), .{ .iterate = true }) catch return &[_]Example{};
    defer examples_dir.close();

    var modules_list = std.ArrayList(Example).initCapacity(b.allocator, 16) catch return &[_]Example{};
    var examples_iter = examples_dir.iterate();
    while (examples_iter.next() catch null) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".zig")) {
            var example_name = std.fs.path.stem(entry.name);

            iter = b.top_level_steps.iterator();
            while (iter.next()) |step| {
                if (std.mem.eql(u8, step.key_ptr.*, example_name)) {
                    // Example step already exists
                    example_name = std.fmt.allocPrint(b.allocator, "{s}_example", .{example_name}) catch break;
                    break;
                }
            }

            const example_path = std.fs.path.join(b.allocator, &.{ "examples", entry.name }) catch continue;

            const example_mod = b.createModule(.{
                .root_source_file = b.path(example_path),
                .target = target,
                .optimize = optimize,
            });

            // Add imports from the first module if any
            if (modules.len > 0) {
                for (modules) |module| {
                    example_mod.addImport(module.name, module.module);
                }
            }

            // Add each module
            for (modules) |item| {
                example_mod.addImport(item.name, item.module);
            }

            const example_exe = b.addExecutable(.{
                .name = example_name,
                .root_module = example_mod,
            });

            const run_example = b.addRunArtifact(example_exe);

            if (b.args) |args| {
                run_example.addArgs(args);
            }

            const example_step = b.step(example_name, b.fmt("Run the {s} example", .{example_name}));
            example_step.dependOn(&run_example.step);

            examples_step.?.dependOn(example_step);

            modules_list.append(b.allocator, .{
                .name = example_name,
                .path = example_path,
                .module = example_mod,
            }) catch continue;
        }
    }
    return .{
        .step = examples_step.?,
        .examples = modules_list.toOwnedSlice(b.allocator) catch &[_]Example{},
    };
}
