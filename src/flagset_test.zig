const std = @import("std");
const allocator = std.testing.allocator;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const FlagSet = @import("FlagSet.zig");

test "FlagSet" {
    var flags = try FlagSet.init(allocator, "sodium");
    defer flags.deinit();

    const LogLevel = enum { trace, errors, warnings, info, none };

    var output: []const u8 = "";
    var verbose: bool = false;
    var log_level: LogLevel = .none;

    try flags.addFlag([]const u8, "output", 'o', "selects the output `filename`", &output);
    try flags.setDefault("output", "~/filename.ext");
    try expectEqualStrings(output, "~/filename.ext");

    try flags.addFlag(bool, "verbose", 'v', "print more information", &verbose);

    try flags.addFlag(LogLevel, "log-level", null, "sets the amount of detail in the log", &log_level);
    try expectEqual(LogLevel.none, log_level);
    try flags.setValue("log-level", "warnings");
    try expectEqual(LogLevel.warnings, log_level);
}

test "shorthand joined" {
    var flags = try FlagSet.init(allocator, "sodium");
    defer flags.deinit();

    var verbose: bool = false;
    var archive: bool = false;
    var recursive: bool = false;
    var sync: bool = false;
    var follow: bool = false;

    try flags.addFlag(bool, "verbose", 'v', "verbose output", &verbose);
    try flags.addFlag(bool, "archive", 'a', "preserve file permissions", &archive);
    try flags.addFlag(bool, "recursive", 'r', "search directories recursively", &recursive);
    try flags.addFlag(bool, "sync", 's', "sync database before executing", &sync);
    try flags.addFlag(bool, "follow-links", 'f', "follow symbolic links", &follow);

    try flags.parseArgs(&[_][]const u8{ "-vrs", "--", "|", "echo", "'hello world'" });

    try expectEqual(true, verbose);
    try expectEqual(false, archive);
    try expectEqual(true, recursive);
    try expectEqual(true, sync);
    try expectEqual(false, follow);

    const usages = try flags.flagUsages(allocator, 0);
    defer allocator.free(usages);
    std.debug.print("{s}", .{usages});

    for (flags.args) |arg| std.debug.print("{s}\n", .{arg});
}
