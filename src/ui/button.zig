const rl = @import("raylib");
const ui_mod = @import("ui.zig");

const Ui = ui_mod.Ui;
const WidgetId = ui_mod.WidgetId;

/// Persistent state (store in AppModel if you want per-button memory later)
pub const State = struct {};

pub const Params = struct {
    font_px: f32 = 18.0,
    pad_x: f32 = 12.0,
    pad_y: f32 = 8.0,
};

pub const Result = struct {
    clicked: bool,
    held: bool,
    hovered: bool,
};

pub fn button(
    ui: *Ui,
    id: WidgetId,
    bounds: rl.Rectangle,
    font: rl.Font,
    label: [:0]const u8,
    enabled: bool,
    p: Params,
) Result {
    if (!enabled) {
        // --- draw disabled ---
        rl.drawRectangleRec(bounds, rl.Color.light_gray);
        rl.drawRectangleLinesEx(bounds, 1, rl.Color.gray);

        const text_w = rl.measureTextEx(font, label, p.font_px, 0).x;
        const text_h = p.font_px;

        const pos = rl.Vector2{
            .x = bounds.x + (bounds.width - text_w) * 0.5,
            .y = bounds.y + (bounds.height - text_h) * 0.5,
        };

        rl.drawTextEx(font, label, pos, p.font_px, 0, rl.Color.dark_gray);

        return .{
            .clicked = false,
            .held = false,
            .hovered = false,
        };
    }

    const hovered = ui.hit(id, bounds);

    // Begin press
    if (hovered and ui.mouse_pressed) {
        ui.active = id;
    }

    const held =
        ui.active != null and
        ui.active.? == id and
        ui.mouse_down;

    const released =
        ui.active != null and
        ui.active.? == id and
        ui.mouse_released;

    const clicked = released and hovered;

    // --- visuals ---
    const bg =
        if (held)
            rl.Color.dark_gray
        else if (hovered)
            rl.Color.light_gray
        else
            rl.Color.gray;

    const offset_y: f32 = if (held) 2.0 else 0.0;

    rl.drawRectangleRec(bounds, bg);
    rl.drawRectangleLinesEx(bounds, 1, rl.Color.black);

    // Center text (slightly lower when held)
    const text_w = rl.measureTextEx(font, label, p.font_px, 0).x;
    const text_h = p.font_px;

    const text_pos = rl.Vector2{
        .x = bounds.x + (bounds.width - text_w) * 0.5,
        .y = bounds.y + (bounds.height - text_h) * 0.5 + offset_y,
    };

    rl.drawTextEx(font, label, text_pos, p.font_px, 0, rl.Color.black);

    // Clear active on mouse up (safety)
    if (ui.active != null and ui.active.? == id and ui.mouse_released) {
        ui.active = null;
    }

    return .{
        .clicked = clicked,
        .held = held,
        .hovered = hovered,
    };
}
