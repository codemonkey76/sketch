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
const PathList = @import("path_list.zig").PathList;

const ToolbarAction = enum { None, Reload, Save };

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

    editor: PathEditor,
    path_list: PathList,
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
            .path_list = PathList.init(allocator),
        };

        m.reloadAll() catch {};
        return m;
    }

    pub fn deinit(self: *Self) void {
        self.paths.deinit();
        self.editor.deinit();
        self.path_list.deinit();
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

        const act = self.drawToolbar(split_root.top);
        switch (act) {
            .None => {},
            .Reload => try self.reloadAll(),
            .Save => try self.saveCurrent(),
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
            self.path_list.items,
            self.selected,
            .{ .debug_log = self.debug_log },
        );

        try self.handlePathSelection(res);

        if (!self.isBlockedByModal()) {
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

        try self.handleModal();
    }

    fn acceptConfirmAndSwitch(self: *Self, target: u32) !void {
        try self.saveCurrent();
        try self.switchToIndex(target);
        self.modal = .None;
    }

    fn discardConfirmAndSwitch(self: *Self, target: u32) !void {
        try self.switchToIndex(target);
        self.modal = .None;
    }

    fn cancelConfirm(self: *Self) void {
        self.modal = .None;
    }

    fn handleModal(self: *Self) !void {
        switch (self.modal) {
            .None => {},
            .ConfirmSwitch => |m| {
                const act = ConfirmSwitchModal.draw(&self.ui, self.font);
                switch (act) {
                    .None => {},
                    .Yes => try self.acceptConfirmAndSwitch(m.target_index),
                    .No => try self.discardConfirmAndSwitch(m.target_index),
                    .Cancel => self.cancelConfirm(),
                }
            },
        }
    }

    fn isBlockedByModal(self: *const Self) bool {
        return self.modal != .None;
    }

    fn handlePathSelection(self: *Self, res: listbox.Result) !void {
        if (self.isBlockedByModal()) return;

        if (res.picked) |id| {
            const clicked_index: u32 = id;
            if (clicked_index == self.selected) return;

            if (!self.editor.dirty) {
                try self.switchToIndex(clicked_index);
            } else {
                self.modal = .{ .ConfirmSwitch = .{ .target_index = clicked_index } };
            }
            return;
        }

        // keyboard/nav selection changes
        if (!self.editor.dirty and res.selected_id != self.selected) {
            try self.switchToIndex(res.selected_id);
        }
    }

    fn drawToolbar(self: *Self, top: rl.Rectangle) ToolbarAction {
        // Toolbar chrome
        rl.drawRectangleRec(top, rl.Color.light_gray);
        rl.drawRectangleLinesEx(top, 1, rl.Color.gray);

        var flow = layout.Flow.init(top);

        // Reload
        const btn_reload = flow.nextButton(self.font, 18, "Reload");
        const r = button.button(&self.ui, Id.toolbar_reload_btn, btn_reload, self.font, "Reload", true, .{});
        if (r.clicked) return .Reload;

        // Save
        const btn_save = flow.nextButton(self.font, 18, "Save");
        const s = button.button(&self.ui, Id.toolbar_save_btn, btn_save, self.font, "Save", self.editor.dirty, .{});
        if (s.clicked) return .Save;

        return .None;
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
        try self.path_list.rebuild(&self.paths);

        // select first path if present
        if (self.path_list.names.len > 0) {
            try self.switchToIndex(0);
        }
    }

    fn switchToIndex(self: *Self, idx: u32) !void {
        self.selected = idx;

        const name = self.path_list.names[@intCast(idx)];
        const path = self.paths.getPath(name) orelse return;

        try self.editor.load(name, path);
    }

    fn saveCurrent(self: *Self) !void {
        const name = self.editor.current_name orelse return;
        try self.paths.savePath(name, self.editor.definition());
        try self.path_list.rebuild(&self.paths);
        self.editor.dirty = false;
    }
};
