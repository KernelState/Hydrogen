const std = @import("std");
const wl = @import("wayland").server.wl;
const wls = @import("wayland").server;
const wlr = @import("wlroots");
const Compositor = @import("Compositor.zig");
const log = Compositor.log;

popup: *wlr.XdgPopup,
comp: *Compositor,

commit: wl.Listener(*wlr.Surface) = .init(onCommit),
destroy: wl.Listener(void) = .init(onDestroy),

const Popup = @This();

pub fn create(comp: *Compositor, popup: *wlr.XdgPopup) !void {
    const parent = wlr.XdgSurface.tryFromWlrSurface(popup.parent.?) orelse return;
    const parent_tree = @as(?*wlr.SceneTree, @ptrCast(@alignCast(parent.data))) orelse return;
    const scene_tree = parent_tree.createSceneXdgSurface(popup.base) catch |err| {
        log.err("Failed to allocate SceneSurface: {}", .{err});
        return;
    };
    popup.base.data = scene_tree;

    const self = comp.gpa.create(Popup) catch @panic("Out of Memory");
    self.* = .{
        .comp = comp,
        .popup = popup,
    };

    popup.base.surface.events.commit.add(&self.commit);
    popup.events.destroy.add(&self.destroy);
}

pub fn onCommit(listener: *wl.Listener(*wlr.Surface), _: *wlr.Surface) void {
    const self: *Popup = @fieldParentPtr("commit", listener);
    if (self.popup.base.initial_commit) {
        _ = self.popup.base.scheduleConfigure();
    }
}
pub fn onDestroy(listener: *wl.Listener(void)) void {
    const self: *Popup = @fieldParentPtr("destroy", listener);
    self.commit.link.remove();
    self.destroy.link.remove();

    self.comp.gpa.destroy(self);
}
