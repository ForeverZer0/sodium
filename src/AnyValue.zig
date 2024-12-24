//! Interface type of values that can be parsed from a command-line option.

const Allocator = @import("std").mem.Allocator;
const ParseError = @import("errors.zig").ParseError;
const AnyValue = @This();

/// The fully qualified name of the underlying type, as returned by `@typeName`.
type_name: []const u8,
/// A pointer to the variable value with all type information stripped.
value_ptr: *anyopaque,
/// The function used to parse a string into a value.
parse_func: *const fn (str: []const u8, dest: *anyopaque) ParseError!void,
/// A function that returns the string representation of the value.
/// Callers are responsible for freeing the returned memory.
string_func: *const fn (allocator: Allocator, value: *const anyopaque) Allocator.Error![]u8,
/// Function that returns the name of an argument of this type in usage text.
/// A default implementation is used when `null`, but can be overridden via this field.
///
/// For example, given a flag called "output" and this function returning "string",
/// the following would be displayed in the help text for the user:
///
/// `-o, --output <string>  sets the output path`
argname_func: *const fn () []const u8,

/// Parses a value from a string and stores the result
/// in the underlying storage.
pub fn parse(self: AnyValue, str: []const u8) ParseError!void {
    return self.parse_func(str, self.value_ptr);
}

/// Returns a user-friendly name for the value type as used in an argument.
///
/// This can be used in help messages to indicate the expected type for a user to supply.
pub fn argName(self: AnyValue) []const u8 {
    return self.argname_func();
}

/// Returns the value represented as a string.
///
/// The caller is responsible for freeing the returned memory.
pub fn toString(self: AnyValue, allocator: Allocator) Allocator.Error![]u8 {
    return self.string_func(allocator, self.value_ptr);
}
