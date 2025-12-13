const rl = @import("raylib");

const ui_mod = @import("ui.zig");

const Ui = ui_mod.Ui;
const WidgetId = ui_mod.WidgetId;

/// Persistent scrollbar state (store this in Model)
pub const State = struct {
    /// Normalized scroll position (0 = top, 1 = bottom)
    t: f32 = 0.0,

    /// Internal: mouse grab offset inside handle (pixels)
    grab_y: f32 = 0.0,
};

/// Scrollbar configuration (stateless)
pub const Params = struct {
    /// Total scrollable content height (px)
    content_h: f32,

    /// Visible viewport height (px)
    viewport_h: f32,

    /// Minimum handle size (px)
    min_handle_h: f32 = 18.0,

    /// Scroll wheel speed in pixels per notch
    wheel_px: f32 = 40.0,
};

/// Scrollbar output
pub const Result = struct {
    /// Normalized scroll position (0..1)
    t: f32,

    /// Pixel scroll offset (0..max)
    scroll_px: f32,

    /// True while handle is being dragged
    dragging: bool,
};

fn clamp(x: f32, lo: f32, hi: f32) f32 {
    if (x < lo) return lo;
    if (x > hi) return hi;
    return x;
}

fn clamp01(x: f32) f32 {
    return clamp(x, 0.0, 1.0);
}

/// Vertical scrollbar (immediate-mode)
///
/// `track` is the full scrollbar_rect (background + handle)
/// `is_base` must be stable per scrollbar instance
pub fn scrollbarV(
    ui: *Ui,
    state: *State,
    id_base: WidgetId,
    track: rl.Rectangle,
    p: Params,
) Result {
    const max_scroll_px = @max(0.0, p.content_h - p.viewport_h);
    const can_scroll = max_scroll_px > 0.5;

    // Clamp normalized position
    state.t = if (can_scroll) clamp01(state.t) else 0.0;

    // Handle sizing
    const track_h = track.height;
    const handle_h =
        if (!can_scroll)
            track_h
        else
            @max(p.min_handle_h, track_h * (p.viewport_h / p.content_h));

    const range_px = @max(0.0, track_h - handle_h);

    const handle_y = track.y + if (can_scroll and range_px > 0.0)
        range_px * state.t
    else
        0.0;

    const handle = rl.Rectangle{
        .x = track.x,
        .y = handle_y,
        .width = track.width,
        .height = handle_h,
    };

    const track_id: WidgetId = id_base;
    const handle_id: WidgetId = id_base + 1;

    const over_handle = ui.hit(handle_id, handle);
    const over_track = ui.hit(track_id, track);

    // Begin drag
    if (can_scroll and over_handle and ui.mouse_pressed) {
        ui.active = handle_id;
        state.grab_y = ui.mouse.y - handle.y;
    }

    const dragging = can_scroll and
        ui.active != null and
        ui.active.? == handle_id and
        ui.mouse_down;

    if (dragging) {
        var new_y = ui.mouse.y - state.grab_y;
        new_y = clamp(new_y, track.y, track.y + range_px);

        state.t =
            if (range_px > 0.0)
                (new_y - track.y) / range_px
            else
                0.0;

        state.t = clamp01(state.t);
    }

    // Page jump on track click
    else if (can_scroll and over_track and ui.mouse_pressed and !over_handle) {
        const page = p.viewport_h / p.content_h;
        if (ui.mouse.y < handle.y) {
            state.t = clamp01(state.t - page);
        } else if (ui.mouse.y > handle.y + handle.height) {
            state.t = clamp01(state.t + page);
        }
    }

    // Mouse wheel (only when hovering track)
    if (can_scroll and over_track and ui.wheel != 0.0) {
        const cur_px = state.t * max_scroll_px;
        const next_px = clamp(
            cur_px - ui.wheel * p.wheel_px,
            0.0,
            max_scroll_px,
        );
        state.t = if (max_scroll_px > 0.0) next_px / max_scroll_px else 0.0;
        state.t = clamp01(state.t);

        // snap to ends to avoid "almost top/bottom" float residue
        if (state.t < 0.0005) state.t = 0.0;
        if (state.t > 0.9995) state.t = 1.0;
    }

    // Draw track
    rl.drawRectangleRec(track, rl.Color.light_gray);
    rl.drawRectangleLinesEx(track, 1, rl.Color.gray);

    // Draw handle
    const is_active = ui.active != null and ui.active.? == handle_id;
    const is_hot = ui.hot != null and ui.hot.? == handle_id;

    const handle_col =
        if (!can_scroll)
            rl.Color.gray
        else if (is_active)
            rl.Color.dark_gray
        else if (is_hot)
            rl.Color.gray
        else
            rl.Color.gray;

    rl.drawRectangleRec(handle, handle_col);
    rl.drawRectangleLinesEx(handle, 1, rl.Color.black);

    const scroll_px = state.t * max_scroll_px;

    return .{
        .t = state.t,
        .scroll_px = scroll_px,
        .dragging = dragging,
    };
}
