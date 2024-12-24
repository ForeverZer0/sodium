const std = @import("std");

pub const AnyValue = @import("AnyValue.zig");
pub const Value = @import("value.zig").Value;
pub const Flag = @import("Flag.zig");
pub const FlagSet = @import("FlagSet.zig");

test "all" {
    std.testing.refAllDecls(@import("string.zig"));
    std.testing.refAllDecls(@import("value.zig"));
    std.testing.refAllDecls(@import("wrapper.zig"));

    std.testing.refAllDecls(AnyValue);
    std.testing.refAllDecls(Flag);
    std.testing.refAllDecls(FlagSet);
    std.testing.refAllDecls(@import("flagset_test.zig"));
}
