const std = @import("std");
const rl = @import("raylib");

const ui_mod = @import("../ui.zig");
const Ui = ui_mod.Ui;

const button = @import("../button.zig");
const text_input = @import("../text_input.zig");
const ids = @import("../ids.zig");

pub const Action = enum { None, Create, Cancel };

pub const Result = struct {
    action: Action = .None,
    name: []const u8 = "",
    name_changed: bool = false,
};

pub fn draw(
    ui: *Ui,
    font: rl.Font,
    input_state: *text_input.State,
    buf: []u8,
    len: *usize,
    name_ok: bool,
    err_msg: ?[:0]const u8,
) Result {
    const sw = @as(f32, @floatFromInt(rl.getScreenWidth()));
    const sh = @as(f32, @floatFromInt(rl.getScreenHeight()));

    rl.drawRectangle(0, 0, @intFromFloat(sw), @intFromFloat(sh), rl.fade(rl.Color.black, 0.45));

    const dlg_w: f32 = 520;
    const dlg_h: f32 = 220;
    const dlg = rl.Rectangle{
        .x = (sw - dlg_w) * 0.5,
        .y = (sh - dlg_h) * 0.5,
        .width = dlg_w,
        .height = dlg_h,
    };

    rl.drawRectangleRec(dlg, rl.Color.light_gray);
    rl.drawRectangleLinesEx(dlg, 1, rl.Color.gray);

    rl.drawTextEx(font, "Create new path", .{ .x = dlg.x + 18, .y = dlg.y + 16 }, 20, 0, rl.Color.black);
    rl.drawTextEx(font, "Name:", .{ .x = dlg.x + 18, .y = dlg.y + 60 }, 18, 0, rl.Color.dark_gray);

    const input_rect = rl.Rectangle{
        .x = dlg.x + 90,
        .y = dlg.y + 52,
        .width = dlg.width - 108,
        .height = 44,
    };

    const ti = text_input.textInput(
        ui,
        input_state,
        ids.Id.modal_create,
        input_rect,
        font,
        buf,
        len,
        40,
        .{},
    );

    var out: Result = .{
        .name = buf[0..len.*],
        .name_changed = ti.changed,
    };

    if (ti.canceled) out.action = .Cancel;
    if (ti.submitted and name_ok) out.action = .Create;

    if (err_msg) |e| {
        rl.drawTextEx(font, e, .{ .x = dlg.x + 18, .y = dlg.y + 110 }, 16, 0, rl.Color.maroon);
    }

    const row = rl.Rectangle{
        .x = dlg.x + 18,
        .y = dlg.y + dlg.height - 56,
        .width = dlg.width - 36,
        .height = 40,
    };

    const bw: f32 = 130;
    const gap: f32 = 10;

    const r_create = rl.Rectangle{ .x = row.x, .y = row.y, .width = bw, .height = row.height };
    const r_cancel = rl.Rectangle{ .x = row.x + bw + gap, .y = row.y, .width = bw, .height = row.height };

    if (button.button(ui, ids.Id.modal_create_ok, r_create, font, "Create", name_ok, .{}).clicked) out.action = .Create;
    if (button.button(ui, ids.Id.modal_create_cancel, r_cancel, font, "Cancel", true, .{}).clicked) out.action = .Cancel;

    return out;
}
