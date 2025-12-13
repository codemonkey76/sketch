const rl = @import("raylib");

const ui_mod = @import("../ui.zig");
const Ui = ui_mod.Ui;

const button = @import("../button.zig");
const ids = @import("../ids.zig");

pub const Action = enum { None, Yes, No, Cancel };

pub fn draw(ui: *Ui, font: rl.Font) Action {
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

    rl.drawRectangleRec(dlg, rl.Color.light_gray);
    rl.drawRectangleLinesEx(dlg, 1, rl.Color.gray);

    const msg = "Save changes?";
    rl.drawTextEx(font, msg, .{ .x = dlg.x + 18, .y = dlg.y + 18 }, 20, 0, rl.Color.black);

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

    if (button.button(ui, ids.Id.modal_yes, r_yes, font, "Yes", true, .{}).clicked) return .Yes;
    if (button.button(ui, ids.Id.modal_no, r_no, font, "No", true, .{}).clicked) return .No;
    if (button.button(ui, ids.Id.modal_cancel, r_can, font, "Cancel", true, .{}).clicked) return .Cancel;

    return .None;
}
