const std = @import("std");
const Compositor = @import("Compositor.zig");

pub fn main(init: std.process.Init) !void {
    var comp: Compositor = undefined;
    try comp.init(init.gpa, init.io);
    defer comp.deinit();
    try comp.run();
    std.debug.print("Running compositor\n", .{});
}
