const std = @import("std");
const wl = @import("wayland").server.wl;
const wls = @import("wayland").server;
const wlr = @import("wlroots");
const xkb = @import("xkbcommon");
const Compositor = @import("Compositor.zig");

comp: *Compositor,
link: wl.list.Link = undefined,
device: *wlr.InputDevice,

modifiers: wl.Listener(*wlr.Keyboard) = .init(onModifiers),
key: wl.Listener(*wlr.Keyboard.event.Key) = .init(onKey),
destroy: wl.Listener(*wlr.InputDevice) = .init(onDestroy),

const Keyboard = @This();

pub fn create(comp: *Compositor, device: *wlr.InputDevice) !void {
    const self = try comp.gpa.create(Keyboard);
    errdefer comp.gpa.destroy(self);
    self.* = .{
        .device = device,
        .comp = comp,
    };
    const context = xkb.Context.new(.no_flags) orelse return error.FailedToInitContext;
    defer context.unref();
    const keymap = xkb.Keymap.newFromNames(context, null, .no_flags)
        orelse return error.FailedToInitKeymap;
    defer keymap.unref();

    const wkeyboard = device.toKeyboard();
    if (!wkeyboard.setKeymap(keymap)) return error.FailedToSetKeymap;
    wkeyboard.setRepeatInfo(25, 600);
    wkeyboard.events.modifiers.add(&self.modifiers);
    wkeyboard.events.key.add(&self.key);
    device.events.destroy.add(&self.destroy);

    comp.seat.setKeyboard(wkeyboard);
    comp.keyboards.append(self);
}

pub fn onModifiers(listener: *wl.Listener(*wlr.Keyboard), keyboard: *wlr.Keyboard) void {
    const self: *Keyboard = @fieldParentPtr("modifiers", listener);
    self.comp.seat.setKeyboard(keyboard);
    self.comp.seat.keyboardNotifyModifiers(&keyboard.modifiers);
}

pub fn onKey(listener: *wl.Listener(*wlr.Keyboard.event.Key), event: *wlr.Keyboard.event.Key) void {
    const self: *Keyboard = @fieldParentPtr("key", listener);
    const keyboard = self.device.toKeyboard();

    const keycode = event.keycode + 8;
    const shell_mod =
        (keyboard.getModifiers().alt and @import("builtin").mode == .Debug)
        or keyboard.getModifiers().logo;
    if (shell_mod and event.state == .pressed) {
        for (keyboard.xkb_state.?.keyGetSyms(keycode)) |sym| {
            if (self.comp.handleKeybind(sym)) {
                break;
            }
        }
        return;
    }

    self.comp.seat.setKeyboard(keyboard);
    self.comp.seat.keyboardNotifyKey(event.time_msec, event.keycode, event.state);
}

pub fn onDestroy(listener: *wl.Listener(*wlr.InputDevice), _: *wlr.InputDevice) void {
    const self: *Keyboard = @fieldParentPtr("destroy", listener);
    self.link.remove();
    self.destroy.link.remove();
    self.modifiers.link.remove();
    self.key.link.remove();
    self.comp.gpa.destroy(self);
}
