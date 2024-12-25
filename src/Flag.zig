//! Describes a flag that can be parsed from command-line arguments.
//!
//! Unless otherwise stated explicitly, all fields should be considered read-only.
//! This type is intended to be exclusively interacted with via a `FlagSet`.

const std = @import("std");
const testing = std.testing;
const stropts = @import("string.zig");
const Allocator = std.mem.Allocator;

const Error = @import("errors.zig").Error;
const AnyValue = @import("AnyValue.zig");
const Flag = @This();

/// A dynamic list of immutable strings.
pub const StringList = std.ArrayListUnmanaged([]const u8);

/// Container for arbitrary metadata.
pub const Annotations = std.StringHashMapUnmanaged(StringList);

/// Name of the flag.
///
/// This field is read-only.
name: []const u8,
/// Brief message text to be displayed in help messages.
/// e.g. "set an alternate database location"
///
/// This field is read-only.
usage: []const u8,
/// Alternative names that map to the same flag.
/// e.g Flag with name "silent" can have "quiet" and "mute" as aliases.
aliases: StringList,
/// Optional single-letter abbreviated flag.
/// e.g. "-v" maps to "--verbose"
shorthand: ?u8,
/// The value of the argument.
/// This field is private and intended only for internal use.
value: AnyValue,
/// Default value (as text), used for help/usage message.
default: ?[]const u8,
/// Default value (as text), used for help/usage message if the flag is present without any options.
default_no_opt: ?[]const u8,
/// If this flag is deprecated, this string provides a message with alternative or explanation.
/// A `null` value indicates the flag is not deprecated.
deprecated: ?[]const u8,
/// If the shorthand flag is deprecated, this string provides a message with alternative or explanation.
/// A `null` value indicates the shorthand flag is not deprecated.
deprecated_shorthand: ?[]const u8,
/// Indicates if the value has been set during parsing.
changed: bool,
/// Indicates if flag will be displayed in help/usage text.
/// Hidden flags will function normally.
hidden: bool,
/// Arbitrary metadata associated with the flag.
annotations: Annotations,

/// Allocates and initializes a new `Flag` with the specified configuration.
///
///     * `T` is the data type of the argument.
///     * `name` it the name of the argument (without leading dashed) e.g. "output"
///     * `shorthand` is an optional single letter variant e.g. 'o'
///     * `usage` is the brief text to be displayed in help messages
///     * `ptr` is a pointer to a variable where the value will be stored
pub fn create(allocator: Allocator, name: []const u8, shorthand: ?u8, usage: []const u8, value: AnyValue) Error!*Flag {
    if (shorthand) |c| if (!std.ascii.isAlphabetic(c)) return error.InvalidShorthand;
    // Trim any leading dash from string and ensure it is compliant.
    const flag_name: []const u8 = blk: {
        const trimmed = std.mem.trimLeft(u8, name, &.{'-'});
        if (trimmed.len == 0) return error.InvalidFlagName;
        for (0.., trimmed) |i, c| {
            if (i == 0 and !std.ascii.isAlphabetic(c)) return error.InvalidFlagName;
            if (std.ascii.isAlphanumeric(c)) continue;
            if (c != '-' and c != '_') return error.InvalidFlagName;
        }
        break :blk try allocator.dupe(u8, trimmed);
    };
    errdefer allocator.free(flag_name);

    const flag_usage = try allocator.dupe(u8, usage);
    errdefer allocator.free(flag_usage);

    const flag = try allocator.create(Flag);
    flag.* = .{
        .name = flag_name,
        .usage = flag_usage,
        .aliases = .{},
        .shorthand = shorthand,
        .value = value,
        .default = null,
        .default_no_opt = null,
        .deprecated = null,
        .deprecated_shorthand = null,
        .changed = false,
        .hidden = false,
        .annotations = .{},
    };

    // Ensure that bool values have a default "true" value
    if (std.mem.eql(u8, "bool", value.type_name)) {
        flag.default_no_opt = try allocator.dupe(u8, "true");
    }

    return flag;
}

/// Creates a deep-copy of another flag and returns it.
pub fn dupe(allocator: Allocator, other: *Flag) Allocator.Error!*Flag {
    var flag = try allocator.create(Flag);
    errdefer flag.destroy(allocator);
    // Initialize to zero so if an error occurs midway though,
    // the deferred called to destroy won't segfault.
    flag.* = .{
        .name = &.{},
        .usage = &.{},
        .aliases = .{},
        .shorthand = null,
        .value = undefined,
        .default = null,
        .default_no_opt = null,
        .deprecated = null,
        .deprecated_shorthand = null,
        .changed = false,
        .hidden = false,
        .annotations = .{},
    };

    flag.name = try allocator.dupe(u8, other.name);
    flag.usage = try allocator.dupe(u8, other.usage);
    if (other.default) |str| flag.default = try allocator.dupe(u8, str);
    if (other.default_no_opt) |str| flag.default_no_opt = try allocator.dupe(u8, str);
    if (other.deprecated) |str| flag.deprecated = try allocator.dupe(u8, str);
    if (other.deprecated_shorthand) |str| flag.deprecated_shorthand = try allocator.dupe(u8, str);

    if (other.annotations.size == 0) return flag;
    try flag.annotations.ensureTotalCapacity(allocator, other.annotations.size);
    var iter = other.annotations.iterator();
    while (iter.next()) |entry| {
        const key = try allocator.dupe(u8, entry.key_ptr.*);
        errdefer allocator.free(key);

        const size = entry.value_ptr.*.items.len;
        var list = try StringList.initCapacity(allocator, size);
        errdefer {
            for (list.items) |item| allocator.free(item);
            list.deinit(allocator);
        }
        for (entry.value_ptr.*.items) |item| {
            const str = try allocator.dupe(u8, item);
            list.appendAssumeCapacity(str);
        }
        flag.annotations.putAssumeCapacity(key, list);
    }

    return flag;
}

/// Frees all memory stored in the flag and invalidates its pointer.
pub fn destroy(self: *Flag, allocator: Allocator) void {
    if (self.name.len > 0) allocator.free(self.name);
    if (self.usage.len > 0) allocator.free(self.usage);
    if (self.default) |str| allocator.free(str);
    if (self.default_no_opt) |str| allocator.free(str);
    if (self.deprecated) |str| allocator.free(str);
    if (self.deprecated_shorthand) |str| allocator.free(str);

    var iter = self.annotations.iterator();
    while (iter.next()) |entry| {
        allocator.free(entry.key_ptr.*);
        for (entry.value_ptr.items) |str| allocator.free(str);
        entry.value_ptr.*.deinit(allocator);
    }
    self.annotations.deinit(allocator);
    allocator.destroy(self);
}

/// Searches the `usage` string for a back-quoted name that will
/// be used as the variable name in usage text.
///
/// When not found, a generic name based on the value type (e.g. "int", "string")
/// will be used as a placeholder. Boolean flags will not return an value,
/// as the presence of the flag already indicates the value.
pub fn argName(self: *Flag) []const u8 {
    for (0.., self.usage) |i, beg| {
        if (beg != '`') continue;
        for (i + 1.., self.usage[i + 1 ..]) |j, end| {
            if (std.ascii.isWhitespace(end)) break;
            if (end == '`') return self.usage[i + 1 .. j];
        } else break;
    }

    const arg_name = self.value.argName();
    return if (std.mem.eql(u8, "bool", arg_name)) "" else arg_name;
}
