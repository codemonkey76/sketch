const std = @import("std");
const rl = @import("raylib");
const arcade = @import("arcade_lib");
const sketch = @import("../root.zig");
const Ui = sketch.ui.Ui;
const listbox = sketch.ui.listbox;
const canvas = sketch.ui.canvas;
const button = sketch.ui.button;
const layout = sketch.ui.layout;
const ConfirmSwitchModal = sketch.ui.modals.confirm_switch;
const Id = sketch.ui.ids.Id;
const PathEditor = @import("path_editor.zig").PathEditor;
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
    list_items: []listbox.Item = &.{},

    editor: PathEditor,
    modal: Modal = .None,

    ui: Ui = .{},
    list_state: listbox.State = .{},
    canvas_state: canvas.State = .{},
    button_state: button.State = .{},
    selected: u32 = 0,
    debug_log: bool = false,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, font: rl.Font) AppModel {
        var m: AppModel = .{
            .allocator = allocator,
            .font = font,
            .paths = arcade.PathRegistry.init(allocator),
            .editor = PathEditor.init(allocator),
        };

        m.reloadAll() catch {};
        return m;
    }

    fn rebuildPathNames(self: *Self) !void {
        // free old buffers (not the strings)
        if (self.path_names.len != 0) self.allocator.free(self.path_names);
        if (self.list_items.len != 0) self.allocator.free(self.list_items);

        self.path_names = try self.paths.listPaths(self.allocator);

        self.list_items = try self.allocator.alloc(listbox.Item, self.path_names.len);
        for (self.path_names, 0..) |name, i| {
            self.list_items[i] = .{
                .id = @intCast(i),
                .label = name,
            };
        }
    }

    pub fn deinit(self: *Self) void {
        if (self.list_items.len != 0) self.allocator.free(self.list_items);
        if (self.path_names.len != 0) self.allocator.free(self.path_names);

        self.paths.deinit();
        self.editor.deinit();
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

        const b = button.button(&self.ui, Id.toolbar_reload_btn, btn_reload, self.font, "Reload", true, .{});
        if (b.clicked) {
            self.reloadAll() catch {};
        }

        const btn_save = flow.nextButton(self.font, 18, "Save");
        const b2 = button.button(&self.ui, Id.toolbar_save_btn, btn_save, self.font, "Save", self.editor.dirty, .{});
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
        const res = listbox.listBox(
            &self.ui,
            &self.list_state,
            Id.listbox_paths,
            split_main.left,
            self.font,
            self.list_items,
            self.selected,
            .{ .debug_log = self.debug_log },
        );

        if (res.picked) |id| {
            const clicked_index: u32 = id;
            const is_different = clicked_index != self.selected;

            if (!is_different) {
                // no op
            } else if (!self.editor.dirty and self.modal == .None) {
                try self.switchToIndex(clicked_index);
            } else if (self.editor.dirty and self.modal == .None) {
                self.modal = .{ .ConfirmSwitch = .{ .target_index = clicked_index } };
            }
        } else {
            if (!self.editor.dirty and self.modal == .None) {
                if (res.selected_id != self.selected) try self.switchToIndex(res.selected_id);
            }
        }

        if (self.modal == .None) {
            const c = try canvas.canvasEditor(
                self.allocator,
                &self.ui,
                &self.canvas_state,
                Id.canvas_editor,
                split_main.rest,
                self.font,
                &self.editor.points,
                .{},
            );
            if (c.changed) self.editor.markDirty();
        }

        switch (self.modal) {
            .None => {},
            .ConfirmSwitch => |m| {
                const act = ConfirmSwitchModal.draw(&self.ui, self.font);
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

    fn resetEditorState(self: *Self) void {
        self.editor.points.clearRetainingCapacity();
        self.editor.dirty = false;
        self.modal = .None;
        self.editor.current_name = null;
        self.selected = 0;
    }

    fn reloadAll(self: *Self) !void {
        self.resetEditorState();

        // rebuild registry
        self.paths.deinit();
        self.paths = arcade.PathRegistry.init(self.allocator);
        try self.paths.loadFromDirectory("assets/paths");
        try self.rebuildPathNames();

        // select first path if present
        if (self.path_names.len > 0) {
            try self.switchToIndex(0);
        }
    }

    fn switchToIndex(self: *Self, idx: u32) !void {
        self.selected = idx;

        const name = self.path_names[@intCast(idx)];
        const path = self.paths.getPath(name) orelse return;

        try self.editor.load(name, path);
    }

    fn saveCurrent(self: *Self) !void {
        const name = self.editor.current_name orelse return;
        try self.paths.savePath(name, self.editor.definition());
        try self.rebuildPathNames();
        self.editor.dirty = false;
    }
};
