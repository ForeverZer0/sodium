# Sodium - Command-Line Flag Parser for Zig

Sodium is a feature-rich command-line flag/option parser for Zig applications, modeled after the top-tier [pflags](https://github.com/spf13/pflag) library for Go. The design goal was to create a complete solution for flag parsing, including auto-generated usage, support for common conventions, while maintaining a stream-lined and intuitive configuration for its users, leveraging the power of Zig's type system.

## Features

* Handles most common conventions for flag variants:
  * Long-form: `--flag`, `--flag argument`, `--flag=argument`
  * Short-form: `-f`, `-f argument`, `-f=argument`, `-fargument`
  * Short-form (joined): `pacman -Syu`
* Automatic formatted "usage" generation can be displayed with `--help`
* Uses Zig's type system and comptime features to map arguments for the following types automatically:
  * Strings (i.e. `[]const u8`)
  * Integers
  * Floats
  * Booleans
  * Enums (by field name and/or numeric value)
  * UTF-8 codepoints (`u21`)
  * Arrays/Vectors
* Full extensible: implement your own custom types via an interface that requires only a single string parsing function to "just work"
* Handles interspersed arguments and flags, or choose to disable
* Supports flags with optional/default arguments
* By default, displays helpful error messages to users for incorrect/invalid input
* Extracts back-quoted variable names to display from arguments in the usage text
