const std = @import("std");
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const Compositor = @import("Compositor.zig");
const Toplevel = @import("Toplevel.zig");
const Output = @import("Output.zig");

comp: *Compositor,
workspaces: [10]Workspace,
screens: std.ArrayList(Screen) = .empty,
ex_zone: std.ArrayList(ExZone) = .empty,
allocator: std.mem.Allocator,
config: Config,
current_screen: ?usize,
default_mode: Mode = .tiling,
drag_win: ?*Window = null,
drag_ws_idx: usize = 0,

const LayoutMgr = @This();

const log = Compositor.log;

pub const Mode = enum {
    floating,
    tiling,
    monowindow,
};

pub const Config = struct {
    padding_in: i32 = 6,
    padding_out: i32 = 10,
};

pub const SplitDir = enum {
    horizontal,
    vertical,
};

const PHI: f32 = 1.618;

pub fn chooseSplitDir(w: i32, h: i32) SplitDir {
    if (w <= 0 or h <= 0) return .horizontal;

    const v_diff = @abs(@as(f32, @floatFromInt(h)) / (2.0 * @as(f32, @floatFromInt(w))) - PHI);
    const h_diff = @abs(@as(f32, @floatFromInt(w)) / (2.0 * @as(f32, @floatFromInt(h))) - PHI);

    return if (v_diff < h_diff) .vertical else .horizontal;
}

pub fn processWin(self: *LayoutMgr, rect: Rect) Rect {
    const p = self.config.padding_in;
    return .{
        .x = rect.x + p,
        .y = rect.y + p,
        .width = rect.width - (p*2),
        .height = rect.height - (p*2),
    };
}

pub fn splitArea(self: *LayoutMgr, area: Rect, dir: SplitDir) struct { Rect, Rect } {
    const p = @divTrunc(self.config.padding_out, 2);
    const p2 = self.config.padding_out;
    switch (dir) {
        .horizontal => {
            const half_w = @divTrunc(area.width, 2);
            return .{
                Rect{
                    .x = area.x,
                    .y = area.y,
                    .width = half_w - p,
                    .height = area.height,
                },
                Rect{
                    .x = area.x + half_w + p,
                    .y = area.y,
                    .width = area.width - half_w - p2,
                    .height = area.height,
                },
            };
        },
        .vertical => {
            const half_h = @divTrunc(area.height, 2);
            return .{
                Rect{
                    .x = area.x,
                    .y = area.y,
                    .width = area.width,
                    .height = half_h - p
                },
                Rect{
                    .x = area.x,
                    .y = area.y + half_h + p,
                    .width = area.width,
                    .height = area.height - half_h - p2,
                },
            };
        },
    }
}

pub const Rect = struct {
    x: i32,
    y: i32,
    width: i32,
    height: i32,

    pub fn fromView(view: *Toplevel) Rect {
        return .{
            .x = view.x,
            .y = view.y,
            .width = view.toplevel.base.geometry.width,
            .height = view.toplevel.base.geometry.height,
        };
    }
};

const BspNode = struct {
    parent: ?*BspNode,
    /// This is either a doubly forward only linked list or a single window
    /// to represent the base unit. `dir` is just metadata for the drawer to know
    /// if it's horizontal or vertical.
    data: union(enum) {
        leaf: *Window,
        split: struct { dir: SplitDir, first: *BspNode, last: *BspNode },
    },
};

pub const Window = struct {
    rect: Rect,
    link: wl.list.Link = undefined,
    view: *Toplevel,
    gpa: std.mem.Allocator,

    pub fn create(gpa: std.mem.Allocator, view: *Toplevel) !*Window {
        const self = try gpa.create(Window);
        self.* = .{
            .rect = Rect.fromView(view),
            .view = view,
            .gpa = gpa,
        };
        return self;
    }

    pub fn applyPosition(self: *Window) void {
        self.view.scene_tree.node.setPosition(self.rect.x, self.rect.y);
        self.view.x = self.rect.x;
        self.view.y = self.rect.y;
    }

    pub fn commit(self: *Window, respect_min: bool) void {
        self.applyPosition();
        var w = self.rect.width;
        var h = self.rect.height;
        if (respect_min) {
            w = @max(w, self.view.toplevel.current.min_width);
            h = @max(h, self.view.toplevel.current.min_height);
        }
        _ = self.view.toplevel.setSize(w, h);
    }

    pub fn destroy(self: *Window) void {
        self.gpa.destroy(self);
    }
};

pub const Workspace = struct {
    windows: wl.list.Head(Window, .link),
    mode: ?Mode = null,
    bsp_root: ?*BspNode = null,

    pub fn init(w: *Workspace) void {
        w.* = .{
            .windows = undefined,
            .mode = null,
        };
        w.windows.init();
    }

    pub fn deinit(self: *Workspace) void {
        var iter = self.windows.iterator(.forward);
        while (iter.next()) |w| {
            w.destroy();
        }
    }

    pub fn windowCount(self: *Workspace) usize {
        var count: usize = 0;
        var iter = self.windows.iterator(.forward);
        while (iter.next()) |_| count += 1;
        return count;
    }
};

pub const Screen = struct {
    output: *Output,
    workspace: usize,
};

pub const ExZone = struct {
    anchor_top: bool = false,
    anchor_bottom: bool = false,
    anchor_left: bool = false,
    anchor_right: bool = false,
    size: i32 = 0,
};

pub fn create(comp: *Compositor, config: Config) LayoutMgr {
    return .{
        .comp = comp,
        .allocator = comp.gpa,
        .workspaces = undefined,
        .current_screen = null,
        .config = config,
    };
}

pub fn initWorkspaces(self: *LayoutMgr) void {
    for (&self.workspaces) |*w| {
        Workspace.init(w);
    }
}

pub fn getEffectiveMode(self: *LayoutMgr, workspace: usize) Mode {
    std.debug.assert(workspace <= 9);
    return if (self.workspaces[workspace].mode) |m| m else self.default_mode;
}

pub fn getScreenWithWorkspace(self: *LayoutMgr, workspace: usize) ?*Screen {
    for (self.screens.items) |*s| {
        if (s.workspace == workspace)
            return s;
    }
    return null;
}

fn arrangeNode(self: *LayoutMgr, node: *BspNode, area: Rect) void {
    switch (node.data) {
        .leaf => |win| {
            win.rect = self.processWin(area);
            win.commit(false);
        },
        .split => |s| {
            const children = self.splitArea(area, s.dir);
            self.arrangeNode(s.first, children[0]);
            self.arrangeNode(s.last, children[1]);
        },
    }
}

pub fn arrange(self: *LayoutMgr, workspace: usize) void {
    std.debug.assert(workspace <= 9);
    const ws = &self.workspaces[workspace];
    const mode = self.getEffectiveMode(workspace);
    if (mode == .floating) return;

    const area = if (self.screens.items.len > 0)
        self.usableArea(0)
    else
        Rect{ .x = 0, .y = 0, .width = 1920, .height = 1080 };

    switch (mode) {
        .tiling => {
            if (ws.bsp_root) |root| {
                self.arrangeNode(root, .{
                    .x = area.x,
                    .y = area.y,
                    .width = area.width,
                    .height = area.height,
                });
            }
        },
        .monowindow => {
            var iter = ws.windows.iterator(.forward);
            if (iter.next()) |win| {
                win.rect = area;
                win.commit(false);
            }
        },
        .floating => unreachable,
    }
}

pub fn setWorkspaceMode(self: *LayoutMgr, workspace: usize, mode: Mode) void {
    std.debug.assert(workspace <= 9);
    self.workspaces[workspace].mode = mode;
    self.arrange(workspace);
}

fn findBspLeaf(self: *LayoutMgr, node: *BspNode, win: *Window) ?*BspNode {
    switch (node.data) {
        .leaf => |w| {
            return if (w == win) node else null;
        },
        .split => |s| {
            return self.findBspLeaf(s.first, win) orelse self.findBspLeaf(s.last, win);
        },
    }
}

fn findFirstLeaf(self: *LayoutMgr, node: *BspNode) *BspNode {
    return switch (node.data) {
        .leaf => node,
        .split => |s| self.findFirstLeaf(s.first),
    };
}

fn splitBspLeaf(self: *LayoutMgr, _: *Workspace, leaf: *BspNode, dir: SplitDir, new_win: *Window, rel_x: f32, rel_y: f32) void {
    const existing_win = leaf.data.leaf;

    const existing_leaf = self.allocator.create(BspNode) catch @panic("Out of memory");
    existing_leaf.* = .{ .parent = leaf, .data = .{ .leaf = existing_win } };

    const new_leaf = self.allocator.create(BspNode) catch @panic("Out of memory");
    new_leaf.* = .{ .parent = leaf, .data = .{ .leaf = new_win } };

    const cursor_on_first: bool = switch (dir) {
        .horizontal => rel_x < 0.5,
        .vertical => rel_y < 0.5,
    };

    if (cursor_on_first) {
        leaf.data = .{ .split = .{ .dir = dir, .first = new_leaf, .last = existing_leaf } };
    } else {
        leaf.data = .{ .split = .{ .dir = dir, .first = existing_leaf, .last = new_leaf } };
    }
}

fn removeBspLeaf(self: *LayoutMgr, ws: *Workspace, leaf: *BspNode) void {
    const parent = leaf.parent orelse {
        self.allocator.destroy(leaf);
        ws.bsp_root = null;
        return;
    };
    const grandparent = parent.parent;
    const sibling = if (parent.data.split.first == leaf) parent.data.split.last else parent.data.split.first;
    sibling.parent = grandparent;

    if (grandparent) |gp| {
        if (gp.data.split.first == parent) {
            gp.data.split.first = sibling;
        } else {
            gp.data.split.last = sibling;
        }
    } else {
        ws.bsp_root = sibling;
    }

    self.allocator.destroy(leaf);
    self.allocator.destroy(parent);
}

fn destroyBspTree(self: *LayoutMgr, node: *BspNode) void {
    switch (node.data) {
        .leaf => {
            self.allocator.destroy(node);
        },
        .split => |s| {
            self.destroyBspTree(s.first);
            self.destroyBspTree(s.last);
            self.allocator.destroy(node);
        },
    }
}

pub fn doMap(self: *LayoutMgr, view: *Toplevel) void {
    if (self.findView(view) != null) return;
    const ws_idx = if (self.current_screen) |si|
        self.screens.items[si].workspace
    else
        0;
    const ws = &self.workspaces[ws_idx];
    const win = Window.create(self.allocator, view) catch @panic("Out of memory");

    if (self.getEffectiveMode(ws_idx) == .floating) {
        const cx = @as(i32, @intFromFloat(self.comp.cursor.x));
        const cy = @as(i32, @intFromFloat(self.comp.cursor.y));
        if (self.comp.viewAt(self.comp.cursor.x, self.comp.cursor.y)) |hit| {
            if (self.findView(hit.toplevel)) |existing| {
                win.rect.x = existing.rect.x + existing.rect.width;
                win.rect.y = existing.rect.y;
            } else {
                win.rect.x = cx;
                win.rect.y = cy;
            }
        } else {
            win.rect.x = cx;
            win.rect.y = cy;
        }
        ws.windows.append(win);
    } else {
        if (ws.bsp_root) |root| {
            const target_win = blk: {
                if (self.comp.viewAt(self.comp.cursor.x, self.comp.cursor.y)) |hit| {
                    break :blk self.findView(hit.toplevel);
                }
                break :blk null;
            };

            if (target_win) |tw| {
                if (self.findBspLeaf(root, tw)) |leaf| {
                    const dir = chooseSplitDir(tw.rect.width, tw.rect.height);
                    const rel_x = @as(f32, @floatFromInt(@as(i32, @intFromFloat(self.comp.cursor.x)) - tw.rect.x)) / @as(f32, @floatFromInt(tw.rect.width));
                    const rel_y = @as(f32, @floatFromInt(@as(i32, @intFromFloat(self.comp.cursor.y)) - tw.rect.y)) / @as(f32, @floatFromInt(tw.rect.height));
                    self.splitBspLeaf(ws, leaf, dir, win, rel_x, rel_y);
                    ws.windows.append(win);
                } else {
                    ws.windows.append(win);
                }
            } else {
                const first = self.findFirstLeaf(root);
                const dir = chooseSplitDir(win.rect.width, win.rect.height);
                const rel_x = @as(f32, @floatFromInt(@as(i32, @intFromFloat(self.comp.cursor.x)) - first.data.leaf.rect.x)) / @as(f32, @floatFromInt(first.data.leaf.rect.width));
                const rel_y = @as(f32, @floatFromInt(@as(i32, @intFromFloat(self.comp.cursor.y)) - first.data.leaf.rect.y)) / @as(f32, @floatFromInt(first.data.leaf.rect.height));
                self.splitBspLeaf(ws, first, dir, win, rel_x, rel_y);
                ws.windows.append(win);
            }
        } else {
            ws.bsp_root = self.allocator.create(BspNode) catch @panic("Out of memory");
            ws.bsp_root.?.* = .{ .parent = null, .data = .{ .leaf = win } };
            ws.windows.append(win);
        }
    }

    win.commit(self.getEffectiveMode(ws_idx) == .floating);
    self.arrange(ws_idx);
}

pub fn doUnmap(self: *LayoutMgr, view: *Toplevel) void {
    if (self.drag_win) |dw| {
        if (dw.view == view) {
            dw.destroy();
            self.drag_win = null;
            return;
        }
    }
    const ws_idx = self.workspaceForView(view) orelse return;
    if (self.findView(view)) |win| {
        win.link.remove();
        if (self.getEffectiveMode(ws_idx) == .tiling) {
            const ws = &self.workspaces[ws_idx];
            if (ws.bsp_root) |root| {
                if (self.findBspLeaf(root, win)) |leaf| {
                    self.removeBspLeaf(ws, leaf);
                }
            }
        }
        win.destroy();
        self.arrange(@intCast(ws_idx));
    }
}

pub fn doMove(self: *LayoutMgr, view: *Toplevel, x: i32, y: i32) void {
    if (self.findView(view)) |win| {
        win.rect.x = x;
        win.rect.y = y;
        win.applyPosition();
    }
}

pub fn liftWindow(self: *LayoutMgr, view: *Toplevel) void {
    if (self.drag_win != null) return;
    const ws_idx = self.workspaceForView(view) orelse return;
    if (self.getEffectiveMode(ws_idx) != .tiling) return;
    const win = self.findView(view) orelse return;

    win.link.remove();

    const ws = &self.workspaces[ws_idx];
    if (ws.bsp_root) |root| {
        if (self.findBspLeaf(root, win)) |leaf| {
            self.removeBspLeaf(ws, leaf);
        }
    }

    self.drag_win = win;
    self.drag_ws_idx = ws_idx;
    self.arrange(ws_idx);
}

pub fn snapWindow(self: *LayoutMgr, view: *Toplevel) void {
    const win = self.drag_win orelse return;
    if (win.view != view) return;

    const ws_idx = self.drag_ws_idx;
    const ws = &self.workspaces[ws_idx];
    if (self.getEffectiveMode(ws_idx) != .tiling) {
        self.drag_win = null;
        return;
    }

    // We remove the window so we can get the leaf of the window below it
    // and split it.
    win.view.scene_tree.node.setEnabled(false);
    const target_win = blk: {
        if (self.comp.viewAt(self.comp.cursor.x, self.comp.cursor.y)) |hit| {
            break :blk self.findView(hit.toplevel);
        }
        break :blk null;
    };
    win.view.scene_tree.node.setEnabled(true);

    if (target_win) |tw| {
        if (ws.bsp_root) |root| {
            if (self.findBspLeaf(root, tw)) |leaf| {
                const dir = chooseSplitDir(tw.rect.width, tw.rect.height);
                const rel_x = @as(f32, @floatFromInt(@as(i32, @intFromFloat(self.comp.cursor.x)) - tw.rect.x)) / @as(f32, @floatFromInt(tw.rect.width));
                const rel_y = @as(f32, @floatFromInt(@as(i32, @intFromFloat(self.comp.cursor.y)) - tw.rect.y)) / @as(f32, @floatFromInt(tw.rect.height));
                self.splitBspLeaf(ws, leaf, dir, win, rel_x, rel_y);
                ws.windows.append(win);
                self.drag_win = null;
                self.arrange(ws_idx);
                return;
            }
        }
    }

    // If there is no window below the lifted window, we make the lifted window root.

    if (ws.bsp_root) |root| {
        self.destroyBspTree(root);
    }
    ws.bsp_root = self.allocator.create(BspNode) catch @panic("Out of memory");
    ws.bsp_root.?.* = .{ .parent = null, .data = .{ .leaf = win } };
    ws.windows.append(win);
    self.drag_win = null;
    self.arrange(ws_idx);
}

pub fn usableArea(self: *LayoutMgr, screen_idx: usize) Rect {
    var box: wlr.Box = undefined;
    self.comp.output_layout.getBox(self.screens.items[screen_idx].output.output, &box);
    var area = Rect{ .x = box.x, .y = box.y, .width = box.width, .height = box.height };
    for (self.ex_zone.items) |zone| {
        const s = zone.size+self.config.padding_out;
        if (zone.anchor_top) {
            area.y += s;
            area.height -= s;
        }
        if (zone.anchor_bottom) {
            area.height -= s;
        }
        if (zone.anchor_left and !zone.anchor_right) {
            area.x += s;
            area.width -= s;
        }
        if (zone.anchor_right and !zone.anchor_left) {
            area.width -= s;
        }
    }
    return area;
}

pub fn switchWorkspace(self: *LayoutMgr, ws_idx: usize) void {
    const si = self.current_screen orelse return;
    if (ws_idx >= self.workspaces.len) return;
    const old = self.screens.items[si].workspace;
    if (old == ws_idx) return;
    self.showWorkspace(old, false);
    self.screens.items[si].workspace = ws_idx;
    self.showWorkspace(ws_idx, true);
    self.arrange(ws_idx);
}

pub fn cycleMode(self: *LayoutMgr) void {
    const si = self.current_screen orelse return;
    const ws_idx = self.screens.items[si].workspace;
    const current = self.getEffectiveMode(ws_idx);
    const next: Mode = switch (current) {
        .floating => .tiling,
        .tiling => .monowindow,
        .monowindow => .floating,
    };
    self.setWorkspaceMode(ws_idx, next);
}

fn showWorkspace(self: *LayoutMgr, ws_idx: usize, show: bool) void {
    const ws = &self.workspaces[ws_idx];
    var iter = ws.windows.iterator(.forward);
    while (iter.next()) |win| {
        win.view.scene_tree.node.setEnabled(show);
    }
}

pub fn addScreen(self: *LayoutMgr, output: *Output) !usize {
    const ws = self.screens.items.len;
    try self.screens.append(self.allocator, .{
        .output = output,
        .workspace = ws,
    });
    if (self.current_screen == null) {
        self.current_screen = self.screens.items.len - 1;
    }
    return self.screens.items.len - 1;
}

pub fn removeScreen(self: *LayoutMgr, output: *Output) void {
    for (self.screens.items, 0..) |screen, i| {
        if (screen.output == output) {
            _ = self.screens.swapRemove(i);
            if (self.current_screen) |cs| {
                if (cs == i or cs >= self.screens.items.len) {
                    self.current_screen = if (self.screens.items.len > 0) @as(usize, 0) else null;
                }
            }
            return;
        }
    }
}

pub fn findView(self: *LayoutMgr, view: *Toplevel) ?*Window {
    if (self.drag_win) |dw| {
        if (dw.view == view) return dw;
    }
    for (&self.workspaces) |*wo| {
        var iter = wo.windows.iterator(.forward);
        while (iter.next()) |w| {
            if (w.view == view) return w;
        }
    }
    return null;
}

pub fn workspaceForView(self: *LayoutMgr, view: *Toplevel) ?usize {
    if (self.drag_win) |dw| {
        if (dw.view == view) return self.drag_ws_idx;
    }
    for (&self.workspaces, 0..) |*ws, i| {
        var iter = ws.windows.iterator(.forward);
        while (iter.next()) |win| {
            if (win.view == view) return i;
        }
    }
    return null;
}

/// Gets rectangle out of exclusive area into usable area.
/// Mainly used for coordinate correction and mixmization.
pub fn unexclusive(self: *LayoutMgr, rect: Rect) Rect {
    var res = rect;
    if (self.current_screen) |si| {
        const ua = self.usableArea(si);
        if (res.x < ua.x) res.x = ua.x;
        if (res.y < ua.y) res.y = ua.y;
        if (res.x + res.width > ua.x + ua.width) res.x = ua.x + ua.width - res.width;
        if (res.y + res.height > ua.y + ua.height) res.y = ua.y + ua.height - res.height;
    }
    return res;
}

pub fn destroy(self: *LayoutMgr) void {
    for (&self.workspaces) |*w| {
        w.deinit();
    }
    self.screens.deinit(self.allocator);
    self.ex_zone.deinit(self.allocator);
}
