const std = @import("std");
const wl = @import("wayland").server.wl;
const wls = @import("wayland").server;
const wlr = @import("wlroots");

gpa: std.mem.Allocator,
io: std.Io,

display_name: [:0]const u8,
server: *wl.Server,
backend: *wlr.Backend,
renderer: *wlr.Renderer,
scene: *wlr.Scene,
wlr_allocator: *wlr.Allocator,

output_layout: *wlr.OutputLayout,
scene_output_layout: *wlr.SceneOutputLayout,
//new_output: wl.Listener(*wlr.Output) = .init(newOutput),
//
xdg_shell: *wlr.XdgShell,
//new_xdg_toplevel: wl.Listener(*wlr.XdgToplevel) = .init(newXdgToplevel),
//new_xdg_popup: wl.Listener(*wlr.XdgPopup) = .init(newXdgPopup),
//toplevels: wl.list.Head(Toplevel, .link) = undefined,
//
seat: *wlr.Seat,
//new_input: wl.Listener(*wlr.InputDevice) = .init(newInput),
//request_set_cursor: wl.Listener(*wlr.Seat.event.RequestSetCursor) = .init(requestSetCursor),
//request_set_selection: wl.Listener(*wlr.Seat.event.RequestSetSelection) = .init(requestSetSelection),
//keyboards: wl.list.Head(Keyboard, .link) = undefined,
//
cursor: *wlr.Cursor,
cursor_mgr: *wlr.XcursorManager,
//cursor_motion: wl.Listener(*wlr.Pointer.event.Motion) = .init(cursorMotion),
//cursor_motion_absolute: wl.Listener(*wlr.Pointer.event.MotionAbsolute) = .init(cursorMotionAbsolute),
//cursor_button: wl.Listener(*wlr.Pointer.event.Button) = .init(cursorButton),
//cursor_axis: wl.Listener(*wlr.Pointer.event.Axis) = .init(cursorAxis),
//cursor_frame: wl.Listener(*wlr.Cursor) = .init(cursorFrame),

cursor_mode: enum { passthrough, move, resize } = .passthrough,
grabbed_view: ?*Toplevel = null,
grab_x: f64 = 0,
grab_y: f64 = 0,
grab_box: wlr.Box = undefined,
resize_edges: wlr.Edges = .{},

const Compositor = @This();

pub fn init(self: *Compositor, gpa: std.mem.Allocator, io: std.Io) !void {
    self.* = .{
        .display_name = undefined,
        .gpa = gpa,
        .io = io,
        .server = try .create(),
    };
    const loop = self.server.getEventLoop();
    self.backend = try wlr.Backend.autocreate(loop, null);
    self.renderer = try wlr.Renderer.autocreate(backend);
    self.wlr_allocator = try wlr.Allocator.autocreate(backend, renderer);
    self.scene = try wlr.Scene.create();
    self.output_layout = try wlr.OutputLayout.create(self.server);
    self.scene_output_layout = try self.scene.attachOutputLayout(self.output_layout);

    self.xdg_shell = try wlr.XdgShell.create(self.Server, 2);
    self.seat = wlr.Seat.create(self.server, "default");
    self.cursor = wlr.Cursor.create();
    self.cursor_mgr = wlr.XcursorManager.create(null, 24);
    try self.renderer.initServer(self.server);

    _ = try wlr.Compositor.create(self.server, 6, self.renderer);
    _ = try wlr.Subcompositor.create(self.server);
    _ = try wlr.DataDeviceManager.create(self.server);
}

// TODO: make it at least walk, this aint moving an inch
pub fn run(self: *Compositor) !void {
    var buf: [11]u8 = undefined;
    self.display_name = try self.server.addSocketAuto(&buf);
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
