const std = @import("std");
const AnyValue = @import("AnyValue.zig");
const Allocator = std.mem.Allocator;

const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const string = @import("string.zig");
const ParseError = @import("errors.zig").ParseError;

/// Prototype of a function that can parse a string into type `T`.
pub fn ParseFunc(comptime T: type) type {
    return *const fn (str: []const u8, value_ptr: *T) ParseError!void;
}

/// Prototype of a function that can return the string representation for a value of type `T`.
pub fn StringFunc(comptime T: type) type {
    return *const fn (allocator: Allocator, value: *const T) Allocator.Error![]u8;
}

/// Returns a wrapper for a pointer of type `T`.
///
/// All get/set operations do so at the location of the pointer assigned during initialization.
/// This type does no allocations, nor has any storage of its own.
pub fn Value(comptime T: type, comptime parse_func: ParseFunc(T)) type {
    return struct {
        const Self = @This();

        /// A pointer the value being wrapped.
        value_ptr: *T,
        /// Optional function pointer that will be called to retrieve
        /// the name of an argument of this type in usage text.
        ///
        /// When `null`, a generic built-in function will be used.
        ///
        /// ex. `Value(u32)` -> "uint"
        ///     `Value([]const u8)` -> "string"
        ///     `Value([3]i32)` -> "ints"
        argname_func: ?*const fn () []const u8,
        /// Optional function pointer that will be called to retrieve
        /// the this value represented as a string.
        ///
        /// When `null`, a generic built-in function will be used.
        ///
        /// ex. `Value(u32)` -> "45"
        ///     `Value([]const u8)` -> "hello world"
        ///     `Value([3]i32)` -> "1,2,3"
        string_func: ?StringFunc(T),

        /// Initializes the struct, wrapping the value located at `value_ptr`.
        pub fn init(value_ptr: *T) Self {
            return .{
                .value_ptr = value_ptr,
                .argname_func = null,
                .string_func = null,
            };
        }

        /// Returns an implementation of the `AnyValue` interface wrapping the value.
        pub fn any(self: Self) AnyValue {
            return AnyValue{
                .type_name = @typeName(T),
                .value_ptr = @ptrCast(self.value_ptr),
                .parse_func = parseImpl,
                .string_func = stringImpl,
                .argname_func = self.argname_func orelse defaultArgName,
            };
        }

        /// Get the value of the wrapped variable.
        pub fn get(self: *Self) T {
            return self.value_ptr.*;
        }

        /// Set the value of the wrapped variable.
        pub fn set(self: *Self, value: T) void {
            self.value_ptr.* = value;
        }

        /// Returns the string representation of the value.
        pub fn toString(self: *Self, allocator: Allocator) Allocator.Error![]u8 {
            if (self.string_func) |fptr| {
                return fptr(allocator, self.value_ptr);
            }
            return stringImpl(allocator, self.value_ptr);
        }

        /// Parse implementation wrapping the provided parse function.
        fn parseImpl(str: []const u8, ptr: *anyopaque) ParseError!void {
            const value_ptr: *T = @ptrCast(@alignCast(ptr));
            return parse_func(str, value_ptr);
        }

        /// Generic stringify implementation.
        fn stringImpl(allocator: Allocator, ptr: *const anyopaque) Allocator.Error![]u8 {
            const value: T = @as(*const T, @ptrCast(@alignCast(ptr))).*;
            var buffer = std.ArrayList(u8).init(allocator);
            defer buffer.deinit();
            var writer = buffer.writer();

            switch (@typeInfo(T)) {
                .Int, .Float, .Bool, .Enum, .Pointer => try writeSingleValue(T, writer, value),
                .Array => |ary| {
                    for (0..ary.len) |i| {
                        if (i > 0) try writer.writeByte(',');
                        try writeSingleValue(ary.child, writer, value[i]);
                    }
                },
                .Vector => |vec| {
                    for (0..vec.len) |i| {
                        if (i > 0) try writer.writeByte(',');
                        try writeSingleValue(vec.child, writer, value[i]);
                    }
                },
                else => std.fmt.format(writer, "{any}", .{value}) catch return error.OutOfMemory,
            }

            return buffer.toOwnedSlice();
        }

        fn writeSingleValue(comptime Type: type, writer: std.ArrayList(u8).Writer, value: Type) Allocator.Error!void {
            return switch (@typeInfo(Type)) {
                .Int, .Float => std.fmt.format(writer, "{d}", .{value}),
                .Bool => writer.writeAll(if (value) "true" else "false"),
                .Enum => |e| blk: {
                    if (e.is_exhaustive) break :blk writer.writeAll(@tagName(value));
                    break :blk std.fmt.format(writer, "{d}", .{@as(e.tag_type, @intFromEnum(value))});
                },
                .Pointer => writer.writeAll(value), // can only be []const u8
                else => unreachable,
            };
        }

        /// Returns an function to get the argument name.
        fn defaultArgName() []const u8 {
            return comptime argName(T);
        }

        /// Default implementation to get the argument name.
        fn argName(comptime Type: type) []const u8 {
            return switch (@typeInfo(Type)) {
                .Int => |int| switch (int.signedness) {
                    .signed => "int",
                    else => if (int.bits == 21) "char" else "uint",
                },
                .Enum => |e| blk: {
                    if (e.is_exhaustive) break :blk "string";
                    break :blk switch (@typeInfo(e.tag_type).Int.signedness) {
                        .signed => "int",
                        else => "uint",
                    };
                },
                .Float => "float",
                .Bool => "bool",
                .Pointer => |ptr| blk: {
                    comptime if (ptr.size != .Slice or ptr.child != u8 or !ptr.is_const) {
                        @compileError("[]const u8 (string) is the only supported slice type");
                    };
                    break :blk "string";
                },
                .Array => |ary| argName(ary.child) ++ if (ary.len > 1) "s" else "",
                .Vector => |vec| argName(vec.child) ++ if (vec.len > 1) "s" else "",
                else => "arg",
            };
        }
    };
}

test "Value" {
    const Closure = struct {
        fn parse(str: []const u8, dest: *u32) ParseError!void {
            return string.parseInt(u32, str, dest);
        }
    };

    const Uint32 = Value(u32, Closure.parse);
    var variable: u32 = undefined;
    var value = Uint32.init(&variable);

    // get/set
    value.set(2000);
    try expectEqual(2000, variable);
    try expectEqual(2000, value.get());

    // toString
    const str = try value.toString(std.testing.allocator);
    defer std.testing.allocator.free(str);
    try expectEqualStrings("2000", str);
    try expectEqualStrings("uint", Uint32.defaultArgName());

    const any = value.any();
    try any.parse("0xEFBBBF");
    try expectEqual(0xEFBBBF, variable);
    try expectEqual(0xEFBBBF, value.get());

    // Copy any by value
    const any_copy = any;
    try any_copy.parse("88");
    try expectEqual(88, variable);
    try expectEqual(88, value.get());

    // copy by value
    variable = 22;
    var value_copy = value;
    try expectEqual(variable, value_copy.get());
    try expectEqual(22, value_copy.get());
    try expectEqual(22, value_copy.value_ptr.*);

    value_copy.set(69);

    try expectEqual(69, value_copy.value_ptr.*);
    try expectEqual(69, variable);
    try expectEqual(69, variable);

    try expectEqual(variable, value_copy.get());
    try expectEqual(69, value_copy.get());
    try expectEqual(69, value_copy.value_ptr.*);
}
