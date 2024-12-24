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

    const usages = try flags.flagUsages(allocator, 0);
    defer allocator.free(usages);
    std.debug.print("{s}", .{usages});
}
