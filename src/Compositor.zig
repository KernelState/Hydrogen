const std = @import("std");
const wl = @import("wayland").server.wl;
const wls = @import("wayland").server;
const wlr = @import("wlroots");
const Toplevel = @import("Toplevel.zig");

gpa: std.mem.Allocator,

display_name: [:0]const u8,
server: *wl.Server,
backend: *wlr.Backend,
renderer: *wlr.Renderer,
scene: *wlr.Scene,
wlr_allocator: *wlr.Allocator,

output_layout: *wlr.OutputLayout,
scene_output_layout: *wlr.SceneOutputLayout,
new_output: wl.Listener(*wlr.Output) = .init(newOutput),

xdg_shell: *wlr.XdgShell,
new_xdg_toplevel: wl.Listener(*wlr.XdgToplevel) = .init(newXdgToplevel),
new_xdg_popup: wl.Listener(*wlr.XdgPopup) = .init(newXdgPopup),
toplevels: wl.list.Head(Toplevel, .link) = undefined,

seat: *wlr.Seat,
new_input: wl.Listener(*wlr.InputDevice) = .init(newInput),
request_set_cursor: wl.Listener(*wlr.Seat.event.RequestSetCursor) = .init(requestSetCursor),
request_set_selection: wl.Listener(*wlr.Seat.event.RequestSetSelection) = .init(requestSetSelection),
keyboards: wl.list.Head(wlr.Keyboard, .link) = undefined,

cursor: *wlr.Cursor,
cursor_mgr: *wlr.XcursorManager,
cursor_motion: wl.Listener(*wlr.Pointer.event.Motion) = .init(cursorMotion),
cursor_motion_absolute: wl.Listener(*wlr.Pointer.event.MotionAbsolute) = .init(cursorMotionAbsolute),
cursor_button: wl.Listener(*wlr.Pointer.event.Button) = .init(cursorButton),
cursor_axis: wl.Listener(*wlr.Pointer.event.Axis) = .init(cursorAxis),
cursor_frame: wl.Listener(*wlr.Cursor) = .init(cursorFrame),

cursor_mode: enum { passthrough, move, resize } = .passthrough,
grabbed_view: ?*Toplevel = null,
grab_x: f64 = 0,
grab_y: f64 = 0,
grab_box: wlr.Box = undefined,
resize_edges: wlr.Edges = .{},

const Compositor = @This();

pub fn init(self: *Compositor, gpa: std.mem.Allocator) !void {
    const loop = self.server.getEventLoop();
    self.* = .{
        .display_name = undefined,
        .gpa = gpa,
        .server = try .create(),
        .backend = try wlr.Backend.autocreate(loop, null),
        .renderer = try wlr.Renderer.autocreate(self.backend),
        .wlr_allocator = try wlr.Allocator.autocreate(self.backend, self.renderer),
        .scene = try wlr.Scene.create(),
        .output_layout = try wlr.OutputLayout.create(self.server),
        .scene_output_layout = try self.scene.attachOutputLayout(self.output_layout),

        .xdg_shell = try wlr.XdgShell.create(self.server, 2),
        .seat = try wlr.Seat.create(self.server, "default"),
        .cursor = try wlr.Cursor.create(),
        .cursor_mgr = try wlr.XcursorManager.create(null, 25),
    };
    try self.renderer.initServer(self.server);

    _ = try wlr.Compositor.create(self.server, 6, self.renderer);
    _ = try wlr.Subcompositor.create(self.server);
    _ = try wlr.DataDeviceManager.create(self.server);
}

pub fn newOutput(listener: *wl.Listener(*wlr.Output), data: *wlr.Output) void {
    _ = listener;
    _ = data;
}

pub fn cursorFrame(
    listener: *wl.Listener(*wlr.Cursor),
    data: *wlr.Cursor,
) void {
    _ = listener;
    _ = data;
}

pub fn cursorAxis(
    listener: *wl.Listener(*wlr.Pointer.event.Axis),
    data: *wlr.Pointer.event.Axis,
) void {
    _ = listener;
    _ = data;
}

pub fn cursorButton(
    listener: *wl.Listener(*wlr.Pointer.event.Button),
    data: *wlr.Pointer.event.Button,
) void {
    _ = listener;
    _ = data;
}

pub fn cursorMotion(
    listener: *wl.Listener(*wlr.Pointer.event.Motion),
    data: *wlr.Pointer.event.Motion,
) void {
    _ = listener;
    _ = data;
}

pub fn cursorMotionAbsolute(
    listener: *wl.Listener(*wlr.Pointer.event.MotionAbsolute),
    data: *wlr.Pointer.event.MotionAbsolute,
) void {
    _ = listener;
    _ = data;
}

pub fn requestSetSelection(
    listener: *wl.Listener(*wlr.Seat.event.RequestSetSelection),
    data: *wlr.Seat.event.RequestSetSelection,
) void {
    _ = listener;
    _ = data;
}

pub fn requestSetCursor(
    listener: *wl.Listener(*wlr.Seat.event.RequestSetCursor),
    data: *wlr.Seat.event.RequestSetCursor,
) void {
    _ = listener;
    _ = data;
}

pub fn newInput(
    listener: *wl.Listener(*wlr.InputDevice),
    data: *wlr.InputDevice,
) void {
    _ = listener;
    _ = data;
}

pub fn newXdgToplevel(
    listener: *wl.Listener(*wlr.XdgToplevel),
    data: *wlr.XdgToplevel,
) void {
    _ = listener;
    _ = data;
}

pub fn newXdgPopup(
    listener: *wl.Listener(*wlr.XdgPopup),
    data: *wlr.XdgPopup,
) void {
    _ = listener;
    _ = data;
}

// TODO: make it at least walk, this aint moving an inch
pub fn run(self: *Compositor) !void {
    var buf: [11]u8 = undefined;
    self.display_name = try self.server.addSocketAuto(&buf);
    try self.backend.start();
    self.server.run();
}

pub fn deinit(self: *Compositor) void {
    self.cursor_mgr.destroy();
    self.cursor.destroy();
    self.seat.destroy();
    self.output_layout.destroy();
    // TODO: deinitialize/disconnect all outputs
    self.wlr_allocator.destroy();
    self.renderer.destroy();
    self.backend.destroy();
    self.server.destroyClients();
    self.server.destroy();
}
