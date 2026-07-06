const std = @import("std");
const wl = @import("wayland").server.wl;
const wls = @import("wayland").server;
const wlr = @import("wlroots");
const Compositor = @import("Compositor.zig");
const log = Compositor.log;

comp: *Compositor,
link: wl.list.Link = undefined,
toplevel: *wlr.XdgToplevel,
scene_tree: *wlr.SceneTree,

x: i32 = 0,
y: i32 = 0,

commit: wl.Listener(*wlr.Surface) = .init(onCommit),
map: wl.Listener(void) = .init(onMap),
unmap: wl.Listener(void) = .init(onUnmap),
destroy: wl.Listener(void) = .init(onDestroy),
request_move: wl.Listener(*wlr.XdgToplevel.event.Move) = .init(onRequestMove),
request_resize: wl.Listener(*wlr.XdgToplevel.event.Resize) = .init(onRequestResize),

const Toplevel = @This();

/// Does not add itself to the toplevels list on creation.
/// Gets added when mapped.
///
/// See https://codeberg.org/ifreund/zig-wlroots/src/branch/master/tinywl/tinywl.zig
pub fn create(comp: *Compositor, toplevel: *wlr.XdgToplevel) !void {
    const self = try comp.gpa.create(Toplevel);
    errdefer comp.gpa.destroy(self);
    self.* = .{ .comp = comp, .toplevel = toplevel, .scene_tree = try comp.scene.tree.createSceneXdgSurface(toplevel.base) };
    self.scene_tree.node.data = self;
    toplevel.base.data = self.scene_tree;

    toplevel.base.surface.events.commit.add(&self.commit);
    toplevel.base.surface.events.map.add(&self.map);
    toplevel.base.surface.events.unmap.add(&self.unmap);
    toplevel.events.destroy.add(&self.destroy);
    toplevel.events.request_move.add(&self.request_move);
    toplevel.events.request_resize.add(&self.request_resize);
}

pub fn onCommit(
    listener: *wl.Listener(*wlr.Surface),
    _: *wlr.Surface,
) void {
    const self: *Toplevel = @fieldParentPtr("commit", listener);
    if (self.toplevel.base.initial_commit) {
        _ = self.toplevel.setSize(0, 0);
    }
}

pub fn onMap(listener: *wl.Listener(void)) void {
    const self: *Toplevel = @fieldParentPtr("map", listener);
    self.comp.toplevels.prepend(self);
    self.comp.focusView(self);
}

pub fn onUnmap(listener: *wl.Listener(void)) void {
    const self: *Toplevel = @fieldParentPtr("unmap", listener);
    self.link.remove();
}

pub fn onDestroy(listener: *wl.Listener(void)) void {
    const self: *Toplevel = @fieldParentPtr("destroy", listener);

    self.commit.link.remove();
    self.unmap.link.remove();
    self.map.link.remove();
    self.destroy.link.remove();
    self.request_move.link.remove();
    self.request_resize.link.remove();

    self.comp.gpa.destroy(self);
}

pub fn onRequestMove(
    listener: *wl.Listener(*wlr.XdgToplevel.event.Move),
    event: *wlr.XdgToplevel.event.Move,
) void {
    const self: *Toplevel = @fieldParentPtr("request_move", listener);
    self.comp.grabbed_view = self;
    self.comp.cursor_mode = .move;
    self.comp.grab_x = self.comp.cursor.x - @as(f64, @floatFromInt(self.x));
    self.comp.grab_y = self.comp.cursor.y - @as(f64, @floatFromInt(self.y));
    self.comp.grab_event = .{ .move = event.* };
}

pub fn onRequestResize(
    listener: *wl.Listener(*wlr.XdgToplevel.event.Resize),
    event: *wlr.XdgToplevel.event.Resize,
) void {
    const self: *Toplevel = @fieldParentPtr("request_resize", listener);
    self.comp.grabbed_view = self;
    self.comp.cursor_mode = .resize;
    self.comp.resize_edges = event.edges;
    self.comp.grab_event = .{ .resize = event.* };
    self.comp.grab_x = self.comp.cursor.x;
    self.comp.grab_y = self.comp.cursor.y;
    const box = self.toplevel.base.geometry;
    self.comp.grab_box = .{
        .width = box.width,
        .height = box.height,
        .x = self.x,
        .y = self.y
    };
}

pub fn syncResize(self: *Toplevel) void {
    const ev = self.comp.grab_event.?.resize;
    const c = self.comp.cursor;
    const box = self.comp.grab_box;
    const w = box.width;
    const h = box.height;
    var dw: f64 = 0.0;
    var dh: f64 = 0.0;

    if (ev.edges.right) {
        dw = c.x-self.comp.grab_x;
    } else if (ev.edges.left) {
        dw = self.comp.grab_x-c.x;
        self.x = box.x-@as(i32, @intFromFloat(self.comp.grab_x-c.x));
    }

    if (ev.edges.bottom) {
        dw = c.y-self.comp.grab_y;
    } else {
        dh = self.comp.grab_y-c.y;
        self.y = box.y-@as(i32, @intFromFloat(self.comp.grab_y-c.y));
    }

    const new_width = @as(i32, @intFromFloat(@max(w+dw, 1)));
    const new_height = @as(i32, @intFromFloat(@max(h+dh, 1.0)));
    self.scene_tree.node.setPosition(self.x, self.y);
    _ = self.toplevel.setSize(new_width, new_height);
}

pub fn syncMove(self: *Toplevel) void {
    self.x = @as(i32, @intFromFloat(self.comp.cursor.x - self.comp.grab_x));
    self.y = @as(i32, @intFromFloat(self.comp.cursor.y - self.comp.grab_y));
    self.scene_tree.node.setPosition(self.x, self.y);
}
