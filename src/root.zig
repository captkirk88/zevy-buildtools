const std = @import("std");
const examples_mod = @import("examples.zig");

pub const examples = struct {
    pub const isSelf = examples_mod.isSelf;
    pub const setupExamples = examples_mod.setupExamples;
};

pub const fetch = @import("fetch.zig");

pub const embed = @import("embed.zig");

pub const copy = @import("copy.zig");

pub const fmt = @import("fmt.zig");

pub const utils = @import("utils.zig");

test {
    std.testing.refAllDeclsRecursive(@This());
}
