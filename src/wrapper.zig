const std = @import("std");

const string = @import("string.zig");
const ParseError = string.ParseError;
const Value = @import("value.zig").Value;

/// Returns a wrapper type for a string type.
pub const String = Value([]const u8, string.parseString);

/// Returns a wrapper for a boolean type.
pub const Bool = Value(bool, string.parseBool);

/// Returns a wrapper for an integer type.
/// Includes `u21` for UTF-8 codepoints.
pub fn Int(comptime T: type) type {
    comptime if (@typeInfo(T) != .Int)
        @compileError("expected T to be an integer type, found " ++ @typeName(T));

    const Closure = struct {
        fn parse(str: []const u8, dest: *T) ParseError!void {
            return string.parseInt(T, str, dest);
        }
    };
    return Value(T, Closure.parse);
}

/// Returns a wrapper for a floating-point number type.
pub fn Float(comptime T: type) type {
    if (@typeInfo(T) != .Float) @compileError("expected T to be a floating-point type, found " ++ @typeName(T));

    const Closure = struct {
        fn parse(str: []const u8, dest: *T) ParseError!void {
            return string.parseFloat(T, str, dest);
        }
    };
    return Value(T, Closure.parse);
}

/// Returns a wrapper for an enumeration type.
pub fn Enum(comptime T: type) type {
    comptime if (@typeInfo(T) != .Enum) @compileError("expected T to be an enum type, found " ++ @typeName(T));

    const Closure = struct {
        fn parse(str: []const u8, dest: *T) ParseError!void {
            return string.parseEnum(T, str, dest);
        }
    };
    return Value(T, Closure.parse);
}

/// Returns a wrapper for a fixed-length array type.
pub fn Array(comptime T: type) type {
    comptime if (@typeInfo(T) != .Array) @compileError("expected T to be an array type, found " ++ @typeName(T));

    const Closure = struct {
        fn parse(str: []const u8, dest: *T) ParseError!void {
            return string.parseArray(T, str, dest);
        }
    };
    return Value(T, Closure.parse);
}

/// Returns a wrapper for a fixed-length array type.
pub fn Vector(comptime T: type) type {
    comptime if (@typeInfo(T) != .Vector) @compileError("expected T to be a vector type, found " ++ @typeName(T));

    const Closure = struct {
        fn parse(str: []const u8, dest: *T) ParseError!void {
            return string.parseVector(T, str, dest);
        }
    };
    return Value(T, Closure.parse);
}
