const std = @import("std");
const string = @import("string.zig");
const wrapper = @import("wrapper.zig");

const Allocator = std.mem.Allocator;
const AnyValue = @import("AnyValue.zig");
const Error = @import("errors.zig").Error;
const FlagSet = @This();
const Flag = @import("Flag.zig");

/// A dynamically-sized list of flags.
pub const FlagList = std.ArrayListUnmanaged(*Flag);

/// Because "[]const []const u8" doesn't make me feel nice.
const ArgList = []const []const u8;

/// A hashmap containing flags, with their names as keys.
pub const FlagMap = std.StringHashMapUnmanaged(*Flag);

/// Iterator for flags.
pub const FlagIterator = struct {
    /// The current index.
    index: usize = 0,
    /// The items to be yielded.
    items: []const *Flag,

    /// Yields the next item in the iterator, or `null` when all items have been exhausted.
    pub fn next(self: *FlagIterator) ?*Flag {
        if (self.index >= self.items.len) return null;
        defer self.index += 1;
        return self.items[self.index];
    }
};

/// Allocator used by the set.
allocator: Allocator,
/// The name of the flag set.
name: []const u8,
/// The function called to display usage text to the user (e.g. "appname --help").
/// A `null` value uses a built-in function, but it can be overridden by assigning this field.
usage: ?*const fn (self: *FlagSet) void,
/// Indicates if the flags have been parsed from the command line.
parsed: bool,
/// Indicates if flags will be sorted lexicographical order in the usage text.
/// When false, flags will be displayed in the order they were added to the set.
/// The default it `true`.
sort: bool,
/// Indicates if mixed option/non-option arguments are permitted in any order.
/// The default it `true`.
interspersed: bool,
/// Automatically output an error message to the user and terminate the process
/// when an error is encountered.
///
/// This only applies to errors created from invalid user-defined input.
exit_on_error: bool,
/// Arguments that were are not flags/options.
///
/// For example, given command-line "curl --cert client.pem --key key.pem --insecure https://example.com",
/// `args` would contain only "https://example.com", as it not part of the options.
args: ArgList,
/// The length of the arguments at the point a `--` was encountered while parsing, or `null` if not present.
len_at_terminator: ?usize,
/// Mapping of flags that were explicitly parsed from the command line arguments.
/// This field should only be used in a read-only context.
actual: FlagMap,
/// Mapping of all known flags, including those not set by the command line arguments.
/// This field should only be used in a read-only context.
formal: FlagMap,
/// Mapping of shorthand arguments to flags.
/// This field should only be used in a read-only context.
shorthands: std.AutoHashMapUnmanaged(u8, *Flag),
/// List of lags in the order they were parsed from command-line arguments;
/// This field is private and for internal use only. See `iterator()`.
actual_ordered: FlagList,
/// List of flags in the order they were defined.
/// This field is private and for internal use only. See `iterator()`.
formal_ordered: FlagList,
/// List of flags parsed from the command line arguments in lexicographical order.
/// This field is private and for internal use only. See `iterator()`.
actual_sorted: FlagList,
/// List of all defined flags in lexicographical order.
/// This field is private and for internal use only. See `iterator()`.
formal_sorted: FlagList,
/// Writer where help/usage messages will be written to.
/// Defaults to `stderr` when `null`, but can be overridden by assigning to this field.
output: ?std.io.AnyWriter,
/// Indicates if unknown flags will be ignored during parsing.
/// When `true`, unknown flags are skipped, otherwise they result in errors.
ignore_unknown: bool,

pub fn init(allocator: Allocator, name: []const u8) Error!FlagSet {
    const set_name = try allocator.dupe(u8, name);
    errdefer allocator.free(set_name);

    return FlagSet{
        .allocator = allocator,
        .name = set_name,
        .usage = null,
        .parsed = false,
        .sort = true,
        .interspersed = true,
        .exit_on_error = true,
        .args = &.{},
        .len_at_terminator = null,
        .actual = .{},
        .formal = .{},
        .actual_sorted = .{},
        .formal_sorted = .{},
        .actual_ordered = .{},
        .formal_ordered = .{},
        .shorthands = .{},
        .output = null,
        .ignore_unknown = false,
    };
}

/// Prints an error message to the user, and optionally exits the application when `exit_on_error` is `true`.
fn printError(self: *FlagSet, comptime fmt: []const u8, args: anytype) void {
    const output = self.getOutput();
    std.fmt.format(output, fmt, args) catch {};
    if (self.exit_on_error) std.process.exit(1);
}

/// Frees all memory and invalidates all pointers associated with the set.
pub fn deinit(self: *FlagSet) void {
    self.allocator.free(self.name);
    if (self.args.len > 0) {
        for (self.args) |arg| self.allocator.free(arg);
        self.allocator.free(self.args);
    }

    self.actual_ordered.deinit(self.allocator);
    self.actual_sorted.deinit(self.allocator);
    self.formal_sorted.deinit(self.allocator);

    self.shorthands.deinit(self.allocator);
    self.actual.deinit(self.allocator);
    self.formal.deinit(self.allocator);

    for (self.formal_ordered.items) |flag| flag.destroy(self.allocator);
    self.formal_ordered.deinit(self.allocator);
}

/// Merges another set into this one.
///
/// When `ignore_duplicates` is `true`, flags in `other` that have conflicting
/// name/shorthand/alias values will be skipped, otherwise an error is returned.
pub fn merge(self: *FlagSet, other: *FlagSet, ignore_duplicates: bool) Error!void {
    for (other.formal_ordered.items) |flag| {
        // Check if the flag with the same name already exists
        if (self.getFlag(flag.name, true)) |_| {
            if (!ignore_duplicates) continue;
            return error.DuplicateName;
        }
        // Check if the flag with the same shorthand name already exists
        if (flag.shorthand) |c| {
            if (self.getShorthand(c)) |_| {
                if (ignore_duplicates) continue;
                return error.DuplicateShorthand;
            }
        }
        // Check if the flag with any alias names already exists
        for (flag.aliases.items) |name| {
            if (self.getFlag(name, true)) |_| {
                if (ignore_duplicates) continue;
                return error.DuplicateName;
            }
        }
        // Create deep-clone of the flag and add it
        const copy = try Flag.dupe(self.allocator, flag);
        errdefer copy.destroy(self.allocator);
        try self.formal.put(self.allocator, copy.name, copy);
        try self.formal_ordered.append(self.allocator, copy);
    }
}

/// Defines a new flag in the set and returns it.
///
///     * `T` is the data type of the argument.
///     * `name` it the name of the argument (without leading dashed) e.g. "output"
///     * `shorthand` is an optional single letter variant e.g. 'o'
///     * `usage` is the brief text to be displayed in help messages
///     * `ptr` is a pointer to a variable where the value will be stored
///
/// If a flag with the same name, alias, or shorthand already exists, an error will be returned.
pub fn addFlag(self: *FlagSet, comptime T: type, name: []const u8, shorthand: ?u8, usage: []const u8, ptr: *T) Error!void {
    // Determine the appropriate wrapper type at comptime.
    const ValueType = comptime switch (@typeInfo(T)) {
        .Int => wrapper.Int(T),
        .Float => wrapper.Float(T),
        .Bool => wrapper.Bool,
        .Enum => wrapper.Enum(T),
        .Array => wrapper.Array(T),
        .Vector => wrapper.Vector(T),
        .Pointer => |pointer| blk: {
            if (pointer.size != .Slice) @compileError("pointer types require a custom parsing implementation");
            if (pointer.child != u8) @compileError("slices types must be \"[]const u8\" (string), found " ++ @typeName(T));
            if (!pointer.is_const) @compileError("expected \"[]const u8\", found \"[]u8\"");
            break :blk wrapper.String;
        },
        else => @compileError("unable to parse \"" ++ @typeName(T) ++ "\" type, see addFlagWithValue()"),
    };

    var value = ValueType.init(ptr);
    try addFlagWithValue(self, name, shorthand, usage, value.any());
}

/// Defines a new flag in the set and returns it.
///
///     * `T` is the data type of the argument.
///     * `name` it the name of the argument (without leading dashed) e.g. "output"
///     * `shorthand` is an optional single letter variant e.g. 'o'
///     * `usage` is the brief text to be displayed in help messages
///     * `ptr` is a pointer to a variable where the value will be stored
///     * `default` is an optional value to assign if flag is omitted.
///
/// If a flag with the same name, alias, or shorthand already exists, an error will be returned.
pub fn addFlagDefault(self: *FlagSet, comptime T: type, name: []const u8, shorthand: ?u8, usage: []const u8, ptr: *T, default: []const u8) Error!void {
    try addFlag(self, T, name, shorthand, usage, ptr);
    const flag = self.formal_ordered.items[self.formal_ordered.items.len - 1];
    try flag.value.parse(default);
    flag.default = try self.allocator.dupe(u8, default);
}

/// Defines a new flag in the set and returns it.
///
///     * `T` is the data type of the argument.
///     * `name` it the name of the argument (without leading dashed) e.g. "output"
///     * `shorthand` is an optional single letter variant e.g. 'o'
///     * `usage` is the brief text to be displayed in help messages
///     * `value` is a wrapper for the value of the flag.
///
/// If a flag with the same name, alias, or shorthand already exists, an error will be returned.
pub fn addFlagWithValue(self: *FlagSet, name: []const u8, shorthand: ?u8, usage: []const u8, value: AnyValue) Error!void {
    // Duplication checks
    if (shorthand) |c| if (self.shorthands.contains(c)) return error.DuplicateShorthand;
    if (self.getFlag(name, true)) |_| return error.DuplicateName;

    // Create the flag
    const flag = try Flag.create(self.allocator, name, shorthand, usage, value);
    errdefer flag.destroy(self.allocator);

    // Store the flag using its formal name, and optionally shorthand.
    try self.formal.put(self.allocator, flag.name, flag);
    try self.formal_ordered.append(self.allocator, flag);
    if (flag.shorthand) |c| try self.shorthands.put(self.allocator, c, flag);
}

/// Tests if the set has any flags defined, optionally including those in a "hidden" state.
///
/// A hidden flag functions normally, but does not appear in help/usage messages.
pub fn hasFlags(self: *FlagSet, include_hidden: bool) bool {
    // Simply test if any flags have been added, hidden or not.
    if (include_hidden) return self.formal_ordered.items.len > 0;
    // Loop through the flags and determine if any are not hidden.
    for (self.formal_ordered.items) |flag| {
        if (!flag.hidden) return true;
    }
    return false;
}

/// Performs a look for a flag by the given name and returns it.
/// When `aliases` is `true`, all flag aliases will also be searched for a match.
/// Returns `null` when no matching flag was found.
pub fn getFlag(self: *FlagSet, name: []const u8, aliases: bool) ?*Flag {
    // Since the happy-path is a matching name, check all of them before aliases.
    if (self.formal.get(name)) |flag| return flag;

    if (aliases) for (self.formal_ordered.items) |flag| {
        for (flag.aliases.items) |alias_name| {
            if (std.mem.eql(u8, alias_name, name)) return flag;
        }
    };
    return null;
}

/// Gets the value of a flag as a string.
/// The caller is responsible for freeing the returned memory.
pub fn getValue(self: *FlagSet, allocator: Allocator, name: []const u8) Error![]u8 {
    if (self.getFlag(name, true)) |flag| {
        return flag.value.toString(allocator);
    }
    return error.UnknownFlag;
}

/// Sets the value of a flag.
///
///     * `name` is the name/alias of a flag within the set
///     * `value` is the value to set, represented as a string.
pub fn setValue(self: *FlagSet, name: []const u8, value: []const u8) !void {
    if (self.getFlag(name, true)) |flag| {
        // Ensure the string is well-formed
        const str = if (string.isEmptyOrWhitespace(value)) blk: {
            // If the value is empty, assign a default value if configured
            if (flag.default_no_opt) |default| break :blk default;
            // Default to "true" for boolean flags that have not set a default
            if (std.mem.eql(u8, "bool", flag.value.type_name)) break :blk "true";
            break :blk value;
        } else value;

        // Set the value, and update the changed flag containers.
        flag.value.parse(str) catch |err| {
            if (flag.shorthand != null and flag.deprecated_shorthand == null) {
                const c = flag.shorthand.?;
                self.printError("invalid argument \"{s}\" for -{c}, --{s}\n", .{ value, c, name });
            } else {
                self.printError("invalid argument \"{s}\" for --{s}\n", .{ value, name });
            }
            return err;
        };

        if (!flag.changed) {
            try self.actual.put(self.allocator, flag.name, flag);
            try self.actual_ordered.append(self.allocator, flag);
            flag.changed = true;
        }

        // Output deprecated message when defined
        if (flag.deprecated) |msg| {
            const writer = self.getOutput();
            try std.fmt.format(writer, "flag --{s} has been deprecated, {s}\n", .{ flag.name, msg });
        }
    } else return error.UnknownFlag;
}

/// Gets the value of a flag as its concrete type, or
/// return an error when `T` is the incorrect type.
pub fn getValueAs(self: *FlagSet, comptime T: type, name: []const u8) Error!T {
    if (self.getFlag(name, true)) |flag| {
        if (!std.mem.eql(u8, @typeName(T), flag.value.value_type)) return error.TypeMismatch;
        return @as(*T, @ptrCast(@alignCast(flag.value.value_ptr))).*;
    }
    return error.UnknownFlag;
}

/// Sets the value of a flag as its concrete type, or
/// return an error when `T` is the incorrect type.
pub fn setValueAs(self: *FlagSet, comptime T: type, name: []const u8, value: T) Error!T {
    if (self.getFlag(name, true)) |flag| {
        // Check that T is the correct type.
        if (!std.mem.eql(u8, @typeName(T), flag.value.value_type)) return error.TypeMismatch;

        const value_ptr = @as(*T, @ptrCast(@alignCast(flag.value.value_ptr)));
        value_ptr.* = value;

        if (!flag.changed) {
            try self.actual.put(self.allocator, flag.name, flag);
            try self.actual_ordered.append(self.allocator, flag);
            flag.changed = true;
        }

        // Output deprecated message when defined
        if (flag.deprecated) |msg| {
            const writer = self.getOutput();
            try std.fmt.format(writer, "flag --{s} has been deprecated, {s}\n", .{ flag.name, msg });
        }
    }

    return error.UnknownFlag;
}

/// Performs a lookup for a flag by the given shorthand letter and returns it.
/// Returns `null` when no matching flag was found.
pub fn getShorthand(self: *FlagSet, chr: u8) ?*Flag {
    return self.shorthands.get(chr);
}

/// Returns a writer where help/usage messages are written to.
/// Defaults to stderr when the `output` field is unset.
pub fn getOutput(self: *FlagSet) std.io.AnyWriter {
    return self.output orelse blk: {
        const stderr_file = std.io.getStdErr();
        const stderr = stderr_file.writer();
        break :blk stderr.any();
    };
}

/// Returns an iterator for the flags in the set.
///
/// When `sort` is `true`, flags will be yielded in lexicographical order,
/// otherwise they are in primordial order.
///
/// When `all` is `true`, all flags will be returned, otherwise only flags that were
/// explicitly set (i.e. parsed from command-line arguments) will be included.
///
/// The iterator does not need freed. Sorting is done lazily, and results are cached,
/// hence a possible allocation error being returned.
pub fn iterator(self: *FlagSet, sorted: bool, all: bool) Allocator.Error!FlagIterator {
    var list: FlagList = undefined;

    // TODO: Break this into separate sorted/ordered functions

    if (all) {
        list = if (sorted) blk: {
            // Sort now if needed
            if (self.formal_ordered.items.len != self.formal_sorted.items.len) {
                self.formal_sorted.deinit(self.allocator);
                self.formal_sorted = try sortFlags(self.allocator, self.formal_ordered);
            }
            break :blk self.formal_sorted;
        } else self.formal_ordered;
    } else {
        list = if (sorted) blk: {
            // Sort now if needed
            if (self.actual_ordered.items.len != self.actual_sorted.items.len) {
                self.actual_sorted.deinit(self.allocator);
                self.actual_sorted = try sortFlags(self.allocator, self.actual_ordered);
            }
            break :blk self.actual_sorted;
        } else self.actual_ordered;
    }

    return FlagIterator{ .items = list.items };
}

/// Sorts a list of flags in alphanumeric order.
fn sortFlags(allocator: Allocator, unsorted: FlagList) Allocator.Error!FlagList {
    const Compare = struct {
        fn lessThan(context: void, a: *Flag, b: *Flag) bool {
            _ = context;
            const len = @min(a.name.len, b.name.len);
            for (a.name[0..len], b.name[0..len]) |c1, c2| {
                if (c1 == c2) continue;
                return c1 < c2;
            } else return a.name.len < b.name.len;
        }
    };

    var result = try FlagList.initCapacity(allocator, unsorted.items.len);
    result.appendSliceAssumeCapacity(unsorted.items);
    std.mem.sort(*Flag, result.items, void{}, Compare.lessThan);
    return result;
}

/// Defines an alternative name that maps to the same flag.
/// e.g. "--silent" and "--quiet" can be used interchangeably.
pub fn alias(self: *FlagSet, name: []const u8, alias_name: []const u8) Error!void {
    if (self.getFlag(alias_name, true)) |_| return error.DuplicateName;
    if (self.getFlag(name, false)) |flag| {
        const owned = try self.allocator.dupe(u8, alias_name);
        try flag.aliases.append(self.allocator, owned);
    } else return error.UnknownFlag;
}

/// Marks a flag with the given name as "hidden".
/// Returns an error if the flag does not exist.
pub fn hide(self: *FlagSet, name: []const u8) Error!void {
    if (self.getFlag(name, true)) |flag| {
        flag.hidden = true;
    } else return error.UnknownFlag;
}

/// Sets the default value of a flag.
/// The value must successfully parse or an error is returned.
pub fn setDefault(self: *FlagSet, name: []const u8, value: []const u8) Error!void {
    if (self.getFlag(name, true)) |flag| {
        try flag.value.parse(value);
        if (flag.default) |str| self.allocator.free(str);
        flag.default = try self.allocator.dupe(u8, value);
    } else return error.UnknownFlag;
}

/// Sets the default value of a flag when no value is supplied with it.
/// When this value is not set, the flag requires a user-defined argument.
///
/// Boolean flags automatically have a value of "true", and do not need set explicitly.
pub fn setDefaultNoOpt(self: *FlagSet, name: []const u8, value: []const u8) Error!void {
    if (self.getFlag(name, true)) |flag| {
        if (flag.default_no_opt) |str| self.allocator.free(str);
        flag.default_no_opt = try self.allocator.dupe(u8, value);
    } else return error.UnknownFlag;
}

/// Marks a flag as deprecated, which will print the specified usage message when it is used.
/// Deprecating a flag automatically hides it from usage text.
pub fn deprecate(self: *FlagSet, name: []const u8, usage: []const u8) Error!void {
    if (self.getFlag(name, false)) |flag| {
        if (string.isEmptyOrWhitespace(usage)) return error.EmptyString;
        if (flag.deprecated) |str| self.allocator.free(str);
        flag.deprecated = try self.allocator.dupe(u8, usage);
        flag.hidden = true;
    } else return error.UnknownFlag;
}

/// Marks a shorthand flag as deprecated, which will print the specified usage message when it is used.
/// Deprecating a shorthand flag automatically hides it from usage text.
pub fn deprecateShorthand(self: *FlagSet, shorthand: u8, usage: []const u8) Error!void {
    if (self.shorthands.get(shorthand)) |flag| {
        if (string.isEmptyOrWhitespace(usage)) return error.EmptyString;
        if (flag.deprecated_shorthand) |str| self.allocator.free(str);
        flag.deprecated_shorthand = try self.allocator.dupe(u8, usage);
    } else return error.UnknownFlag;
}

/// Sets an arbitrary annotation on a flag.
///
/// This allows programs to assign additional metadata, such as shell completion information, etc.
pub fn annotate(self: *FlagSet, name: []const u8, key: []const u8, entry: []const u8) Error!void {
    if (self.getFlag(name, true)) |flag| {
        // Create a copy of the key, and attempt to get existing entry, creating if not found.
        const owned_key = try self.allocator.dupe(u8, key);
        const result = flag.annotations.getOrPut(self.allocator, owned_key) catch |err| {
            self.allocator.free(owned_key);
            return err;
        };
        // If the key already existed, so free the copy that was made
        defer if (result.found_existing) self.allocator.free(owned_key);
        // Append the line of text to the entry.
        var list: Flag.StringList = result.value_ptr.*;
        // Zero the memory if it didn't previously exist.
        if (!result.found_existing) list = .{};

        const owned_value = try self.allocator.dupe(u8, entry);
        errdefer self.allocator.free(owned_value);
        try list.append(self.allocator, owned_value);
    } else return error.UnknownFlag;
}

/// Sets a slice of arbitrary annotations on a flag.
///
/// This allows programs to assign additional metadata, such as shell completion information.
pub fn annotateSlice(self: *FlagSet, name: []const u8, key: []const u8, entries: []const []const u8) Error!void {
    // Early out if no values
    if (entries.len == 0) return;
    if (self.getFlag(name, true)) |flag| {

        // Create a copy of the key, and attempt to get existing entry, creating if not found.
        const owned_key = try self.allocator.dupe(u8, key);
        const result = flag.annotations.getOrPut(self.allocator, owned_key) catch |err| {
            self.allocator.free(owned_key);
            return err;
        };
        // If the key already existed, free the copy that was made
        defer if (result.found_existing) self.allocator.free(owned_key);
        // Append the line of text to the entry.
        var list: Flag.StringList = result.value_ptr.*;
        // Zero the memory if it didn't previously exist.
        if (!result.found_existing) list = .{};

        // Ensure enough space for the entries, then add them.
        try list.ensureUnusedCapacity(self.allocator, entries.len);
        for (entries) |entry| {
            list.appendAssumeCapacity(try self.allocator.dupe(u8, entry));
        }
    } else return error.UnknownFlag;
}

/// Gets the annotations for the flag with the given name and key.
/// Returns `null` if the flag cannot be found, or no annotation with the key exist.
pub fn annotation(self: *FlagSet, name: []const u8, key: []const u8) ?[]const []const u8 {
    if (self.getFlag(name, true)) |flag| {
        if (flag.annotations.get(key)) |list| return list.items;
    }
    return null;
}

/// Tests if a flag with the given name as been explicitly set during parsing.
/// Returns an error if the flag does not exist.
pub fn isChanged(self: *FlagSet, name: []const u8) Error!bool {
    if (self.getFlag(name, true)) |flag| {
        return flag.changed;
    } else return error.UnknownFlag;
}

/// Prints the default usage text.
pub fn printDefaults(self: *FlagSet) !void {
    const usages = try self.flagUsages(self.allocator, 0);
    defer self.allocator.free(usages);

    const output = self.getOutput();
    if (self.output == null) {
        try std.fmt.format(output, "Usage of {s}:\n", .{self.name});
    }
    return output.writeAll(usages);
}

/// Returns the usage text, wrapped to the specified number of columns.
/// A value of `0` indicates no wrapping.
///
/// The caller is responsible for freeing the returned memory.
pub fn flagUsages(self: *FlagSet, allocator: Allocator, columns: usize) Allocator.Error![]u8 {
    var lines = try std.ArrayList([]u8).initCapacity(allocator, self.formal_ordered.items.len);
    defer {
        for (lines.items) |line| allocator.free(line);
        lines.deinit();
    }

    var line_buffer = std.ArrayList(u8).init(allocator);
    defer line_buffer.deinit();
    var writer = line_buffer.writer();

    var max_len: usize = 0;
    var iter = try self.iterator(self.sort, true);
    while (iter.next()) |flag| {
        // Do not print hidden flags
        if (flag.hidden) continue;

        // Print the shorthand and flag names
        if (flag.shorthand != null and flag.deprecated_shorthand == null) {
            try std.fmt.format(writer, "  -{c}, --{s}", .{ flag.shorthand.?, flag.name });
        } else {
            try std.fmt.format(writer, "      --{s}", .{flag.name});
        }

        // Print the argument/type name, if any
        const type_name = flag.value.argName();
        try writeArgument(flag, writer, type_name);

        // Insert a marker that will be later removed once final alignment is calculated;
        try writer.writeByte('\x00');
        // Update the maximum column width for all flags up to this point.
        max_len = @max(line_buffer.items.len, max_len);
        // Print the usage message with back-ticks stripped.
        try writeEscaped(flag.usage, writer);

        // Print the default value, if any
        if (flag.default) |default| {
            if (std.mem.eql(u8, type_name, "string")) {
                // Quote string values
                try std.fmt.format(writer, " (default \"{s}\")", .{default});
            } else if (!std.mem.eql(u8, type_name, "bool")) {
                // Omit "(default true)" for boolean flags
                try std.fmt.format(writer, " (default {s})", .{default});
            }
        }

        if (flag.deprecated) |str| {
            try std.fmt.format(writer, " (DEPRECATED: {s})", .{str});
        }

        try lines.append(try line_buffer.toOwnedSlice());
    }

    // Initialize a dynamically-sized buffer for writing to.
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    writer = buffer.writer();

    for (lines.items) |line| {
        // Find the index of the marker previously placed
        const sidx = std.mem.indexOfScalar(u8, line, '\x00') orelse unreachable;

        // Write up to the marker, then fill with spaces to uniform length
        try writer.writeAll(line[0..sidx]);
        try writer.writeByteNTimes(' ', max_len - sidx);

        // Wrap the usage text, prefixed with the same spacing
        const opts = string.WrapOpts{ .width = columns, .indent = max_len };
        string.wrapLinesTo(writer.any(), line[sidx + 1 ..], opts) catch {
            return error.OutOfMemory;
        };
        try writer.writeByte('\n');
    }

    return buffer.toOwnedSlice();
}

/// Prints usage text to the given writer with back-ticks stripped.
fn writeEscaped(text: []const u8, writer: std.ArrayList(u8).Writer) !void {
    var str = text;
    while (str.len > 0) {
        if (std.mem.indexOfScalar(u8, str, '`')) |i| {
            try writer.writeAll(str[0..i]);
            str = str[i + 1 ..];
            continue;
        }
        // No back-tick found, write the whole string and break
        try writer.writeAll(str);
        break;
    }
}

// Writes the argument section of the usage text.
fn writeArgument(flag: *Flag, writer: std.ArrayList(u8).Writer, type_name: []const u8) !void {
    var arg_name = flag.argName();
    // Ignore "bool" as a name, the presence of the flag is its value.
    if (std.mem.eql(u8, arg_name, "bool")) arg_name = "";

    // Formatting for when a value is optional and uses a default.
    if (flag.default_no_opt) |opt| {
        // Quote strings
        if (std.mem.eql(u8, type_name, "string")) {
            try std.fmt.format(writer, " [{s}=\"{s}\"]", .{ arg_name, opt });
        } else if (std.mem.eql(u8, type_name, "bool")) {
            // Omit for boolean flags
            if (!std.mem.eql(u8, opt, "true")) {
                try std.fmt.format(writer, " [{s}={s}]", .{ arg_name, opt });
            }
        } else if (std.mem.eql(u8, type_name, "count")) {
            // TODO: Remove this branch?
            if (!std.mem.eql(u8, opt, "+1")) {
                try std.fmt.format(writer, " [{s}={s}]", .{ arg_name, opt });
            }
        } else {
            try std.fmt.format(writer, " [{s}={s}]", .{ arg_name, opt });
        }
    } else if (arg_name.len > 0) {
        try std.fmt.format(writer, " <{s}>", .{arg_name});
    }
}

/// Parses the command-line arguments of the running application.
pub fn parseArgsFromCommandLine(self: *FlagSet) !void {
    // TODO: Error?
    if (self.parsed) return;
    const args = try std.process.argsAlloc(self.allocator);
    defer std.process.argsFree(self.allocator, args);
    return parseArgs(self, args[1..]);
}

/// Parses the specified command-line arguments.
/// The argument list should *NOT* contain the command/application name in the first position.
pub fn parseArgs(self: *FlagSet, arguments: ArgList) !void {
    if (arguments.len == 0) return;

    var list = try std.ArrayList([]const u8).initCapacity(self.allocator, arguments.len);
    defer list.deinit();

    // Create a mutable copy with the same backing storage
    var args = arguments;
    while (args.len > 0) {
        const s = args[0];
        args = args[1..];

        // Not a flag
        if (s.len <= 1 or s[0] != '-') {
            if (!self.interspersed) {
                // interspersed flags not allowed, so we reached the end
                list.appendAssumeCapacity(s);
                list.appendSliceAssumeCapacity(args);
                break;
            }
            // Otherwise append the non-flag argument to the list and loop
            list.appendAssumeCapacity(s);
            continue;
        }

        if (s[1] == '-') {
            // Check for "--", marking the end of optional arguments
            if (s.len == 2) {
                self.len_at_terminator = list.items.len;
                list.appendSliceAssumeCapacity(args);
                break;
            }
            args = try self.parseLongArg(s, args);
        } else {
            args = try self.parseShortArg(s, args);
        }
    }

    self.args = try list.toOwnedSlice();
    self.parsed = true;
}

/// When `ignore_unknown`  or skipping a flag, this function checks
/// the whether the following value was associated with the ignored
/// flag, and consumes it.
fn stripUnknownFlagValue(args: ArgList) ArgList {
    if (args.len == 0) {
        // --unknown
        return args;
    }

    const first = args[0];
    if (first.len > 0 and first[0] == '-') {
        // --unknown --next-flag
        return args;
    }

    if (args.len > 1) {
        // --unknown value (consumes value)
        return args[1..];
    }

    return &.{};
}

/// Parses a long-form (e.g. "--flag") argument.
fn parseLongArg(self: *FlagSet, str: []const u8, arguments: ArgList) !ArgList {
    var name = str[2..];
    if (name.len == 0 or name[0] == '-' or name[0] == '=') {
        self.printError("bad flag syntax: {s}\n", .{str});
        return error.CannotParse;
    }

    var args = arguments;
    var value: ?[]const u8 = null;

    if (std.mem.indexOfScalar(u8, name, '=')) |idx| {
        // --flag=value
        value = name[idx + 1 ..];
        name = name[0..idx];
    }

    const flag = self.getFlag(name, true) orelse {
        if (std.mem.eql(u8, "help", name)) {
            try self.printDefaults();
            // TODO: Create an error.Help to let caller know?
            // It would allow for the convention of "app --help cmd"
            return args;
        }

        // Recover parsing state and continue.
        if (self.ignore_unknown) {
            // --unknown=arg
            if (value != null) return args;
            return stripUnknownFlagValue(args);
        }

        self.printError("unknown flag: --{s}\n", .{name});
        return error.UnknownFlag;
    };

    if (value == null) {
        if (flag.default_no_opt) |default| {
            // --flag (no required value)
            value = default;
        } else if (args.len > 0) {
            // --flag value
            value = args[0];
            args = args[1..];
        } else {
            // --flag (missing required value)
            self.printError("flag missing required argument: --{s}\n", .{name});
            return error.MissingArgument;
        }
    }

    self.setValue(name, value.?) catch |err| {
        self.printError("invalid argument: \"{s}\" (--{s})\n", .{ value.?, name });
        return err;
    };
    return args;
}

/// Parses a short-form (e.g. "-f" or "-Syu") argument.
fn parseShortArg(self: *FlagSet, str: []const u8, arguments: ArgList) !ArgList {
    var args = arguments;
    var shorthands = str[1..];

    // shorthands can be in series without a dash (e.g. "pacman -Syu")
    while (shorthands.len > 0) {
        shorthands = try self.parseShortSingle(shorthands, arguments, &args);
    }
    return args;
}

/// Parses a short-form (e.g. "-f") argument.
fn parseShortSingle(self: *FlagSet, shorthands: []const u8, args: ArgList, out_args: *ArgList) ![]const u8 {
    out_args.* = args;
    var out_shorts = shorthands[1..];
    const c = shorthands[0];

    const flag = self.shorthands.get(c) orelse {
        if (c == 'h') {
            self.printDefaults() catch {};
            // TODO: Create an error.Help to let caller know?
            // It would allow for the convention of "app --help cmd"
            return out_shorts;
        }

        if (self.ignore_unknown) {
            // -f=value another
            // Don't lose "another" in this case
            if (shorthands.len > 2 and shorthands[1] == '=') {
                out_shorts = &.{};
                return out_shorts;
            }

            out_args.* = stripUnknownFlagValue(out_args.*);
            return out_shorts;
        }

        self.printError("unknown shorthand flag: {c} in {s}", .{ c, shorthands });
        return error.UnknownFlag;
    };

    var value: ?[]const u8 = null;
    if (shorthands.len > 2 and shorthands[1] == '=') {
        // -f=value
        value = shorthands[2..];
        out_shorts = &.{};
    } else if (flag.default_no_opt) |default| {
        // -f (argument is optional)
        value = default;
    } else if (shorthands.len > 1) {
        // -fvalue
        value = shorthands[1..];
        out_shorts = &.{};
    } else if (args.len > 0) {
        // -f value
        value = args[0];
        out_args.* = args[1..];
    } else {
        // -f (missing required argument)
        self.printError("flag needs an argument: {c} in -{s}\n", .{ c, shorthands });
        return error.MissingArgument;
    }

    if (flag.deprecated_shorthand) |msg| {
        const output = self.getOutput();
        try std.fmt.format(output, "flag shorthand -{c} has been deprecated: {s}\n", .{ c, msg });
    }

    self.setValue(flag.name, value.?) catch |err| {
        self.printError("invalid argument: \"{s}\" (-{c})\n", .{ value.?, c });
        return err;
    };

    return out_shorts;
}
