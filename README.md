# zevy-buildtools

A collection of build utilities for Zig projects, designed to streamline asset management, code formatting, and example execution.

## Features

- **Asset Fetching**: Update dependencies with `zig build fetch` using `@import("zig_buildtools").fetch.addFetchStep`.
- **Code Formatting**: Format your Zig source files using `zig build fmt` using `@import("zig_buildtools").addFmtStep`.
- **Example Runner**: Build and run example projects with `zig build examples` using `@import("zig_buildtools").setupExamples`.
- **Asset Embedding**: Embed assets directly into your Zig binaries for easy distribution using `@import("zig_buildtools").embed`.


---

## Usage

### 1. Fetch Dependencies
Calls `zig fetch` and updates external dependencies defined in your build configuration:

```sh
zig build fetch
```

> [!NOTE]
> zevy-buildtools enables you to use a `.ignore = true` on your dependency in build.zig.zon to tell fetch to ignore that dependency.  You may still use `zig fetch --save ...`.

### 2. Format Code
Format all Zig source files in your project:

```sh
zig build fmt
```

- Runs Zig's built-in formatter on your codebase.
- Ensures consistent style and formatting.

### 3. Build Examples
Compile and run example projects:

```sh
zig build examples
```

- Builds all example Zig files in the `examples/` directory.
- Useful for testing and showcasing features.

### 4. Embed Assets
Embed assets into your Zig binary for portability:

- Use the build tools to include files from `embedded_assets/` or other directories.
- Assets are accessible at runtime without external dependencies.

---

## Getting Started

1. Add `zevy-buildtools` to your Zig project `build.zig` file.
2. Import and configure in your `build.zig`:
   - See `example/build.zig` for usage patterns.
3. Run the desired build commands as shown above.


## Contributing

Contributions are welcome! Ideas, kinda, just don't be dumb.

---
