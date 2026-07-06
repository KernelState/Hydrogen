const std = @import("std");
const wl = @import("wayland").server.wl;
const wls = @import("wayland").server;
const wlr = @import("wlroots");
const Compositor = @import("Compositor.zig");

comp: *Compositor,
link: wl.list.Link = undefined,
toplevel: *wlr.XdgToplevel,
scene_tree: *wlr.SceneTree,

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
    data: *wlr.XdgToplevel.event.Move,
) void {
    _ = listener;
    _ = data;
}

pub fn onRequestResize(
    listener: *wl.Listener(*wlr.XdgToplevel.event.Resize),
    data: *wlr.XdgToplevel.event.Resize,
) void {
    _ = listener;
    _ = data;
}
