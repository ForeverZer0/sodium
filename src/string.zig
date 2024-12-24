//! Contains functions for parsing and interacting with strings.

const std = @import("std");
const Allocator = std.mem.Allocator;
const AnyWriter = std.io.AnyWriter;

const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;

/// Error set for string-parsing related errors.
pub const ParseError = error{
    /// An empty string was given.
    EmptyString,
    /// The number of given items is less than the size of an array/vector.
    NotEnoughItems,
    /// The number of items exceeds the size of an array/vector.
    TooManyItems,
    /// The result cannot fit in the type specified.
    Overflow,
    /// The input was empty or contained an invalid character, or decoding a UTF-8 codepoint failed.
    InvalidCharacter,
    /// A field name was not found in an enum.
    InvalidEnumName,
    /// A numeric value does not match a named field value in an enum,
    /// and the enum is not marked non-exhaustive.
    InvalidEnumTag,
};

/// Provides options for wrapping lines.
pub const WrapOpts = struct {
    /// The maximum width (in columns) of each line.
    width: usize = 80,
    /// The number of spaces to apply in indentation.
    /// Each newline will be prefixed by this amount.
    indent: usize = 4,
    /// Number of ASCII characters that can exceed `width`.
    /// This tolerance is used to prevent a short word being orphaned on the final line.
    slop: usize = 5,
};

const LineSplit = struct {
    line: []const u8,
    remainder: []const u8,

    pub fn all(str: []const u8) LineSplit {
        return .{ .line = str, .remainder = &.{} };
    }
};

/// Splits a string on whitespace into an initial sub-string, up to `max` characters in length.
/// Will go `slop` over `max` if that encompasses the entire string.
/// This avoids short words orphaned on the final line.
fn wrapLine(max: usize, slop: usize, str: []const u8) LineSplit {
    if (max + slop > str.len) return LineSplit.all(str);

    if (std.mem.lastIndexOfAny(u8, str[0..max], &.{ ' ', '\t', '\n' })) |width| {
        if (std.mem.lastIndexOfScalar(u8, str[0..max], '\n')) |newline| {
            if (newline < width) return .{
                .line = str[0..newline],
                .remainder = str[newline + 1 ..],
            };
        }
        return .{
            .line = str[0..width],
            .remainder = str[width + 1 ..],
        };
    }
    return LineSplit.all(str);
}

/// Inserts the specified number of spaces after newlines in a string.
///
/// Caller is responsible for freeing the returned memory.
pub fn insertIndentation(allocator: Allocator, str: []const u8, size: usize) Allocator.Error![]u8 {
    // Early out for zero values.
    if (size == 0 or str.len == 0) return allocator.dupe(u8, str);

    // Create a buffer to write with
    var buffer = try std.ArrayList(u8).initCapacity(allocator, str.len);
    defer buffer.deinit();
    var writer = buffer.writer();

    // Loop until end input string has been reached
    var i: usize = 0;
    while (i < str.len) {
        if (std.mem.indexOfScalar(u8, str[i..], '\n')) |offset| {
            // A newline was found, write from current position to after that offset
            try writer.writeAll(str[i .. i + offset + 1]);
            // Write out the specified number of spaces for the indent
            try writer.writeByteNTimes(' ', size);
            i += offset + 1;
            continue;
        }
        // No newline found, copy until end of string and break loop
        try writer.writeAll(str[i..]);
        break;
    }

    return buffer.toOwnedSlice();
}

/// Inserts the specified number of spaces after newlines in a string.
pub fn insertIndentationTo(writer: AnyWriter, str: []const u8, size: usize) !void {
    // Early out for zero values.
    if (size == 0 or str.len == 0) return;

    // Loop until end input string has been reached
    var i: usize = 0;
    while (i < str.len) {
        if (std.mem.indexOfScalar(u8, str[i..], '\n')) |offset| {
            // A newline was found, write from current position to after that offset
            try writer.writeAll(str[i .. i + offset + 1]);
            // Write out the specified number of spaces for the indent
            try writer.writeByteNTimes(' ', size);
            i += offset + 1;
            continue;
        }
        // No newline found, copy until end of string and break loop
        try writer.writeAll(str[i..]);
        break;
    }
}

test "insertIndentation" {
    const str1 = try insertIndentation(std.testing.allocator, "HELLO\nWORLD", 2);
    defer std.testing.allocator.free(str1);
    try std.testing.expectEqualStrings("HELLO\n  WORLD", str1);

    const str2 = try insertIndentation(std.testing.allocator, "\nHELLO\nWORLD\n\nGOODBYE\n", 3);
    defer std.testing.allocator.free(str2);
    try std.testing.expectEqualStrings("\n   HELLO\n   WORLD\n   \n   GOODBYE\n   ", str2);
}

/// Wraps a string to a maximum width with leading indentation.
/// The first line is not indented, as this assumed to be done by the caller.
pub fn wrapLinesTo(writer: AnyWriter, str: []const u8, opts: WrapOpts) !void {
    // Invalid options.
    if (opts.width <= opts.indent) return writer.writeAll(str);

    // When width is 0, only apply indentation.
    if (opts.width == 0) return insertIndentationTo(writer, str, opts.indent);

    var indent = opts.indent;
    var wrap = opts.width - indent;

    // Not enough space for sensible wrapping.
    // Wrap as a block on next line instead.
    if (wrap < 24) {
        indent = 16;
        wrap = opts.width - indent;
        try writer.writeByte('\n');
        try writer.writeByteNTimes(' ', indent);
    }
    // If still not enough space, then it is time to abort.
    if (wrap < 24) return insertIndentationTo(writer, str, indent);

    // To avoid short words orphaned on the final line, use a bit of
    // tolerance that can exceed the max to fit it.
    wrap = wrap - opts.slop;

    // Handle the first line, which is indented by the caller (or special case above)
    var split = wrapLine(wrap, opts.slop, str);
    try writer.writeAll(split.line);

    // Wrap the remaining lines.
    while (split.remainder.len > 0) {
        try writer.writeByte('\n');
        try writer.writeByteNTimes(' ', indent);

        split = wrapLine(wrap, opts.slop, split.remainder);
        try writer.writeAll(split.line);
    }
}

/// Wraps a string to a maximum width with leading indentation.
/// The first line is not indented, as this assumed to be done by the caller.
///
/// Caller is responsible for freeing the returned memory.
pub fn wrapLines(allocator: Allocator, str: []const u8, opts: WrapOpts) Allocator.Error![]u8 {
    // Calculate the difference between the end of the line and the indentation.
    var buffer = try std.ArrayList(u8).initCapacity(allocator, str.len);
    defer buffer.deinit();
    const writer = buffer.writer();

    // OutOfMemory is the only actual error that can be generated here, but
    // the use of AnyWriter prevents the use of a concrete error set.
    wrapLinesTo(writer.any(), str, opts) catch return error.OutOfMemory;
    return buffer.toOwnedSlice();
}

test "wrapLines" {
    const lorem = "Lorem ipsum dolor sit amet. Et autem modi qui repudiandae earum vel nostrum deleniti ut voluptatum enim. Ab voluptatem itaque non quasi similique ea molestias officiis. Ea dolorem illum qui architecto officia qui cupiditate ipsa. Rem excepturi molestiae est galisum dolor qui omnis nobis et quidem suscipit sed rerum earum.";

    const opts = WrapOpts{ .indent = 4, .width = 80 };
    const wrapped = try wrapLines(std.testing.allocator, lorem, opts);
    defer std.testing.allocator.free(wrapped);

    var line_no: usize = 0;
    var iter = std.mem.splitScalar(u8, wrapped, '\n');
    while (iter.next()) |line| : (line_no += 1) {
        switch (line_no) {
            // Non-indented first line
            0 => try std.testing.expectEqualStrings("Lorem ipsum", line[0..11]),
            // All subsequent strings with indent
            else => try std.testing.expectEqualStrings("    ", line[0..4]),
        }
        try std.testing.expect(line.len <= opts.width + opts.slop);
    }
    try std.testing.expectEqual(5, line_no);
}

/// Tests if a string is empty or only contains ASCII whitespace characters.
pub fn isEmptyOrWhitespace(str: []const u8) bool {
    if (str.len == 0) return true;
    for (str) |c| switch (c) {
        ' ', '\n', '\t', '\r', 0x0B, 0x0C => continue,
        else => return false,
    };
    return true;
}

test "isEmptyOrWhitespace" {
    try expectEqual(true, isEmptyOrWhitespace(""));
    try expectEqual(true, isEmptyOrWhitespace("   "));
    try expectEqual(true, isEmptyOrWhitespace("  \r\n"));
    try expectEqual(true, isEmptyOrWhitespace("\t  \n"));
    try expectEqual(true, isEmptyOrWhitespace("\t"));
    try expectEqual(false, isEmptyOrWhitespace("\t    w"));
}

/// Parse an integer in string format.
///
/// Values may be signed or unsigned and in the following form:
///     * Decimal: "1234", "-5678"
///     * Hexadecimal: "0x1FFF", "-Ox23"
///     * Octal: "0o45"
///     * Binary: "0b1101"
///
/// In addition, there is special handling for the `u21` type,
/// which will be decoded as a single UTF-8 codepoint.
pub fn parseInt(comptime T: type, str: []const u8, dest: *T) ParseError!void {
    const info = comptime @typeInfo(T).Int;
    if (str.len == 0) return error.EmptyString;

    dest.* = try switch (info.signedness) {
        .signed => std.fmt.parseInt(T, str, 0),
        else => switch (info.bits) {
            21 => std.unicode.utf8Decode(str) catch error.InvalidCharacter,
            else => std.fmt.parseUnsigned(T, str, 0),
        },
    };
}

test "parseInt" {
    var unsigned: u32 = undefined;
    var signed: i32 = undefined;
    var codepoint: u21 = undefined;

    // unsigned decimal
    try parseInt(u32, "123", &unsigned);
    try expectEqual(123, unsigned);
    // unsigned hexadecimal
    try parseInt(u32, "0xFFFF", &unsigned);
    try expectEqual(0xFFFF, unsigned);
    // unsigned octal
    try parseInt(u32, "0o45", &unsigned);
    try expectEqual(0o45, unsigned);
    // unsigned binary
    try parseInt(u32, "0b1101", &unsigned);
    try expectEqual(0b1101, unsigned);

    // signed decimal
    try parseInt(i32, "-322", &signed);
    try expectEqual(-322, signed);
    // signed hexadecimal
    try parseInt(i32, "+0x1FFF", &signed);
    try expectEqual(0x1FFF, signed);
    // signed octal
    try parseInt(i32, "-0o76", &signed);
    try expectEqual(-0o76, signed);
    // signed binary
    try parseInt(i32, "-0b1", &signed);
    try expectEqual(-0b1, signed);

    // UTF-8 codepoint
    try parseInt(u21, "A", &codepoint);
    try expectEqual(65, codepoint);
    try parseInt(u21, "¶", &codepoint);
    try expectEqual(0xB6, codepoint);

    // errors
    try expectError(error.InvalidCharacter, parseInt(i32, "1.2", &signed));
    try expectError(error.Overflow, parseInt(i32, "4294967295", &signed));
    try expectError(error.EmptyString, parseInt(i32, "", &signed));
}

/// Parse a floating-point value from a string.
///
/// Supports the following formats:
///     * decimal "12.34"
///     * scientific "1234e-2"
///     * special: "inf", "nan", "-inf"
pub fn parseFloat(comptime T: type, str: []const u8, dest: *T) ParseError!void {
    if (str.len == 0) return error.EmptyString;
    dest.* = try std.fmt.parseFloat(T, str);
}

test "parseFloat" {
    var value: f32 = undefined;

    // decimal notation
    try parseFloat(f32, "123.45", &value);
    try expectEqual(123.45, value);
    // scientific notation
    try parseFloat(f32, "123e-4", &value);
    try expectEqual(123e-4, value);
    // integral
    try parseFloat(f32, "123", &value);
    try expectEqual(123, value);

    // infinity
    try parseFloat(f32, "inf", &value);
    try expectEqual(std.math.inf(f32), value);
    try parseFloat(f32, "-iNf", &value);
    try expectEqual(-std.math.inf(f32), value);
    // not-a-number
    try parseFloat(f32, "nan", &value);
    try expectEqual(@as(u32, @bitCast(std.math.nan(f32))), @as(u32, @bitCast(value)));

    // error
    try expectError(error.EmptyString, parseFloat(f32, "", &value));
}

/// Parse an enum value in string format.
///
/// Values may be strings, in which case the name must be the name of a field,
/// otherwise an integer value will attempt to be parsed.
///
/// In the case of integer values, it must be equal to the value of an enum field,
/// with the exception of non-exhaustive enums, in which case it is valid so long
/// as it can be parsed into the enumeration's tag type.
pub fn parseEnum(comptime T: type, str: []const u8, dest: *T) ParseError!void {
    const info = comptime @typeInfo(T).Enum;

    if (str.len == 0) return error.EmptyString;
    // If the first character is a digit, skip the check for field names
    if (str.len > 0 and !std.ascii.isDigit(str[0])) {
        // Unroll fields at comptime into "if" branches for each name.
        inline for (info.fields) |field| {
            if (std.mem.eql(u8, field.name, str)) {
                dest.* = @as(T, @enumFromInt(field.value));
                return;
            }
        }
        return error.InvalidEnumName;
    }

    // No names matched, so assume value is numeric and attempt to parse
    const tag_int = try switch (@typeInfo(info.tag_type).Int.signedness) {
        .signed => std.fmt.parseInt(info.tag_type, str, 0),
        else => std.fmt.parseUnsigned(info.tag_type, str, 0),
    };

    // Attempt to convert numeric value into enum type
    dest.* = try std.meta.intToEnum(T, tag_int);
}

test "parseEnum" {
    // exhaustive
    const Shape = enum { triangle, square, circle };
    var shape: Shape = undefined;
    try parseEnum(Shape, "circle", &shape);
    try expectEqual(Shape.circle, shape);
    try parseEnum(Shape, "1", &shape);
    try expectEqual(Shape.square, shape);

    // non-exhaustive
    const Number = enum(u8) { zero, one, two, _ };
    var number: Number = undefined;
    try parseEnum(Number, "10", &number);
    try expectEqual(@as(Number, @enumFromInt(10)), number);

    // errors
    try expectError(error.InvalidEnumTag, parseEnum(Shape, "3", &shape));
    try expectError(error.InvalidEnumName, parseEnum(Shape, "hexagon", &shape));
    try expectError(error.EmptyString, parseEnum(Shape, "", &shape));
}

/// Parse a boolean value from a string.
///
/// `true` values: "1", "t", "T", "y", "Y", "yes", "YES", "true", "TRUE"
/// `false` values: "0", "f", "F", "n", "N", "no", "NO", "false", "FALSE"
pub fn parseBool(str: []const u8, dest: *bool) ParseError!void {
    dest.* = try switch (str.len) {
        0 => error.EmptyString,
        1 => switch (str[0]) {
            '1', 't', 'T', 'y', 'Y' => true,
            '0', 'f', 'F', 'n', 'N' => false,
            else => error.InvalidCharacter,
        },
        2 => blk: {
            if (std.mem.eql(u8, "no", str)) break :blk false;
            if (std.mem.eql(u8, "NO", str)) break :blk false;
            break :blk error.InvalidCharacter;
        },
        3 => blk: {
            if (std.mem.eql(u8, "yes", str)) break :blk true;
            if (std.mem.eql(u8, "YES", str)) break :blk true;
            break :blk error.InvalidCharacter;
        },
        4 => blk: {
            if (std.mem.eql(u8, "true", str)) break :blk true;
            if (std.mem.eql(u8, "TRUE", str)) break :blk true;
            break :blk error.InvalidCharacter;
        },
        5 => blk: {
            if (std.mem.eql(u8, "false", str)) break :blk false;
            if (std.mem.eql(u8, "FALSE", str)) break :blk false;
            break :blk error.InvalidCharacter;
        },
        else => error.InvalidCharacter,
    };
}

test "parseBool" {
    var value: bool = undefined;

    // true
    try parseBool("1", &value);
    try expectEqual(true, value);
    try parseBool("t", &value);
    try expectEqual(true, value);
    try parseBool("T", &value);
    try expectEqual(true, value);
    try parseBool("y", &value);
    try expectEqual(true, value);
    try parseBool("Y", &value);
    try expectEqual(true, value);
    try parseBool("yes", &value);
    try expectEqual(true, value);
    try parseBool("YES", &value);
    try expectEqual(true, value);
    try parseBool("true", &value);
    try expectEqual(true, value);
    try parseBool("TRUE", &value);
    try expectEqual(true, value);

    // false
    try parseBool("0", &value);
    try expectEqual(false, value);
    try parseBool("f", &value);
    try expectEqual(false, value);
    try parseBool("F", &value);
    try expectEqual(false, value);
    try parseBool("n", &value);
    try expectEqual(false, value);
    try parseBool("N", &value);
    try expectEqual(false, value);
    try parseBool("no", &value);
    try expectEqual(false, value);
    try parseBool("NO", &value);
    try expectEqual(false, value);
    try parseBool("false", &value);
    try expectEqual(false, value);
    try parseBool("FALSE", &value);
    try expectEqual(false, value);

    // error
    try expectError(error.InvalidCharacter, parseBool("nope", &value));
    try expectError(error.EmptyString, parseBool("", &value));
}

pub fn parseString(str: []const u8, dest: *[]const u8) ParseError!void {
    dest.* = str;
}

test "parseString" {
    var value: []const u8 = undefined;

    // Just returns the same slice without allocating memory, and it allowed to be empty, so not much to test.
    try parseString("Hello World!", &value);
    try expectEqualStrings("Hello World!", value);
    try parseString("Hello\x00World!", &value);
    try expectEqualStrings("Hello\x00World!", value);
}

fn parseSingle(comptime T: type, str: []const u8, dest: *T) ParseError!void {
    return switch (@typeInfo(T)) {
        .Int => parseInt(T, str, dest),
        .Float => parseFloat(T, str, dest),
        .Bool => parseBool(str, dest),
        .Enum => parseEnum(T, str, dest),
        .Pointer => |ptr| blk: {
            comptime assertString(ptr);
            break :blk parseString(str, dest);
        },
        else => @compileError(""),
    };
}

test "parseSingle" {
    // Just test that types are mapped to the correct function, as each has its own more in-depth testing.

    // parseInt
    var int: u16 = undefined;
    try parseSingle(u16, "0x1EFE", &int);
    try expectEqual(0x1EFE, int);
    // parseFloat
    var float: f64 = undefined;
    try parseSingle(f64, "-0.667", &float);
    try expectEqual(-0.667, float);
    // parseBool
    var boolean: bool = undefined;
    try parseSingle(bool, "TRUE", &boolean);
    try expectEqual(true, boolean);

    // parseEnum
    const Number = enum { one, two, three };
    var number: Number = undefined;
    try parseSingle(Number, "two", &number);
    try expectEqual(Number.two, number);

    // parseString
    var string: []const u8 = undefined;
    try parseSingle([]const u8, "string", &string);
    try expectEqualStrings("string", string);
}

/// Parses a fixed-size array from a comma-separated string.
/// The number of parsed items must match the size of the array, else an error is returned.
///
/// Supports the following child types:
///     * any integer type
///     * any float type
///     * string (`[]const u8`)
///     * any enum type (either string field names or numeric values)
///     * UTF-8 codepoint (`u21`)
///     * boolean
pub fn parseArray(comptime T: type, str: []const u8, dest: *T) ParseError!void {
    const ary = comptime @typeInfo(T).Array;
    return parseFixedWidth(T, ary.child, ary.len, str, dest);
}

test "parseArray" {
    var array: [3]u8 = undefined;
    try parseArray([3]u8, "1,2,3", &array);
    try expectEqual([3]u8{ 1, 2, 3 }, array);

    var string_array: [3][]const u8 = undefined;
    try parseArray([3][]const u8, "one,two,three", &string_array);
    try expectEqualStrings("one", string_array[0]);
    try expectEqualStrings("two", string_array[1]);
    try expectEqualStrings("three", string_array[2]);

    try expectError(error.TooManyItems, parseArray([3]u8, "1,2,3,4", &array));
    try expectError(error.NotEnoughItems, parseArray([3]u8, "1,2", &array));
    try expectError(error.InvalidCharacter, parseArray([3]u8, "1,2.0,3", &array));
}

/// Parses a fixed-size vector from a comma-separated string.
/// The number of parsed items must match the size of the vector, else an error is returned.
///
/// Supports the following child types:
///     * any integer type
///     * any float type
///     * UTF-8 codepoint (`u21`)
///     * boolean
pub fn parseVector(comptime T: type, str: []const u8, dest: *T) ParseError!void {
    const vec = comptime @typeInfo(T).Vector;
    return parseFixedWidth(T, vec.child, vec.len, str, dest);
}

test "parseVector" {
    const Vec3 = @Vector(3, f32);
    var value: Vec3 = undefined;
    try parseVector(Vec3, "1.23,4.56,7.89", &value);
    try expectEqual(Vec3{ 1.23, 4.56, 7.89 }, value);
}

/// Parse implementation for array/vector types.
fn parseFixedWidth(comptime T: type, comptime Child: type, comptime len: comptime_int, str: []const u8, dest: *T) ParseError!void {
    if (len == 0) @compileError("empty array/vector is not supported");

    comptime switch (@typeInfo(Child)) {
        .Int, .Float, .Bool, .Enum => {},
        .Pointer => |ptr| {
            if (ptr.size != .Slice or ptr.child != u8 or !ptr.is_const) {
                @compileError("[]const u8 (string) is the only supported pointer type for an array child type, got " ++ @typeName(Child));
            }
        },
        else => @compileError("expected child type of integer, float, boolean, enum, or string, got " ++ @typeName(Child)),
    };

    var i: usize = 0;
    var iter = std.mem.splitScalar(u8, str, ',');

    while (iter.next()) |item| : (i += 1) {
        if (i >= len) return error.TooManyItems;
        try parseSingle(Child, item, &dest[i]);
    }
    if (i != len) return error.NotEnoughItems;
}

inline fn assertString(comptime ptr: std.builtin.Type.Pointer) void {
    comptime if (ptr.size != .Slice or ptr.child != u8 or !ptr.is_const) {
        @compileError("[]const u8 (string) is the only supported slice type");
    };
}

// TODO: Private for now.

/// Parses a sentinel-terminated slice from a comma-separated string.
/// The slice must be pre-allocated, and large enough to hold the number of parsed items,
/// else an error is returned. The slice may be smaller the number of items.
///
/// Supports the following child types:
///     * any integer type
///     * any float type
///     * string (`[]const u8`)
///     * any enum type (either string field names or numeric values)
///     * UTF-8 codepoint (`u21`)
///     * boolean
fn parseSlice(comptime T: type, str: []const u8, dest: *T) ParseError!void {
    const info = comptime @typeInfo(T).Pointer;
    comptime if (info.size != .Slice) @compileError("expected slice, got " ++ @typeName(T));
    comptime if (info.is_const) @compileError("slice cannot be const-qualified");
    comptime if (info.sentinel == null) @compileError("slice must be sentinel-terminated");

    comptime switch (@typeInfo(info.child)) {
        .Int, .Float, .Bool, .Enum => {},
        .Pointer => |ptr| {
            if (ptr.size != .Slice or ptr.child != u8 or !ptr.is_const) {
                @compileError("[]const u8 (string) is the only supported pointer child type, got " ++ @typeName(info.child));
            }
        },
        else => @compileError("expected child type of integer, float, boolean, enum, or string, got " ++ @typeName(info.child)),
    };

    var slice = dest.*;
    var i: usize = 0;
    var iter = std.mem.splitScalar(u8, str, ',');

    while (iter.next()) |item| : (i += 1) {
        if (i >= slice.len) return error.TooManyItems;
        try parseSingle(info.child, item, &slice[i]);
    }

    // Terminate with sentinel to mark how many items were parsed
    if (i < slice.len) {
        const sentinel = @as(*const info.child, @ptrCast(@alignCast(info.sentinel.?)));
        @memset(slice[i..], sentinel.*);
    }
}

test "parseSlice" {
    const sentinel = std.math.maxInt(u8);
    var slice = try std.testing.allocator.allocSentinel(u8, 16, sentinel);
    defer std.testing.allocator.free(slice);

    try parseSlice([:sentinel]u8, "1,2,3,4", &slice);
    var i: usize = 0;
    while (slice[i] != sentinel) : (i += 1) {
        try expectEqual(i + 1, slice[i]);
    }
    try expectEqual(4, i);

    for (0.., slice[0..4 :sentinel]) |index, value| {
        try expectEqual(index + 1, value);
    }
    for (slice[4..]) |value| try expectEqual(sentinel, value);
}
