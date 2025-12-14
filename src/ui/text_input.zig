const std = @import("std");
const rl = @import("raylib");

const ui_mod = @import("ui.zig");
const Ui = ui_mod.Ui;
const WidgetId = ui_mod.WidgetId;

pub const State = struct {
    /// caret position in bytes (ASCII only for now)
    caret: usize = 0,
};

pub const Params = struct {
    font_px: f32 = 18.0,
    pad_x: f32 = 10.0,
    pad_y: f32 = 8.0,
};

pub const Result = struct {
    changed: bool = false,
    submitted: bool = false,
    focused: bool = false,
    canceled: bool = false,
};

fn clampUsize(v: usize, lo: usize, hi: usize) usize {
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

pub fn textInput(
    ui: *Ui,
    state: *State,
    id: WidgetId,
    bounds: rl.Rectangle,
    font: rl.Font,
    buf: []u8, // writable storage
    len: *usize, // current length (0..buf.len)
    max_len: usize, // usually buf.len
    p: Params,
) Result {
    var out: Result = .{};

    // hit + focus handling
    const hovered = ui.hit(id, bounds);

    if (hovered and ui.mouse_pressed) {
        ui.active = id;
        // naive caret: jump to end on click (good enough for now)
        state.caret = len.*;
    }

    const focused =
        ui.active != null and ui.active.? == id;

    out.focused = focused;

    // visuals
    const bg =
        if (!focused and hovered) rl.Color.light_gray else if (focused) rl.Color.white else rl.Color.white;

    rl.drawRectangleRec(bounds, bg);
    rl.drawRectangleLinesEx(bounds, 1, if (focused) rl.Color.black else rl.Color.gray);

    // handle input (only when focused)
    if (focused) {
        // cancel (escape)
        if (rl.isKeyPressed(rl.KeyboardKey.escape)) {
            out.canceled = true;
            ui.active = null; // blur
        }
        // backspace
        if (rl.isKeyPressed(rl.KeyboardKey.backspace)) {
            if (len.* > 0 and state.caret > 0) {
                // delete byte before caret
                const del_at = state.caret - 1;
                if (del_at < len.*) {
                    // shift left
                    var i: usize = del_at;
                    while (i + 1 < len.*) : (i += 1) {
                        buf[i] = buf[i + 1];
                    }
                    len.* -= 1;
                    state.caret -= 1;
                    out.changed = true;
                }
            }
        }

        // left/right
        if (rl.isKeyPressed(rl.KeyboardKey.left)) {
            state.caret = clampUsize(state.caret, 0, len.*);
            if (state.caret > 0) state.caret -= 1;
        }
        if (rl.isKeyPressed(rl.KeyboardKey.right)) {
            state.caret = clampUsize(state.caret, 0, len.*);
            if (state.caret < len.*) state.caret += 1;
        }

        // submit (enter)
        if (rl.isKeyPressed(rl.KeyboardKey.enter)) {
            out.submitted = true;
        }

        // typed characters (ASCII for now)
        while (true) {
            const ch: i32 = rl.getCharPressed();
            if (ch == 0) break;

            // printable ASCII range
            if (ch >= 32 and ch <= 126) {
                if (len.* < max_len) {
                    // insert at caret (shift right)
                    var i: usize = len.*;
                    while (i > state.caret) : (i -= 1) {
                        buf[i] = buf[i - 1];
                    }
                    buf[state.caret] = @as(u8, @intCast(ch));
                    len.* += 1;
                    state.caret += 1;
                    out.changed = true;
                }
            }
        }
    }

    // draw text
    // make a temporary Z string without allocating
    var zbuf: [256:0]u8 = undefined;
    const show_len = @min(len.*, zbuf.len - 1);
    @memcpy(zbuf[0..show_len], buf[0..show_len]);
    zbuf[show_len] = 0;

    const text_pos = rl.Vector2{
        .x = bounds.x + p.pad_x,
        .y = bounds.y + (bounds.height - p.font_px) * 0.5,
    };

    rl.drawTextEx(font, &zbuf, text_pos, p.font_px, 0.0, rl.Color.black);

    // draw caret
    if (focused) {
        // measure text up to caret
        var leftz: [256:0]u8 = undefined;
        const caret_len = @min(state.caret, leftz.len - 1);
        @memcpy(leftz[0..caret_len], buf[0..caret_len]);
        leftz[caret_len] = 0;

        const tw = rl.measureTextEx(font, &leftz, p.font_px, 0.0).x;

        const cx = text_pos.x + tw;
        const cy0 = bounds.y + p.pad_y;
        const cy1 = bounds.y + bounds.height - p.pad_y;

        rl.drawLine(
            @intFromFloat(cx),
            @intFromFloat(cy0),
            @intFromFloat(cx),
            @intFromFloat(cy1),
            rl.Color.black,
        );
    }

    // blur on click outside (simple)
    if (focused and ui.mouse_pressed and !hovered) {
        ui.active = null;
    }

    return out;
}
