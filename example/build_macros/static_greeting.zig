const buildtools = @import("zevy_buildtools");
const implementation = @import("fragments/static_greeting_expr.zig");

pub const definition = buildtools.prebuild.moduleDefinition("staticGreeting", implementation);
