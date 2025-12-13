const std = @import("std");
const rl = @import("raylib");
const Ui = @import("../ui/ui.zig").Ui;
const listbox = @import("../ui/listbox.zig");

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

pub const AppModel = struct {
    allocator: std.mem.Allocator,
    running: bool = true,
    mouse_x: f32 = 0,
    mouse_y: f32 = 0,
    font: rl.Font,

    ui: Ui = .{},
    list_state: listbox.State = .{},
    selected: u32 = 0,
    debug_log: bool = false,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, font: rl.Font) AppModel {
        return .{
            .allocator = allocator,
            .font = font,
        };
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

        var items: [30]listbox.Item = undefined;
        var labels: [30][32:0]u8 = undefined;

        for (items[0..], 0..) |*it, i| {
            const label = std.fmt.bufPrintZ(&labels[i], "Item {d}", .{i}) catch "???";
            it.* = .{
                .id = @as(u32, @intCast(i)),
                .label = label,
            };
        }

        // Get window dimensions (handles resizing automatically)
        const window_h = @as(f32, @floatFromInt(rl.getScreenHeight()));

        // Create rectangle that fills the window height (with some margin)
        const margin = 20.0;
        const r = rl.Rectangle{
            .x = margin,
            .y = margin,
            .width = 260,
            .height = window_h - (margin * 2),
        };

        const res = listbox.listBox(
            &self.ui,
            &self.list_state,
            2000,
            r,
            self.font,
            items[0..],
            self.selected,
            .{
                .debug_rows = false,
                .debug_log = self.debug_log,
            },
        );

        // Update selection from both click and keyboard navigation
        if (res.picked) |id| {
            self.selected = id;
        } else {
            self.selected = res.selected_id;
        }
    }
};
