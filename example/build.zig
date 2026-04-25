const std = @import("std");
const buildtools = @import("zevy_buildtools");
const macros = @import("build_macros/root.zig");

// Although this function looks imperative, it does not perform the build
// directly and instead it mutates the build graph (`b`) that will be then
// executed by an external runner. The functions in `std.Build` implement a DSL
// for defining build steps and express dependencies between them, allowing the
// build runner to parallelize the build automatically (and the cache system to
// know when a step doesn't need to be re-run).  Another words `build` is more
// of a "build script" than a function that performs the build itself.

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ── Prebuild step ────────────────────────────────────────────────────────
    // Mix built-in macros from buildtools.prebuild.builtins with any
    // project-specific ones defined right here in build.zig.
    const pre = try buildtools.prebuild.addPrebuildStep(b, .{
        .src_dir = "src",
        .macros = &.{
            // Built-in: @buildTimestamp() → ISO-8601 UTC string literal
            buildtools.prebuild.builtins.build_timestamp,
            // Built-in: @envVar(NAME) → env var as string literal / @compileError
            buildtools.prebuild.builtins.env_var,
            // Built-in (parameterised): @buildMode() → optimize tag string
            buildtools.prebuild.builtins.buildModeExpander(optimize),
            // Project-specific macro imported from its own Zig module.
            macros.greeting.definition,
            // Project-specific macro backed by a raw Zig fragment file.
            macros.static_greeting.definition,
        },
    });

    // Use the expanded root.zig produced by the prebuild step.
    const mod = b.addModule("example", .{
        .root_source_file = pre.file(b, "root.zig"),
        .target = target,
    });

    const exe = b.addExecutable(.{
        .name = "example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "example", .module = mod },
            },
        }),
    });

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    // Adds `zig build fetch`
    try buildtools.fetch.addFetchStep(b, b.path("build.zig.zon"));
    // Adds `zig build get`
    buildtools.fetch.addGetStep(b);
    // Adds `zig build fmt`
    try buildtools.fmt.addFmtStep(b, true);

    // Adds `zig build examples`
    //try buildtools.examples.setupExamples(b, ...);

    // Adds `zig build deps`
    try buildtools.deps.addDepsStep(b);

    _ = try buildtools.examples.setupExample(b, "testA", "examples/testA.zig", &.{
        .{ .name = "self", .module = mod },
    }, target, .ReleaseFast);

    _ = try buildtools.embed.addEmbeddedAssetsModule(b, target, optimize, exe.root_module, .{
        .assets_dir = "embeds/",
    });
}
