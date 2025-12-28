# zevy-buildtools

A collection of build utilities for Zig projects, designed to streamline asset management, code formatting, and example execution. Built for Zig 0.15.x.

## Features

- **Asset Fetching**: Update dependencies with `zig build fetch`.
- **Code Formatting**: Format your Zig source files using `zig build fmt`.
- **Example Runner**: Build and run example projects with `zig build examples`.
- **Asset Embedding**: Embed assets directly into your Zig binaries for easy distribution.

> [!NOTE]
> Use `zig build --help` to see all available commands and options provided by `zevy-buildtools`.

---

## Usage

### 1. Fetch Assets
Download and update external assets defined in your build configuration:

```sh
zig build fetch
```

- Downloads assets to the appropriate directory.
- Supports custom asset sources and versioning.

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

1. Add `zevy-buildtools` to your Zig project build file.
2. Import and configure in your `build.zig`:
   - See `example/build.zig` for usage patterns.
3. Run the desired build commands as shown above.

---
