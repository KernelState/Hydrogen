const std = @import("std");

const Scanner = @import("wayland").Scanner;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const scanner = Scanner.create(b, .{});

    scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");
    scanner.addSystemProtocol("stable/tablet/tablet-v2.xml");
    scanner.addSystemProtocol("staging/color-management/color-management-v1.xml");

    scanner.generate("wl_compositor", 4);
    scanner.generate("wl_subcompositor", 1);
    scanner.generate("wl_shm", 1);
    scanner.generate("wl_output", 4);
    scanner.generate("wl_seat", 7);
    scanner.generate("wl_data_device_manager", 3);
    scanner.generate("xdg_wm_base", 2);
    scanner.generate("zwp_tablet_manager_v2", 1);
    scanner.generate("wp_color_manager_v1", 2);

    const wayland = b.createModule(.{ .root_source_file = scanner.result });
    const wlroots = b.dependency("wlroots", .{}).module("wlroots");
    const pixman = b.dependency("pixman", .{}).module("pixman");
    wlroots.addImport("wayland", wayland);
    wlroots.addImport("pixman", pixman);
    wlroots.resolved_target = target;
    wlroots.linkSystemLibrary("wlroots-0.20", .{});

    const exe = b.addExecutable(.{
        .name = "Hydrogen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
            },
        }),
    });

    exe.root_module.addImport("wayland", wayland);
    exe.root_module.addImport("wlroots", wlroots);

    exe.root_module.linkSystemLibrary("wayland-server", .{});
    exe.root_module.linkSystemLibrary("xkbcommon", .{});
    exe.root_module.linkSystemLibrary("pixman-1", .{});

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}
