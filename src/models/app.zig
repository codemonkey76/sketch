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
                }
            },
            else => {},
        }

        return .None;
    }

    pub fn view(self: *Self) !void {
        self.ui.beginFrame();

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.black);

        var items: [10]listbox.Item = undefined;

        for (items[0..], 0..) |*it, i| {
            it.* = .{
                .id = @as(u32, @intCast(i)),
                .label = "",
            };
        }
        const r = rl.Rectangle{ .x = 20, .y = 90, .width = 260, .height = 480 };

        const res = listbox.listBox(
            &self.ui,
            &self.list_state,
            2000,
            r,
            self.font,
            items[0..],
            self.selected,
            .{ .debug_rows = false },
        );

        if (res.picked) |id| self.selected = id;
    }
};
