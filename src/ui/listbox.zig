const std = @import("std");
const rl = @import("raylib");

const ui_mod = @import("ui.zig");
const Ui = ui_mod.Ui;
const WidgetId = ui_mod.WidgetId;

const scrollbar = @import("scrollbar.zig");

pub const State = struct {
    // First visible row index
    scroll_index: usize = 0,

    // Persistent scrollbar state (only used when scrolling is possible)
    sb: scrollbar.State = .{},
};

pub const Params = struct {
    /// Row height in pxels
    row_h: f32 = 32.0,

    /// Font pixel size passed to drawTextEx
    font_px: f32 = 18.0,

    /// Left padding for text
    pad_x: f32 = 10.0,

    /// Extra space after the last row (creates "padding under last row")
    bottom_pad: f32 = 12.0,

    /// Minimum scrollbar handlesize
    min_handle_h: f32 = 18.0,

    /// Wheel speed (px per notch) when hovering the scrollbar track
    wheel_px: f32 = 60.0,

    /// Width of scrollbar track
    scrollbar_w: f32 = 16.0,

    /// Gap between content and scrollbar
    scrollbar_gap: f32 = 6.0,

    /// If true, draw row outlines (debug)
    debug_rows: bool = false,
};

pub const Item = struct {
    id: u32,
    label: [:0]const u8,
};

pub const Result = struct {
    /// id of clicked item (null if none)
    picked: ?u32 = null,
};

fn clampUsize(v: usize, lo: usize, hi: usize) usize {
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

/// Immediate-mode listbox with optional scrollbar.
/// - Scrollbar is only shown when content doesn't fit.
/// - Selection is driven by `selected_id` you pass in.
/// - Returns `picked` when user clicks a row (you then update your model).
pub fn listBox(
    ui: *Ui,
    state: *State,
    id_base: WidgetId,
    bounds: rl.Rectangle,
    font: rl.Font,
    items: []const Item,
    selected_id: u32,
    p: Params,
) Result {
    var out: Result = .{};

    const total: usize = items.len;
    const row_h = p.row_h;

    // How many rows can we show?
    const visible: usize = @max(1, @as(usize, @intFromFloat(@floor(bounds.height / row_h))));
    const can_scroll = total > visible;

    // Compute content rect and (optional) scrollbar track rect.
    const content_w: f32 = if (can_scroll)
        (bounds.width - p.scrollbar_w - p.scrollbar_gap)
    else
        bounds.width;

    const content = rl.Rectangle{ .x = bounds.x, .y = bounds.y, .width = content_w, .height = bounds.height };

    const track = rl.Rectangle{
        .x = bounds.x + content_w + p.scrollbar_gap,
        .y = bounds.y,
        .width = p.scrollbar_w,
        .height = bounds.height,
    };

    // Clamp scroll index.
    const max_scroll_index: usize = if (can_scroll) (total - visible) else 0;
    state.scroll_index = clampUsize(state.scroll_index, 0, max_scroll_index);

    // If the scrollbar is visible, drive scroll_index from scrollbar scroll_px;
    var scroll_px: f32 = 0.0;

    if (can_scroll) {
        const content_h = @as(f32, @floatFromInt(total)) * row_h + p.bottom_pad;

        // Keep sb.t in sync with scroll_index (important when selection jumps etc.)
        const max_scroll_px = @max(0.0, content_h - bounds.height);
        if (max_scroll_px > 0.0) {
            const idx_px = @as(f32, @floatFromInt(state.scroll_index)) * row_h;
            state.sb.t = idx_px / max_scroll_px;
        } else {
            state.sb.t = 0.0;
        }

        const sb_res = scrollbar.scrollbarV(ui, &state.sb, id_base + 100_000, track, .{
            .content_h = content_h,
            .viewport_h = bounds.height,
            .min_handle_h = p.min_handle_h,
            .wheel_px = p.wheel_px,
        });

        scroll_px = sb_res.scroll_px;

        // Convert pixel scroll to row index, snap to row boundaries.
        state.scroll_index = clampUsize(
            @as(usize, @intFromFloat(@floor(scroll_px / row_h))),
            0,
            max_scroll_index,
        );
        scroll_px = @as(f32, @floatFromInt(state.scroll_index)) * row_h;
    }

    // Draw lst content (clip to content area);
    rl.drawRectangleRec(content, rl.Color.white);
    rl.drawRectangleLinesEx(bounds, 1, rl.Color.gray);

    rl.beginScissorMode(
        @intFromFloat(content.x),
        @intFromFloat(content.y),
        @intFromFloat(content.width),
        @intFromFloat(content.height),
    );
    defer rl.endScissorMode();

    const start = state.scroll_index;
    const end = @min(total, start + visible);

    // Top of "virtual content"
    const base_y: f32 = content.y - scroll_px;

    var buf: [256]u8 = undefined;

    for (items[start..end], 0..) |it, i| {
        const row_index = start + i;
        const row_y = base_y + @as(f32, @floatFromInt(row_index)) * row_h;

        const row_rect = rl.Rectangle{
            .x = content.x,
            .y = row_y,
            .width = content.width,
            .height = row_h,
        };

        const row_id: WidgetId = id_base + @as(u32, @intCast(row_index));
        const hovered = ui.hit(row_id, row_rect);

        if (hovered and ui.mouse_pressed) ui.active = row_id;

        const clicked = ui.active != null and ui.active.? == row_id and hovered and ui.mouse_released;
        if (clicked) out.picked = it.id;

        const is_sel = it.id == selected_id;

        const bg =
            if (is_sel) rl.Color.sky_blue else if (hovered) rl.Color.light_gray else rl.Color.white;

        rl.drawRectangleRec(row_rect, bg);

        if (p.debug_rows) {
            rl.drawRectangleLinesEx(row_rect, 1, rl.Color.dark_gray);
        }

        // Vertically center text in row (simple approximation).
        const text_y = row_rect.y + (row_h - p.font_px) * 0.5 - 1.0;

        // If caller passed a label, use it; otherwise show id.
        const label = it.label;
        const s =
            if (label.len > 0)
                label
            else
                (std.fmt.bufPrintZ(&buf, "{d}", .{it.id}) catch "");

        rl.drawTextEx(
            font,
            s,
            .{ .x = row_rect.x + p.pad_x, .y = text_y },
            p.font_px,
            0.0,
            rl.Color.dark_gray,
        );
    }

    return out;
}
