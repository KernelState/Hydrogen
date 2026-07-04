const std = @import("std");
const Compositor = @import("Compositor.zig");

pub fn main(init: std.process.Init) !void {
    std.debug.print("Hello, world\n", .{});
    var comp: Compositor = undefined;
    try comp.init(init.gpa);
    defer comp.deinit();
    try comp.run();
}
