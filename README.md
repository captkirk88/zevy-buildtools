# zevy-buildtools

A collection of build utilities for Zig projects, designed to streamline asset management, code formatting, and example execution.

## Features

- **Asset Fetching**: Update dependencies with `zig build fetch` using `@import("zig_buildtools").fetch.addFetchStep`.
   - Get new dependencies `zig build get` using `@import("zig_buildtools").fetch.addGetStep`.
   - List current dependencies with `zig build deps` using `@import("zig_buildtools").fetch.addDepsStep`.
- **Code Formatting**: Format your Zig source files using `zig build fmt` using `@import("zig_buildtools").addFmtStep`.
- **Example Runner**: Build and run example projects with `zig build examples` using `@import("zig_buildtools").setupExamples`.
- **Asset Embedding**: Embed assets directly into your Zig binaries for easy distribution using `@import("zig_buildtools").embed`.
- **Prebuild Macro Expansion**: Define custom `@macro(...)` tokens that are expanded in your `.zig` source files at build time using `@import("zig_buildtools").prebuild`.


---

## Usage

### Fetch Dependencies

Calls `zig fetch` and updates external dependencies defined in your build configuration:

```
zig build fetch
```

> [!NOTE]
> zevy-buildtools enables you to use a `.ignore = true` on your dependency in build.zig.zon to tell fetch to ignore that dependency.  You may still use `zig fetch --save ...`.

### Get New Dependencies

Fetch and add new dependencies without updating existing ones:

```
zig build get -- <dependency-url>
```
Internally invokes `zig build --save <dependency-url>`.

You do not need to add `git+` prefix when specifying Github/Codeberg repositories; it is added automatically.

#### List Dependencies
List all current dependencies in your project:

```
zig build deps
```

### Format Code
Format all Zig source files in your project:

```
zig build fmt
```

- Runs Zig's built-in formatter on your codebase.
- Ensures consistent style and formatting.

### Build Examples
Compile and run example projects:

```
zig build examples
```

- Builds all example Zig files in the `examples/` directory.
- Useful for testing and showcasing features.

### Embed Assets
Embed assets into your Zig binary for portability:

- Use the build tools to include files from `embedded_assets/` or other directories.
- Assets are accessible at runtime without external dependencies.

---

### Prebuild Macro Expansion

Define custom `@macro(...)` tokens that are replaced with generated Zig code before compilation.

All `.zig` files under a designated source directory are scanned.  Any call that matches a registered macro name is replaced by the string your expansion function returns.  Files with no matching calls are copied verbatim — their bytes are never read into memory.

**Tokens inside line comments (`//`), string literals, character literals, and multiline strings (`\\`) are intentionally not expanded.**

#### 1. Write an expansion function in `build.zig`

```zig
fn expandGreeting(allocator: std.mem.Allocator, args: []const u8) anyerror![]u8 {
    // `args` is the raw text between the parens, e.g. `"World"`
    const trimmed = std.mem.trim(u8, args, " \t\"");
    return std.fmt.allocPrint(allocator, "\"Hello, {s}!\"", .{trimmed});
}
```

#### 2. Register the macro and wire up the module

```zig
const pre = try buildtools.prebuild.addPrebuildStep(b, .{
    .src_dir = "src",
    .macros = &.{
        .{ .name = "greeting", .expand = expandGreeting },
    },
});

const mod = b.addModule("mylib", .{
    .root_source_file = pre.file(b, "root.zig"), // use expanded source
    .target = target,
});
```

`pre.file(b, "relative/path.zig")` returns a `LazyPath` into the generated directory.
`pre.directory()` gives the whole generated tree (useful for modules with many files).

#### 3. Use the macro in your source

```zig
// src/greeter.zig
pub fn greet() []const u8 {
    return @greeting("World"); // → "Hello, World!" after prebuild
}
```

The build graph shows the expansion step explicitly:

```
WriteFile greeter.zig success
```

#### MacroDefinition interface

```zig
pub const MacroFn = *const fn (allocator: std.mem.Allocator, args: []const u8) anyerror![]u8;

pub const MacroDefinition = struct {
    name: []const u8,   // macro name without the leading @
    expand: MacroFn,    // returns the replacement Zig source
};
```

`expandMacros` is also exported as a public function for use in your own unit tests:

```zig
const result = try buildtools.prebuild.expandMacros(allocator, source, &macros);
defer allocator.free(result);
```

---

## Getting Started

1. Add `zevy-buildtools` to your Zig project `build.zig` file.
2. Import and configure in your `build.zig`:
   - See `example/build.zig` for usage patterns.
3. Run the desired build commands as shown above.


## Contributing

Contributions, suggestions, and ideas are welcome!

---
