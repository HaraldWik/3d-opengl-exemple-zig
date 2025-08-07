const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sdl = b.dependency("sdl", .{
        .target = target,
        .optimize = optimize,
        .lto = optimize != .Debug,
        .preferred_linkage = .dynamic,
    });
    const sdl_translate_c = b.addTranslateC(.{
        .root_source_file = sdl.path("include/SDL3/SDL.h"),
        .target = target,
        .optimize = optimize,
    });
    sdl_translate_c.addIncludePath(sdl.path("include"));

    const gl_mod = @import("zigglgen").generateBindingsModule(b, .{
        .api = .gl,
        .version = .@"4.1",
        .profile = .core,
        .extensions = &.{ .ARB_clip_control, .NV_scissor_exclusive },
    });

    const numz_mod = b.dependency("numz", .{ .target = target, .optimize = optimize }).module("numz");

    const exe = b.addExecutable(.{
        .name = "GameEngineZigTest",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "sdl", .module = sdl_translate_c.createModule() },
                .{ .name = "gl", .module = gl_mod },
                .{ .name = "numz", .module = numz_mod },
            },
            .link_libc = true,
        }),
    });

    exe.root_module.linkSystemLibrary("SDL3_image", .{}); // This is not a good way of doing this but currently as of writing there is no 'linkSystemLibrary' function for the translate c ¯\_(ツ)_/¯

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
