const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Export as a module
    _ = b.addModule("sodium", .{
        .root_source_file = b.path("src/sodium.zig"),
        .optimize = optimize,
        .target = target,
    });

    // Unit tests
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/sodium.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&unit_tests.step);
}
