const std = @import("std");

pub const AnyValue = @import("AnyValue.zig");
pub const Value = @import("value.zig").Value;
pub const Flag = @import("Flag.zig");
pub const FlagSet = @import("FlagSet.zig");

test "all" {
    const string = @import("string.zig");
    const value = @import("value.zig");
    const wrapper = @import("wrapper.zig");

    std.testing.refAllDecls(string);
    std.testing.refAllDecls(value);
    std.testing.refAllDecls(wrapper);

    std.testing.refAllDecls(AnyValue);
    std.testing.refAllDecls(Flag);
    std.testing.refAllDecls(FlagSet);
}
