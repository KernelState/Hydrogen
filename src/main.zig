const std = @import("std");
const Compositor = @import("Compositor.zig");

pub fn main(init: std.process.Init) !void {
    std.debug.print("Hello, world\n", .{});
    _ = init;
}
