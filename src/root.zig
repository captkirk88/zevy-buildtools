const std = @import("std");

pub const examples = @import("examples.zig");

pub const fetch = @import("fetch.zig");

pub const embed = @import("embed.zig");

pub const copy = @import("copy.zig");

pub const fmt = @import("fmt.zig");

pub const utils = @import("utils.zig");

pub const deps = @import("deps.zig");

test {
    std.testing.refAllDeclsRecursive(@This());
}
