const std = @import("std");
const wl = @import("wayland").server.wl;
const wls = @import("wayland").server;
const wlr = @import("wlroots");
const Compositor = @import("Compositor.zig");

comp: *Compositor,

const Shell = @This();

pub fn create(comp: *Compositor) !Shell {
    return .{
        .comp = comp,
    };
}

pub fn destroy(self: *Shell) void {
    _ = self;
}
