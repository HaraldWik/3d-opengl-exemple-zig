const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sdl_mod = b.dependency("sdl3", .{ .target = target, .optimize = optimize, .ext_image = true }).module("sdl3");

    const gl_mod = @import("zigglgen").generateBindingsModule(b);
    // .version = .@"4.6",
    // .profile = .core,
    // .extensions = &.{ .ARB_clip_control, .NV_scissor_exclusive },

    const numz_mod = b.dependency("numz", .{ .target = target, .optimize = optimize }).module("numz");

    const exe = b.addExecutable(.{
        .name = "GameEngineZigTest",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "sdl3", .module = sdl_mod },
                .{ .name = "gl", .module = gl_mod },
                .{ .name = "numz", .module = numz_mod },
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

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}
