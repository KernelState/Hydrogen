const std = @import("std");
const wl = @import("wayland").server.wl;
const wls = @import("wayland").server;
const wlr = @import("wlroots");
const xkb = @import("xkbcommon");
const Toplevel = @import("Toplevel.zig");
const Output = @import("Output.zig");
const Keyboard = @import("Keyboard.zig");

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
keyboards: wl.list.Head(Keyboard, .link) = undefined,

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

const log = std.log.scoped(.compositor);

pub fn init(self: *Compositor, gpa: std.mem.Allocator) !void {
    const server = try wl.Server.create();
    const loop = server.getEventLoop();
    self.* = .{
        .display_name = undefined,
        .gpa = gpa,
        .server = server,
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

    self.backend.events.new_output.add(&self.new_output);

    self.xdg_shell.events.new_toplevel.add(&self.new_xdg_toplevel);
    self.xdg_shell.events.new_popup.add(&self.new_xdg_popup);
    self.toplevels.init();

    self.backend.events.new_input.add(&self.new_input);
    self.seat.events.request_set_cursor.add(&self.request_set_cursor);
    self.seat.events.request_set_selection.add(&self.request_set_selection);
    self.keyboards.init();

    self.cursor.attachOutputLayout(self.output_layout);
    try self.cursor_mgr.load(1);
    self.cursor.events.motion.add(&self.cursor_motion);
    self.cursor.events.motion_absolute.add(&self.cursor_motion_absolute);
    self.cursor.events.button.add(&self.cursor_button);
    self.cursor.events.axis.add(&self.cursor_axis);
    self.cursor.events.frame.add(&self.cursor_frame);

    _ = try wlr.Compositor.create(self.server, 6, self.renderer);
    _ = try wlr.Subcompositor.create(self.server);
    _ = try wlr.DataDeviceManager.create(self.server);
    self.cursor.setXcursor(self.cursor_mgr, "left_ptr");

    log.info("server initialized successfully", .{});
}

pub fn newOutput(listener: *wl.Listener(*wlr.Output), data: *wlr.Output) void {
    const self: *Compositor = @fieldParentPtr("new_output", listener);
    Output.create(self, data) catch |err| {
        log.err("Failed to create output: {any}", .{err});
        return;
    };
}

pub fn cursorFrame(
    listener: *wl.Listener(*wlr.Cursor),
    _: *wlr.Cursor,
) void {
    const self: *Compositor = @fieldParentPtr("cursor_frame", listener);
    self.seat.pointerNotifyFrame();
}

pub fn cursorAxis(
    listener: *wl.Listener(*wlr.Pointer.event.Axis),
    event: *wlr.Pointer.event.Axis,
) void {
    const self: *Compositor = @fieldParentPtr("cursor_axis", listener);
    self.seat.pointerNotifyAxis(
        event.time_msec,
        event.orientation,
        event.delta,
        event.delta_discrete,
        event.source,
        event.relative_direction,
    );
}

pub fn cursorButton(
    listener: *wl.Listener(*wlr.Pointer.event.Button),
    event: *wlr.Pointer.event.Button,
) void {
    const self: *Compositor = @fieldParentPtr("cursor_button", listener);
    if (event.state == .released) {
        self.cursor_mode = .passthrough;
    } else if (self.viewAt(self.cursor.x, self.cursor.y)) |t| {
        self.focusView(t);
    }
    _ = self.seat.pointerNotifyButton(
        event.time_msec,
        event.button,
        event.state,
    );
}

pub fn cursorMotion(
    listener: *wl.Listener(*wlr.Pointer.event.Motion),
    event: *wlr.Pointer.event.Motion,
) void {
    const self: *Compositor = @fieldParentPtr("cursor_motion", listener);
    self.cursor.move(event.device, event.delta_x, event.delta_y);
    self.seat.pointerNotifyMotion(event.time_msec, self.cursor.x, self.cursor.y);
}

pub fn cursorMotionAbsolute(
    listener: *wl.Listener(*wlr.Pointer.event.MotionAbsolute),
    event: *wlr.Pointer.event.MotionAbsolute,
) void {
    const self: *Compositor = @fieldParentPtr("cursor_motion_absolute", listener);
    self.cursor.warpAbsolute(event.device, event.x, event.y);
    self.seat.pointerNotifyMotion(event.time_msec, self.cursor.x, self.cursor.y);
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
    const self: *Compositor = @fieldParentPtr("new_input", listener);
    switch (data.type) {
        .pointer => self.cursor.attachInputDevice(data),
        .keyboard => Keyboard.create(self, data) catch |err| {
            log.err("Failed to create keyboard: {any}", .{err});
            return;
        },
        else => {},
    }
    self.seat.setCapabilities(.{ .pointer = true, .keyboard = true });
}

pub fn handleKeybind(self: *Compositor, key: xkb.Keysym) bool {
    switch (key) {
        xkb.Keysym.Escape => self.server.terminate(),
        else => {
            log.warn("Unknown compositor/shell keybind {}", .{@intFromEnum(key)});
            return false;
        },
    }
    return true;
}

pub fn newXdgToplevel(
    listener: *wl.Listener(*wlr.XdgToplevel),
    data: *wlr.XdgToplevel,
) void {
    const self: *Compositor = @fieldParentPtr("new_xdg_toplevel", listener);

    Toplevel.create(self, data) catch |err| {
        log.err("Failed to create toplevel: {any}", .{err});
        return;
    };
}

pub fn viewAt(self: *Compositor, lx: f64, ly: f64) ?*Toplevel {
    var sx: f64 = undefined;
    var sy: f64 = undefined;
    if (self.scene.tree.node.at(lx, ly, &sx, &sy)) |n| {
        if (n.type != .buffer) return null;

        var it: ?*wlr.SceneTree = n.parent;
        while (it) |p| : (it = p.node.parent) {
            if (@as(?*Toplevel, @ptrCast(@alignCast(p.node.data)))) |toplevel| {
                return toplevel;
            }
        }
    }
    return null;
}

pub fn focusView(self: *Compositor, view: *Toplevel) void {
    log.info("focusing view", .{});
    self.seat.keyboardNotifyClearFocus();
    self.seat.pointerNotifyClearFocus();
    if (self.seat.keyboard_state.focused_surface) |p| {
        if (p == view.toplevel.base.surface) return;
        if (wlr.XdgSurface.tryFromWlrSurface(p)) |xs| {
            _ = xs.role_data.toplevel.?.setActivated(false);
        }
    }
    view.scene_tree.node.raiseToTop();
    view.link.remove();
    self.toplevels.prepend(view);

    _ = view.toplevel.setActivated(true);

    //const scene_buffer = wlr.SceneBuffer.fromNode(&view.scene_tree.node);
    //const scene_surface = wlr.SceneSurface.tryFromBuffer(scene_buffer) orelse return;

    const keyboard = self.seat.getKeyboard() orelse return;
    self.seat.keyboardNotifyEnter(
        view.toplevel.base.surface,
        keyboard.keycodes[0..keyboard.num_keycodes],
        &keyboard.modifiers,
    );
    self.seat.pointerNotifyEnter(
        view.toplevel.base.surface,
        self.cursor.x,
        self.cursor.y,
    );
    log.info("Focused window {s}", .{if (view.toplevel.title) |t| t else "Unknown"});
}

pub fn newXdgPopup(
    listener: *wl.Listener(*wlr.XdgPopup),
    data: *wlr.XdgPopup,
) void {
    _ = listener;
    _ = data;
}

pub fn run(self: *Compositor) !void {
    var buf: [11]u8 = undefined;
    self.display_name = try self.server.addSocketAuto(&buf);
    log.info("Running on display: {s}", .{self.display_name});
    try self.backend.start();
    self.server.run();
}

pub fn deinit(self: *Compositor) void {
    log.info("Exiting Compositor", .{});
    self.server.destroyClients();

    self.cursor_motion.link.remove();
    self.cursor_motion_absolute.link.remove();
    self.cursor_button.link.remove();
    self.cursor_axis.link.remove();
    self.cursor_frame.link.remove();
    self.new_input.link.remove();
    self.new_output.link.remove();
    self.new_xdg_popup.link.remove();
    self.new_xdg_toplevel.link.remove();
    self.request_set_cursor.link.remove();
    self.request_set_selection.link.remove();

    self.backend.destroy();
    self.server.destroy();
}
