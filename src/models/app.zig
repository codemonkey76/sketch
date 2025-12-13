const std = @import("std");
const rl = @import("raylib");
const arcade = @import("arcade_lib");
const sketch = @import("../root.zig");
const Ui = sketch.ui.Ui;
const listbox = sketch.ui.listbox;
const canvas = sketch.ui.canvas;
const button = sketch.ui.button;
const layout = sketch.ui.layout;

const ModalAction = enum { None, Yes, No, Cancel };

const MARGIN = 6;
pub const AppMsg = union(enum) {
    Quit,
    MoveMouse: struct { x: f32, y: f32 },
    MouseDown: struct { button: rl.MouseButton },
    MouseUp: struct { button: rl.MouseButton },
    KeyDown: struct { key: rl.KeyboardKey },
    Tick: f32,
};

pub const AppCmd = union(enum) {
    None,
};

pub const Modal = union(enum) {
    None,
    ConfirmSwitch: struct { target_index: u32 },
};

pub const AppModel = struct {
    allocator: std.mem.Allocator,
    running: bool = true,
    mouse_x: f32 = 0,
    mouse_y: f32 = 0,
    font: rl.Font,
    paths: arcade.PathRegistry,
    path_names: [][]const u8 = &.{},

    current_path_name: ?[]const u8 = null,
    edit_points: std.ArrayList(arcade.Vec2) = .{},
    dirty: bool = false,
    modal: Modal = .None,

    ui: Ui = .{},
    list_state: listbox.State = .{},
    canvas_state: canvas.State = .{},
    button_state: button.State = .{},
    selected: u32 = 0,
    debug_log: bool = false,

    const Self = @This();

    fn drawConfirmSwitchModal(self: *Self) ModalAction {
        const sw = @as(f32, @floatFromInt(rl.getScreenWidth()));
        const sh = @as(f32, @floatFromInt(rl.getScreenHeight()));

        rl.drawRectangle(0, 0, @intFromFloat(sw), @intFromFloat(sh), rl.fade(rl.Color.black, 0.45));

        const dlg_w: f32 = 420;
        const dlg_h: f32 = 160;
        const dlg = rl.Rectangle{
            .x = (sw - dlg_w) * 0.5,
            .y = (sh - dlg_h) * 0.5,
            .width = dlg_w,
            .height = dlg_h,
        };

        const msg = "Save changes?";
        rl.drawTextEx(self.font, msg, .{ .x = dlg.x + 18, .y = dlg.y + 18 }, 20, 0, rl.Color.black);

        const row = rl.Rectangle{
            .x = dlg.x + 18,
            .y = dlg.y + dlg.height - 56,
            .width = dlg.width - 36,
            .height = 40,
        };

        const bw: f32 = 110;
        const gap: f32 = 10;

        const r_yes = rl.Rectangle{ .x = row.x, .y = row.y, .width = bw, .height = row.height };
        const r_no = rl.Rectangle{ .x = row.x + bw + gap, .y = row.y, .width = bw, .height = row.height };
        const r_can = rl.Rectangle{ .x = row.x + (bw + gap) * 2, .y = row.y, .width = bw, .height = row.height };

        if (button.button(&self.ui, 90_000, r_yes, self.font, "Yes", true, .{}).clicked) return .Yes;
        if (button.button(&self.ui, 90_001, r_no, self.font, "No", true, .{}).clicked) return .No;
        if (button.button(&self.ui, 90_002, r_can, self.font, "Cancel", true, .{}).clicked) return .Cancel;

        return .None;
    }
    pub fn init(allocator: std.mem.Allocator, font: rl.Font) AppModel {
        var m: AppModel = .{
            .allocator = allocator,
            .font = font,
            .paths = arcade.PathRegistry.init(allocator),
        };

        m.paths.loadFromDirectory("assets/paths") catch {};
        m.rebuildPathNames() catch {};

        return m;
    }
    fn rebuildPathNames(self: *Self) !void {
        // free old list buffer (not the strings)
        if (self.path_names.len != 0) self.allocator.free(self.path_names);

        self.path_names = try self.paths.listPaths(self.allocator);
    }

    pub fn deinit(self: *Self) void {
        if (self.path_names.len != 0) self.allocator.free(self.path_names);
        self.edit_points.deinit(self.allocator);
        self.paths.deinit();
    }

    pub fn update(self: *Self, msg: AppMsg) AppCmd {
        switch (msg) {
            .Quit => self.running = false,
            .MoveMouse => |m| {
                self.mouse_x = m.x;
                self.mouse_y = m.y;
            },
            .KeyDown => |k| {
                if (k.key == rl.KeyboardKey.q) {
                    self.running = false;
                } else if (k.key == rl.KeyboardKey.f11) {
                    // Toggle fullscreen
                    rl.toggleBorderlessWindowed();
                } else if (k.key == rl.KeyboardKey.f3) {
                    self.debug_log = true;
                }
            },
            else => {},
        }

        return .None;
    }

    pub fn view(self: *Self) !void {
        self.ui.beginFrame();

        rl.beginDrawing();
        defer {
            rl.endDrawing();
            self.debug_log = false;
        }

        rl.clearBackground(rl.Color.dark_gray);

        const w = @as(f32, @floatFromInt(rl.getScreenWidth()));
        const h = @as(f32, @floatFromInt(rl.getScreenHeight()));

        const root = rl.Rectangle{
            .x = MARGIN,
            .y = MARGIN,
            .width = w - 2 * MARGIN,
            .height = h - 2 * MARGIN,
        };

        const split_root = layout.splitV(root, 52, MARGIN);

        // Toolbar
        rl.drawRectangleRec(split_root.top, rl.Color.light_gray);
        rl.drawRectangleLinesEx(split_root.top, 1, rl.Color.gray);

        var flow = layout.Flow.init(split_root.top);
        const btn_reload = flow.nextButton(self.font, 18, "Reload");

        const b = button.button(&self.ui, 10, btn_reload, self.font, "Reload", true, .{});
        if (b.clicked) {
            // editor atate
            self.edit_points.clearRetainingCapacity();
            self.dirty = false;
            self.modal = .None;
            self.current_path_name = null;
            self.selected = 0;

            self.paths.deinit();
            self.paths = arcade.PathRegistry.init(self.allocator);
            self.paths.loadFromDirectory("assets/paths") catch {};
            self.rebuildPathNames() catch {};

            if (self.path_names.len > 0) {
                self.switchToIndex(0) catch {};
            }
        }
        const btn_save = flow.nextButton(self.font, 18, "Save");
        const b2 = button.button(&self.ui, 11, btn_save, self.font, "Save", self.dirty, .{});
        if (b2.clicked) {
            std.debug.print("Saving\n", .{});
            try self.saveCurrent();
        }
        const split_main = layout.splitH(split_root.rest, 150, MARGIN);

        rl.drawRectangleRec(split_main.left, rl.Color.light_gray);
        rl.drawRectangleLinesEx(split_main.left, 1, rl.Color.gray);

        rl.drawRectangleRec(split_main.rest, rl.Color.light_gray);
        rl.drawRectangleLinesEx(split_main.rest, 1, rl.Color.gray);

        // Build listbox items from registry names
        const count = self.path_names.len;
        var items = try self.allocator.alloc(listbox.Item, count);
        defer self.allocator.free(items);

        for (self.path_names, 0..) |name, i| {
            items[i] = .{
                .id = @intCast(i),
                .label = name,
            };
        }
        const res = listbox.listBox(
            &self.ui,
            &self.list_state,
            2000,
            split_main.left,
            self.font,
            items,
            self.selected,
            .{ .debug_log = self.debug_log },
        );

        if (res.picked) |id| {
            const clicked_index: u32 = id;
            const is_different = clicked_index != self.selected;

            if (!is_different) {
                // no op
            } else if (!self.dirty and self.modal == .None) {
                try self.switchToIndex(clicked_index);
            } else if (self.dirty and self.modal == .None) {
                self.modal = .{ .ConfirmSwitch = .{ .target_index = clicked_index } };
            }
        } else {
            if (!self.dirty and self.modal == .None) {
                if (res.selected_id != self.selected) try self.switchToIndex(res.selected_id);
            }
        }

        if (self.modal == .None) {
            const c = try canvas.canvasEditor(
                self.allocator,
                &self.ui,
                &self.canvas_state,
                3000,
                split_main.rest,
                self.font,
                &self.edit_points,
                .{},
            );
            if (c.changed) self.dirty = true;
        }

        switch (self.modal) {
            .None => {},
            .ConfirmSwitch => |m| {
                const act = self.drawConfirmSwitchModal();
                switch (act) {
                    .None => {},
                    .Yes => {
                        try self.saveCurrent();
                        try self.switchToIndex(m.target_index);
                        self.modal = .None;
                    },
                    .No => {
                        try self.switchToIndex(m.target_index);
                        self.modal = .None;
                    },
                    .Cancel => {
                        self.modal = .None;
                    },
                }
            },
        }
    }

    fn switchToIndex(self: *Self, idx: u32) !void {
        self.selected = idx;

        const name = self.path_names[@intCast(idx)];
        self.current_path_name = name;

        self.edit_points.clearRetainingCapacity();
        if (self.paths.getPath(name)) |p| {
            try self.edit_points.appendSlice(self.allocator, p.control_points);
        }

        self.dirty = false;
    }

    fn saveCurrent(self: *Self) !void {
        const name = self.current_path_name orelse return;

        const def = arcade.PathDefinition{ .control_points = self.edit_points.items };
        try self.paths.savePath(name, def);

        try self.rebuildPathNames();
        self.dirty = false;
    }
};
