const std = @import("std");
const allocator = std.testing.allocator;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const FlagSet = @import("FlagSet.zig");

test "FlagSet" {
    var flags = try FlagSet.init(allocator, "sodium");
    defer flags.deinit();

    const LogLevel = enum { none, info, warning, errors, trace };
    const Vec3 = @Vector(3, f32);

    var verbose: bool = false;
    var archive: bool = false;
    var recursive: bool = false;
    var sync: bool = false;
    var follow: bool = false;
    var path: []const u8 = &.{};
    var loglevel: LogLevel = .warning;
    var direction: Vec3 = undefined;

    try flags.addFlag(bool, "verbose", 'v', "verbose output", &verbose);
    try flags.addFlag(bool, "archive", 'a', "preserve file permissions", &archive);
    try flags.addFlag(bool, "recursive", 'r', "search directories recursively", &recursive);
    try flags.addFlag(bool, "sync", 's', "sync database before executing", &sync);
    try flags.addFlag(bool, "follow-links", 'f', "follow symbolic links", &follow);
    try flags.addFlag([]const u8, "output", 'o', "selects the `filename` of the output", &path);
    try flags.addFlag(LogLevel, "log-level", null, "enable logging with optional `level`", &loglevel);
    try flags.setDefaultNoOpt("log-level", "warning");
    try flags.addFlagDefault(Vec3, "direction", 'd', "the world up direction vector", &direction, "0,1,0");

    // Parse arguments
    try flags.parseArgs(&[_][]const u8{ "-vrrs", "argument", "--output", "~/filename.ext", "--", "|", "echo", "'hello world'" });

    // joined shorthand arguments
    try expectEqual(true, verbose);
    try expectEqual(false, archive);
    try expectEqual(true, recursive);
    try expectEqual(true, sync);
    try expectEqual(false, follow);

    // Default value being set without parsed from arguments
    try expectEqual(Vec3{ 0, 1, 0 }, direction);
    try expectEqual(false, flags.isChanged("direction"));

    // occurrence count
    try expectEqual(2, flags.getOccurrenceCount("recursive"));
    try expectEqual(true, flags.isChanged("recursive"));
    // length at terminator
    try expectEqual(1, flags.args_before_terminator.?);

    // non-option arguments (interspersed)
    try expectEqual(4, flags.args.len);
    const args = [_][]const u8{ "argument", "|", "echo", "hello world" };
    for (0.., flags.args) |i, arg| try expectEqualStrings(args[i], arg);

    const usage_text = try flags.usageText(allocator, 0);
    defer allocator.free(usage_text);

    // argument name extraction
    try expectEqual(true, std.mem.indexOf(u8, usage_text, "output <filename>") != null);
    // argument name extraction with optional flag value
    try expectEqual(true, std.mem.indexOf(u8, usage_text, "log-level [level=\"warning\"]") != null);
    // visual test, just ensure text alignment looks correct
    std.debug.print("\n########## VISUAL ALIGNMENT ###########\n\n{s}\n#######################################\n", .{usage_text});
}
