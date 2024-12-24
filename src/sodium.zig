const std = @import("std");

test "all" {
    const string = @import("string.zig");
    std.testing.refAllDecls(string);
}
