const std = @import("std");
const wl = @import("wayland").server.wl;
const wls = @import("wayland").server;
const wlr = @import("wlroots");
const Compositor = @import("Compositor.zig");

output: *wlr.Output,
comp: *Compositor,
last_frame_time: std.posix.timespec = undefined,

frame: wl.Listener(*wlr.Output) = .init(onFrame),
request_state: wl.Listener(*wlr.Output.event.RequestState) = .init(onRequestState),
destroy: wl.Listener(*wlr.Output) = .init(onDestroy),

const Output = @This();
const log = std.log.scoped(.output);

pub fn init(
    comp: *Compositor,
    data: *wlr.Output,
) !*Output {
    if (!data.initRender(comp.wlr_allocator, comp.renderer)) {
        return error.RendererInitError;
    }
    var state = wlr.Output.State.init();
    state.setEnabled(true);

    const mode = data.preferredMode();
    if (mode) |m| {
        state.setMode(m);
    }

    if (!data.commitState(&state)) {
        return error.CommitStateError;
    }

    const loutput = try comp.output_layout.addAuto(data);
    const soutput = try comp.scene.createSceneOutput(data);
    comp.scene_output_layout.addOutput(loutput, soutput);

    var self = try comp.gpa.create(Output);
    self.* = .{
        .output = data,
        .comp = comp,
    };

    data.events.frame.add(&self.frame);
    data.events.request_state.add(&self.request_state);
    data.events.destroy.add(&self.destroy);

    return self;
}

pub fn onFrame(
    listener: *wl.Listener(*wlr.Output),
    _: *wlr.Output,
) void {
    const self: *Output = @alignCast(@fieldParentPtr("frame", listener));
    const so = self.comp.scene.getSceneOutput(self.output) orelse {
        log.err("Dsynced output frame request", .{});
        return;
    };
    _ = so.commit(null);
    if (std.posix.system.clock_gettime(std.posix.CLOCK.MONOTONIC, &self.last_frame_time,) != 0) {
        log.err("CLOCK_MONOTONIC is unsupported by kernel", .{});
    }
    so.sendFrameDone(&self.last_frame_time);
}

pub fn onRequestState(
    listener: *wl.Listener(*wlr.Output.event.RequestState),
    event: *wlr.Output.event.RequestState,
) void {
    const self: *Output = @alignCast(@fieldParentPtr("request_state", listener));
    _ = self.output.commitState(event.state);
}

pub fn onDestroy(
    listener: *wl.Listener(*wlr.Output),
    _: *wlr.Output,
) void {
    const self: *Output = @alignCast(@fieldParentPtr("destroy", listener));
    _ = self.comp.outputs.orderedRemove(self.deinitWithIdx());
}

pub fn deinitWithIdx(self: *Output) usize {
    var idx: usize = 0;
    for (self.comp.outputs.items, 0..) |o, i| {
        if (o.output == self.output)
            idx = i;
    }
    self.frame.link.remove();
    self.request_state.link.remove();
    self.destroy.link.remove();
    self.comp.output_layout.remove(self.output);
    self.comp.scene.getSceneOutput(self.output).?.destroy();
    self.output.destroy();
    self.comp.gpa.destroy(self);
    return idx;
}

pub fn deinit(self: *Output) void {
    self.frame.link.remove();
    self.request_state.link.remove();
    self.destroy.link.remove();
    self.comp.output_layout.remove(self.output);
    self.comp.scene.getSceneOutput(self.output).?.destroy();
    self.output.destroy();
    self.comp.gpa.destroy(self);
}
