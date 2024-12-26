//! Describes a command-line flag.

const AnyValue = @import("AnyValue.zig");

/// Name of the flag.
name: []const u8,
/// Brief message text to be displayed in help messages.
usage: []const u8,
/// The value of the argument.
value: AnyValue,
/// Optional single-letter abbreviated flag.
shorthand: ?u8 = null,
/// Default value (as text), used for help/usage message.
default: ?[]const u8 = null,
/// Default value (as text), used for help/usage message if the flag is
/// present, but not provided a value. By default, all flags require a
/// value, with the exception of `bool` types, which default to `true`.
default_no_opt: ?[]const u8 = null,
/// If this flag is deprecated, this string provides a message with alternative or explanation.
deprecated: ?[]const u8 = null,
/// If the shorthand flag is deprecated, this string provides a message with alternative or explanation.
deprecated_shorthand: ?[]const u8 = null,
/// Alias names associated with the flag.
aliases: ?[]const []const u8 = null,
