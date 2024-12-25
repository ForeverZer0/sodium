const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Library
    const lib = b.addStaticLibrary(.{
        .name = "sodium",
        .root_source_file = b.path("src/sodium.zig"),
        .target = target,
        .optimize = optimize,
        .version = .{ .major = 0, .minor = 1, .patch = 0 },
    });
    b.installArtifact(lib);

    // Unit tests
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/sodium.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_lib_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
