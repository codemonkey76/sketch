const rl = @import("raylib");
const ui_mod = @import("ui.zig");
const std = @import("std");

const Ui = ui_mod.Ui;
const WidgetId = ui_mod.WidgetId;

/// Persistent state (store in AppModel)
pub const State = struct {
    hovered: bool = false,
};

pub const Params = struct {
    pad: f32 = 10.0,
    font_px: f32 = 18.0,
};

pub const Result = struct {
    hovered: bool,
    local_x: f32,
    local_y: f32,
};

pub fn canvas(
    ui: *Ui,
    state: *State,
    id: WidgetId,
    bounds: rl.Rectangle,
    font: rl.Font,
    p: Params,
) Result {
    const hovered = ui.hit(id, bounds);
    state.hovered = hovered;

    // Draw background + border
    rl.drawRectangleRec(bounds, rl.Color.ray_white);
    rl.drawRectangleLinesEx(bounds, 1, rl.Color.gray);

    // Local mouse coords (relative to top-left of canvas)
    const lx = ui.mouse.x - bounds.x;
    const ly = ui.mouse.y - bounds.y;

    // If hovered, show coords
    if (hovered) {
        var buf: [128:0]u8 = undefined;
        const s = std.fmt.bufPrintZ(&buf, "x: {d:.1}  y: {d:.1}", .{ lx, ly }) catch "x:? y:?";

        rl.drawTextEx(
            font,
            s,
            .{ .x = bounds.x + p.pad, .y = bounds.y + p.pad },
            p.font_px,
            0.0,
            rl.Color.dark_gray,
        );
    }

    return .{
        .hovered = hovered,
        .local_x = lx,
        .local_y = ly,
    };
}
