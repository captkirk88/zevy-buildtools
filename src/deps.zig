const std = @import("std");
const utils = @import("utils.zig");
/// List all build dependencies.
pub fn createDepsStep(b: *std.Build) !*std.Build.Step {
    const make = struct {
        pub fn make(s: *std.Build.Step, opts: std.Build.Step.MakeOptions) !void {
            _ = opts;
            utils.listBuildDependencies(s.owner);
        }
    }.make;

    const step = try b.allocator.create(std.Build.Step);
    step.* = std.Build.Step.init(.{
        .id = .custom,
        .name = "deps",
        .makeFn = make,
        .owner = b,
    });
    return step;
}

pub fn addDepsStep(b: *std.Build) !void {
    const deps_step = try createDepsStep(b);
    const step = b.step("deps", "List build dependencies");
    step.dependOn(deps_step);
}
