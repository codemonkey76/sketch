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
const ConfirmDeleteModal = sketch.ui.modals.confirm_delete;
const Id = sketch.ui.ids.Id;
const PathEditor = @import("path_editor.zig").PathEditor;
const PathList = @import("path_list.zig").PathList;
const CreatePathModal = sketch.ui.modals.create_path;
const text_input = sketch.ui.text_input;
const toolbar = sketch.ui.toolbar;

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
    CreatePath,
    RenamePath: struct { from_index: u32 },
    DuplicatePath: struct { from_index: u32 },
    DeletePath: struct { index: u32 },
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

    // Create path modal state ---
    new_path_buf: [64]u8 = undefined,
    new_path_len: usize = 0,
    new_path_input: sketch.ui.text_input.State = .{},

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

    fn pathNameExists(self: *Self, name: []const u8) bool {
        for (self.path_list.names) |n| {
            if (std.mem.eql(u8, n, name)) return true;
        }
        return false;
    }

    fn createNewPath(self: *Self, name: []const u8) !void {
        // Create empty definition (or a default 4-point cubic if you prefer)
        const def = arcade.PathDefinition{ .control_points = &.{} };

        try self.paths.savePath(name, def);
        try self.path_list.rebuild(&self.paths);

        var i: u32 = 0;
        while (i < self.path_list.names.len) : (i += 1) {
            if (std.mem.eql(u8, self.path_list.names[@intCast(i)], name)) break;
        }
        if (i < self.path_list.names.len) {
            try self.switchToIndex(i);
        }

        self.modal = .None;
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

        const act = toolbar.draw(&self.ui, self.font, split_root.top, self.editor.dirty, self.path_list.names.len > 0);
        switch (act) {
            .None => {},
            .Reload => try self.reloadAll(),
            .Save => try self.saveCurrent(),
            .New => self.openCreatePathModal(),
            .Rename => self.openRenamePathModal(),
            .Duplicate => self.openDuplicatePathModal(),
            .Delete => self.openDeleteModal(),
            .FlipH => self.flipHorizontal(),
            .FlipV => self.flipVertical(),
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

    fn flipHorizontal(self: *Self) void {
        if (self.isBlockedByModal()) return;

        for (self.editor.points.items) |*p| {
            p.x = 1.0 - p.x;
        }
        self.editor.markDirty();
    }

    fn flipVertical(self: *Self) void {
        if (self.isBlockedByModal()) return;

        for (self.editor.points.items) |*p| {
            p.y = 1.0 - p.y;
        }
        self.editor.markDirty();
    }

    fn openDeleteModal(self: *Self) void {
        if (self.path_list.names.len == 0) return;
        self.modal = .{ .DeletePath = .{ .index = self.selected } };
    }

    fn openDuplicatePathModal(self: *Self) void {
        if (self.path_list.names.len == 0) return;

        const from = self.path_list.names[@intCast(self.selected)];

        var suggestion_buf: [64]u8 = undefined;
        const suggestion = self.nextDuplicateName(&suggestion_buf, from);

        self.new_path_len = @min(suggestion.len, self.new_path_buf.len);
        @memcpy(self.new_path_buf[0..self.new_path_len], suggestion[0..self.new_path_len]);
        self.new_path_input.caret = self.new_path_len;

        self.ui.active = Id.modal_create;
        self.modal = .{ .DuplicatePath = .{ .from_index = self.selected } };
    }

    fn nextDuplicateName(self: *Self, out: []u8, base: []const u8) []const u8 {
        // 1) try "{base}_copy"
        var n: u32 = 0;
        while (true) : (n += 1) {
            const s = if (n == 0)
                (std.fmt.bufPrint(out, "{s}_copy", .{base}) catch base)
            else
                (std.fmt.bufPrint(out, "{s}_copy{d}", .{ base, n + 1 }) catch base);

            const trimmed = std.mem.trim(u8, s, " \t\r\n");
            if (trimmed.len == 0) continue;
            if (!self.pathNameExists(trimmed)) return trimmed;
        }
    }

    fn duplicatePath(self: *Self, from: []const u8, to_raw: []const u8) !void {
        const to = std.mem.trim(u8, to_raw, " \t\r\n");
        if (to.len == 0) return;
        if (std.mem.eql(u8, from, to)) return;
        if (self.pathNameExists(to)) return;

        const def = self.paths.getPath(from) orelse return;

        try self.paths.savePath(to, def);
        try self.path_list.rebuild(&self.paths);

        // select the new copy
        var i: u32 = 0;
        while (i < self.path_list.names.len) : (i += 1) {
            if (std.mem.eql(u8, self.path_list.names[@intCast(i)], to)) break;
        }
        if (i < self.path_list.names.len) try self.switchToIndex(i);

        self.modal = .None;
        self.ui.active = null;
    }

    fn openRenamePathModal(self: *Self) void {
        if (self.path_list.names.len == 0) return;

        const cur = self.path_list.names[@intCast(self.selected)];

        self.new_path_len = @min(cur.len, self.new_path_buf.len);
        @memcpy(self.new_path_buf[0..self.new_path_len], cur[0..self.new_path_len]);

        self.new_path_input.caret = self.new_path_len;

        self.ui.active = Id.modal_create;
        self.modal = .{ .RenamePath = .{ .from_index = self.selected } };
    }

    fn renamePath(self: *Self, from: []const u8, to_raw: []const u8) !void {
        const to = std.mem.trim(u8, to_raw, " \t\r\n");
        if (to.len == 0) return;
        if (std.mem.eql(u8, from, to)) return;
        if (self.pathNameExists(to)) return;

        const def = self.paths.getPath(from) orelse return;

        try self.paths.savePath(to, def);
        try self.paths.deletePath(from);
        try self.path_list.rebuild(&self.paths);

        var i: u32 = 0;
        while (i < self.path_list.names.len) : (i += 1) {
            if (std.mem.eql(u8, self.path_list.names[@intCast(i)], to)) break;
        }
        if (i < self.path_list.names.len) try self.switchToIndex(i);

        self.modal = .None;
    }

    fn openCreatePathModal(self: *Self) void {
        self.new_path_len = 0;
        @memset(self.new_path_buf[0..], 0);
        self.new_path_input.caret = 0;

        self.ui.active = Id.modal_create;
        self.modal = .CreatePath;
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
            .CreatePath => {
                const raw = self.new_path_buf[0..self.new_path_len];

                // basic sanitize: trim spces
                const name = std.mem.trim(u8, raw, " \r\t\n");

                const name_ok = name.len > 0 and !self.pathNameExists(name);

                const err: ?[:0]const u8 = if (raw.len == 0) null else if (name.len == 0) "Name can't be empty" else if (self.pathNameExists(name)) "Name already exists" else null;

                const r = CreatePathModal.draw(
                    &self.ui,
                    self.font,
                    &self.new_path_input,
                    self.new_path_buf[0..],
                    &self.new_path_len,
                    name_ok,
                    err,
                );

                switch (r.action) {
                    .None => {},
                    .Cancel => {
                        self.modal = .None;
                        self.ui.active = null;
                    },
                    .Create => try self.createNewPath(std.mem.trim(u8, self.new_path_buf[0..self.new_path_len], " \t\r\n")),
                }
            },
            .RenamePath => |m| {
                const from_name = self.path_list.names[@intCast(m.from_index)];

                const raw = self.new_path_buf[0..self.new_path_len];
                const name = std.mem.trim(u8, raw, " \r\n\t");

                const same = std.mem.eql(u8, name, from_name);
                const exists = self.pathNameExists(name);

                const name_ok = name.len > 0 and (!exists or same);

                const err: ?[:0]const u8 = if (raw.len == 0) null else if (name.len == 0) "Name can't be empty" else if (exists and !same) "Name already exists" else null;

                const r = CreatePathModal.draw(
                    &self.ui,
                    self.font,
                    &self.new_path_input,
                    self.new_path_buf[0..],
                    &self.new_path_len,
                    name_ok,
                    err,
                );

                switch (r.action) {
                    .None => {},
                    .Cancel => {
                        self.modal = .None;
                        self.ui.active = null;
                    },
                    .Create => {
                        if (!same) try self.renamePath(from_name, name);
                        self.modal = .None;
                    },
                }
            },
            .DeletePath => |m| {
                const name = self.path_list.names[@intCast(m.index)];

                const act = ConfirmDeleteModal.draw(&self.ui, self.font, name);
                switch (act) {
                    .None => {},
                    .No => self.modal = .None,
                    .Yes => {
                        try self.paths.deletePath(name);
                        try self.path_list.rebuild(&self.paths);

                        if (self.path_list.names.len == 0) {
                            self.editor.clear();
                            self.selected = 0;
                        } else {
                            const next = @min(m.index, @as(u32, @intCast(self.path_list.names.len - 1)));
                            try self.switchToIndex(next);
                        }

                        self.modal = .None;
                    },
                }
            },
            .DuplicatePath => |m| {
                const from_name = self.path_list.names[@intCast(m.from_index)];

                const raw = self.new_path_buf[0..self.new_path_len];
                const name = std.mem.trim(u8, raw, " \r\n\t");

                const exists = self.pathNameExists(name);
                const name_ok = name.len > 0 and !exists;

                const err: ?[:0]const u8 =
                    if (raw.len == 0) null else if (name.len == 0) "Name can't be empty" else if (exists) "Name already exists" else null;

                const r = CreatePathModal.draw(
                    &self.ui,
                    self.font,
                    &self.new_path_input,
                    self.new_path_buf[0..],
                    &self.new_path_len,
                    name_ok,
                    err,
                );

                switch (r.action) {
                    .None => {},
                    .Cancel => {
                        self.modal = .None;
                        self.ui.active = null;
                    },
                    .Create => {
                        try self.duplicatePath(from_name, name);
                    },
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
