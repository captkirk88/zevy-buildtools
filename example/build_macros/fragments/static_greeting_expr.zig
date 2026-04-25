const buildtools = @import("zevy_buildtools");

pub fn main(
    code: *buildtools.prebuild.CodeBuilder,
    _: buildtools.prebuild.MacroContext,
) !void {
    try code.stringLiteral("Hello from a file-backed macro!");
}
