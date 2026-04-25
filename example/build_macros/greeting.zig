const buildtools = @import("zevy_buildtools");

pub const definition: buildtools.prebuild.MacroDefinition = .{
    .name = "greeting",
    .expand = expand,
};

fn expand(
    code: *buildtools.prebuild.CodeBuilder,
    context: buildtools.prebuild.MacroContext,
) !void {
    const name = context.stringLiteralArg() orelse {
        try code.compileError("@greeting requires a string literal argument");
        return;
    };

    try code.stringLiteralFmt("Hello, {s}!", .{name});
}
