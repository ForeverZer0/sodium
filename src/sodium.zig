const std = @import("std");

test "all" {
    const string = @import("string.zig");
    const value = @import("value.zig");

    std.testing.refAllDecls(string);
    std.testing.refAllDecls(value);
}
