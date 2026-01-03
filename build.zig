const std = @import("std");

const root = @import("src/root.zig");

pub const examples = root.examples;
pub const fetch = root.fetch;
pub const fmt = root.fmt;
pub const embed = root.embed;
pub const copy = root.copy;
pub const utils = root.utils;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    //const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("zevy_buildtools", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = .ReleaseSafe,
    });

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    // A top level step for running all tests. dependOn can be called multiple
    // times and since the two run steps do not depend on one another, this will
    // make the two of them run in parallel.
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);

    // Add a build step that runs `zig build run` in the example subproject.
    // This creates a Run step that spawns the `zig` process in the `example/`
    // directory, forwarding any extra args passed to `zig build example -- ...`.
    const run_example_step = b.step("example", "Run example subproject");

    // Create a Run step that executes `zig build run` in the example dir.
    const example_run = std.Build.Step.Run.create(b, "example: zig build run");
    // Use the `zig` on PATH.
    example_run.addArg("zig");
    example_run.addArg("build");
    example_run.addArg("run");
    // Run from the example subdirectory
    example_run.setCwd(b.path("example"));
    // Inherit stdio so the example can interact with the terminal
    example_run.stdio = .inherit;
    // Mark as having side-effects so it always runs
    example_run.has_side_effects = true;

    // Forward additional arguments after `--` if provided to `zig build example -- arg...`
    if (b.args) |args| {
        example_run.addArg("--");
        for (args) |arg| example_run.addArg(arg);
    }

    // Make the top-level `example` step depend on our run step
    run_example_step.dependOn(&example_run.step);

    // Add and register a top-level fetch step based on the zon file.
    fetch.addFetchStep(b, b.path("build.zig.zon")) catch |err| switch (err) {
        error.OutOfMemory => @panic("Out of memory while creating fetch step"),
        error.ZonNotFound => @panic("build.zig.zon not found for fetch step"),
        error.ZonFileReadError => @panic("Error reading build.zig.zon for fetch step"),
        error.ParseZon => @panic("Error parsing build.zig.zon for fetch step"),
    };

    root.fmt.addFmtStep(b, true) catch |err| {
        @panic(@errorName(err));
    };
}
