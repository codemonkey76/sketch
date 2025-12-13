const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const arcade_lib = b.dependency("arcade_lib", .{
        .target = target,
    });

    const arcade_lib_mod = arcade_lib.module("arcade_lib");

    const raylib = b.dependency("raylib_zig", .{
        .target = target,
    });
    const raylib_mod = raylib.module("raylib");

    const mod = b.addModule("sketch", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "raylib", .module = raylib_mod },
            .{ .name = "arcade_lib", .module = arcade_lib_mod },
        },
    });

    const exe = b.addExecutable(.{
        .name = "sketch",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "sketch", .module = mod },
                .{ .name = "raylib", .module = raylib_mod },
                .{ .name = "arcade_lib", .module = arcade_lib_mod },
            },
        }),
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
