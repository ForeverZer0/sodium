# Sodium

Sodium is a feature-rich POSIX/GNU-style flag/option parser for Zig command-line applications. The design goal was to create a complete solution for flag parsing, including auto-generated usage, support for common conventions, while maintaining a stream-lined and intuitive configuration for its users, leveraging the power of Zig's type system.

## Features

* Handles all common style variants:
  * Long-form: `--flag`, `--flag value`, `--flag=value`
  * Short-form: `-f`, `-f value`, `-f=value`, `-fvalue`
  * Short-form (joined): `pacman -Syu` or `rsync -zvhP`
* Automatic formatted "usage" generation can be displayed with `--help`
* Uses Zig's strong type system and comptime features to map arguments for the following types automatically:
  * Strings (i.e. `[]const u8`)
  * Integers
  * Floats
  * Booleans
  * Enums (by field name and/or numeric value)
  * UTF-8 codepoints (`u21`)
  * Arrays/Vectors
* Fully extensible: implement your own custom types via an interface that requires only a basic parsing function to "just work"
* Handles interspersed arguments and flags by default, or choose to disable for stricter ordering
* Supports flags with an optional argument
* Default values for flags when not specified
* Displays descriptive error messages to users for incorrect/invalid input
* Extracts back-quoted variable names to display from arguments in the usage text
* Respects a naked `--` as a terminator for optional arguments

## Installation

Add an entry to your project's `build.zig.zon`...

```zig
.dependencies = .{
    .sodium = .{
        // Recommended to always use tags
        .url = "https://github.com/ForeverZer0/sodium/archive/refs/heads/master.tar.gz",
        // Zig will suggest the correct hash after a (failed) first run by leaving this initially blank
        .hash = "", 
    }
}
```

...define the module as a dependency in your project's `build.zig`...

```zig
const sodium = b.dependency("sodium", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("sodium", sodium.module("sodium"));
```

...and then `@import` and use normally throughout your project:

```zig
const sodium = @import("sodium");
const FlagSet = sodium.FlagSet;

const fn main() !void {
    ...
}
```
