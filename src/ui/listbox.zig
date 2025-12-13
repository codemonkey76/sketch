const std = @import("std");
const rl = @import("raylib");

const ui_mod = @import("ui.zig");
const Ui = ui_mod.Ui;
const WidgetId = ui_mod.WidgetId;

const scrollbar = @import("scrollbar.zig");

/// Persistent state for a single listbox instance.
pub const State = struct {
    /// Pixel scroll offset from top of content (source of truth).
    scroll_px: f32 = 0.0,

    /// Persistent scrollbar state (only meaningful when scrolling is possible).
    sb: scrollbar.State = .{},
};

/// Stateless tuning parameters for listbox look/feel.
pub const Params = struct {
    /// Row height in pixels.
    row_h: f32 = 32.0,

    /// Font pixel size passed to drawTextEx.
    font_px: f32 = 18.0,

    /// Left padding for text.
    pad_x: f32 = 10.0,

    /// Extra space after the last row (padding under the last item).
    bottom_pad: f32 = 12.0,

    /// Minimum scrollbar handle size.
    min_handle_h: f32 = 18.0,

    /// Wheel speed (px per notch) when scrolling over list content.
    wheel_px: f32 = 60.0,

    /// Width of the scrollbar track.
    scrollbar_w: f32 = 16.0,

    /// Gap between content and scrollbar.
    scrollbar_gap: f32 = 6.0,

    /// If true, draw row outlines.
    debug_rows: bool = false,

    /// If true, caller can sprinkle their own debug prints around calls.
    debug_log: bool = false,
};

pub const Item = struct {
    id: u32,
    label: []const u8,
};

pub const Result = struct {
    /// Id of clicked item (null if none).
    picked: ?u32 = null,

    /// Currently selected item id (may change via keyboard).
    selected_id: u32,
};

/// Small bundle of rectangles derived from bounds + params.
const Layout = struct {
    content: rl.Rectangle,
    track: rl.Rectangle,
    visible_rows: usize,
    can_scroll: bool,
};

/// Scroll metrics derived from item count + bounds.
const Metrics = struct {
    content_h: f32,
    max_scroll_px: f32,
};

/// Clamp a float into [lo, hi].
fn clampF32(v: f32, lo: f32, hi: f32) f32 {
    return std.math.clamp(v, lo, hi);
}

/// Clamp normalized scrollbar position and snap to exact 0/1 near endpoints.
fn syncScrollT(sb: *scrollbar.State, scroll_px: f32, max_scroll_px: f32) void {
    sb.t = if (max_scroll_px > 0.0) (scroll_px / max_scroll_px) else 0.0;

    // Snap ends to avoid "almost top/bottom" float residue.
    if (sb.t < 0.0005) sb.t = 0.0;
    if (sb.t > 0.9995) sb.t = 1.0;
}

/// Adjust `scroll_px` just enough to make a row fully visible in the viewport.
fn ensureRowVisiblePx(
    scroll_px: *f32,
    row_index: usize,
    row_h: f32,
    viewport_h: f32,
    max_scroll_px: f32,
) void {
    const row_top = @as(f32, @floatFromInt(row_index)) * row_h;
    const row_bot = row_top + row_h;

    if (row_top < scroll_px.*) {
        scroll_px.* = row_top;
    } else if (row_bot > scroll_px.* + viewport_h) {
        scroll_px.* = row_bot - viewport_h;
    }

    scroll_px.* = clampF32(scroll_px.*, 0.0, max_scroll_px);
}

/// Compute how many whole rows fit, and split bounds into content + scrollbar track.
fn computeLayout(bounds: rl.Rectangle, total: usize, p: Params) Layout {
    const visible_f = bounds.height / p.row_h;
    const visible_rows: usize = @max(1, @as(usize, @intFromFloat(@floor(visible_f))));
    const can_scroll = total > visible_rows;

    const content_w: f32 = if (can_scroll)
        (bounds.width - p.scrollbar_w - p.scrollbar_gap)
    else
        bounds.width;

    return .{
        .visible_rows = visible_rows,
        .can_scroll = can_scroll,
        .content = .{
            .x = bounds.x,
            .y = bounds.y,
            .width = content_w,
            .height = bounds.height,
        },
        .track = .{
            .x = bounds.x + content_w + p.scrollbar_gap,
            .y = bounds.y,
            .width = p.scrollbar_w,
            .height = bounds.height,
        },
    };
}

/// Compute content height + max scroll range.
fn computeMetrics(total: usize, viewport_h: f32, p: Params) Metrics {
    const content_h: f32 = @as(f32, @floatFromInt(total)) * p.row_h + p.bottom_pad;
    const max_scroll_px: f32 = @max(0.0, content_h - viewport_h);
    return .{ .content_h = content_h, .max_scroll_px = max_scroll_px };
}

/// Find the index for a selected id (null if not found).
fn findSelectedIndex(items: []const Item, selected_id: u32) ?usize {
    for (items, 0..) |it, i| {
        if (it.id == selected_id) return i;
    }
    return null;
}

/// Compute visible range [start, end) given pixel scroll.
fn computeWindow(total: usize, scroll_px: f32, row_h: f32, visible_rows: usize) struct { start: usize, end: usize } {
    const start: usize = if (row_h > 0.0)
        @min(total, @as(usize, @intFromFloat(@floor(scroll_px / row_h))))
    else
        0;

    const end: usize = @min(total, start + visible_rows + 2); // +2 for partial rows at edges
    return .{ .start = start, .end = end };
}

/// Handle arrow/home/end navigation and keep selection in view.
fn handleKeyboardNav(
    over_listbox: bool,
    items: []const Item,
    selected_index: ?usize,
    out: *Result,
    state: *State,
    viewport_h: f32,
    p: Params,
    max_scroll_px: f32,
) void {
    const total = items.len;
    if (!over_listbox or total == 0) return;

    var idx: usize = selected_index orelse 0;
    var changed = false;

    if (rl.isKeyPressed(rl.KeyboardKey.down)) {
        if (idx + 1 < total) {
            idx += 1;
            changed = true;
        }
    } else if (rl.isKeyPressed(rl.KeyboardKey.up)) {
        if (idx > 0) {
            idx -= 1;
            changed = true;
        }
    } else if (rl.isKeyPressed(rl.KeyboardKey.home)) {
        idx = 0;
        changed = true;
    } else if (rl.isKeyPressed(rl.KeyboardKey.end)) {
        idx = total - 1;
        changed = true;
    }

    if (changed) {
        out.selected_id = items[idx].id;
        ensureRowVisiblePx(&state.scroll_px, idx, p.row_h, viewport_h, max_scroll_px);
    }
}

/// Drive scroll state from scrollbar + wheel. Keeps ownership rules consistent:
/// - Track hover wheel is handled by scrollbarV.
/// - Content hover wheel is handled here (excluding the track).
fn handleScroll(
    ui: *Ui,
    state: *State,
    id_base: WidgetId,
    layout: Layout,
    metrics: Metrics,
    over_listbox: bool,
    over_track: bool,
    p: Params,
) void {
    // Always clamp.
    state.scroll_px = clampF32(state.scroll_px, 0.0, metrics.max_scroll_px);

    if (!layout.can_scroll) {
        state.scroll_px = 0.0;
        state.sb.t = 0.0;
        return;
    }

    // Keep handle in sync before calling scrollbar (so it renders correctly).
    syncScrollT(&state.sb, state.scroll_px, metrics.max_scroll_px);

    const sb_res = scrollbar.scrollbarV(ui, &state.sb, id_base + 100_000, layout.track, .{
        .content_h = metrics.content_h,
        .viewport_h = layout.content.height,
        .min_handle_h = p.min_handle_h,
        // Keep scrollbar track wheel speed consistent with listbox.
        .wheel_px = p.wheel_px,
    });

    if (sb_res.dragging) {
        // Drag owns scroll_px.
        state.scroll_px = clampF32(sb_res.scroll_px, 0.0, metrics.max_scroll_px);
    } else {
        // Pixel scroll owns t when not dragging.
        syncScrollT(&state.sb, state.scroll_px, metrics.max_scroll_px);
        state.scroll_px = clampF32(state.scroll_px, 0.0, metrics.max_scroll_px);
    }

    // Wheel over list content (exclude track to avoid double-consumption).
    if (over_listbox and !over_track and ui.wheel != 0.0) {
        state.scroll_px = clampF32(
            state.scroll_px - ui.wheel * p.wheel_px,
            0.0,
            metrics.max_scroll_px,
        );
        syncScrollT(&state.sb, state.scroll_px, metrics.max_scroll_px);
    }
}

/// Draw listbox background + border.
fn drawChrome(bounds: rl.Rectangle, content: rl.Rectangle) void {
    rl.drawRectangleRec(content, rl.Color.white);
    rl.drawRectangleLinesEx(bounds, 1, rl.Color.gray);
}

/// Draw rows and handle clicking/hovering. Returns updated selection/picked.
fn drawRows(
    ui: *Ui,
    state: *State,
    id_base: WidgetId,
    layout: Layout,
    metrics: Metrics,
    font: rl.Font,
    items: []const Item,
    out: *Result,
    p: Params,
) void {
    const total = items.len;
    const win = computeWindow(total, state.scroll_px, p.row_h, layout.visible_rows);
    const base_y: f32 = layout.content.y - state.scroll_px;

    var buf: [256]u8 = undefined;

    rl.beginScissorMode(
        @intFromFloat(layout.content.x),
        @intFromFloat(layout.content.y),
        @intFromFloat(layout.content.width),
        @intFromFloat(layout.content.height),
    );
    defer rl.endScissorMode();

    for (items[win.start..win.end], 0..) |it, i| {
        const row_index = win.start + i;
        const row_y = base_y + @as(f32, @floatFromInt(row_index)) * p.row_h;

        const row_rect = rl.Rectangle{
            .x = layout.content.x,
            .y = row_y,
            .width = layout.content.width,
            .height = p.row_h,
        };

        const row_id: WidgetId = id_base + @as(u32, @intCast(row_index));
        const hovered = ui.hit(row_id, row_rect);

        if (hovered and ui.mouse_pressed) ui.active = row_id;

        const clicked =
            ui.active != null and ui.active.? == row_id and hovered and ui.mouse_released;

        if (clicked) {
            out.picked = it.id;
            out.selected_id = it.id;

            ensureRowVisiblePx(&state.scroll_px, row_index, p.row_h, layout.content.height, metrics.max_scroll_px);
            syncScrollT(&state.sb, state.scroll_px, metrics.max_scroll_px);
        }

        const is_sel = it.id == out.selected_id;
        const bg =
            if (is_sel) rl.Color.sky_blue else if (hovered) rl.Color.light_gray else rl.Color.white;

        rl.drawRectangleRec(row_rect, bg);
        if (p.debug_rows) rl.drawRectangleLinesEx(row_rect, 1, rl.Color.dark_gray);

        const text_y = row_rect.y + (p.row_h - p.font_px) * 0.5 - 1.0;

        const s =
            if (it.label.len > 0)
                it.label
            else
                (std.fmt.bufPrintZ(&buf, "{d}", .{it.id}) catch "");
        var zbuf: [256:0]u8 = undefined;
        const z = std.fmt.bufPrintZ(&zbuf, "{s}", .{s}) catch "???";

        rl.drawTextEx(
            font,
            z,
            .{ .x = row_rect.x + p.pad_x, .y = text_y },
            p.font_px,
            0.0,
            rl.Color.dark_gray,
        );
    }
}

/// Immediate-mode listbox with optional scrollbar.
/// - Scrollbar only shown when content doesn't fit.
/// - Selection is driven by `selected_id` you pass in.
/// - Returns `picked` when user clicks a row (caller updates model).
/// - Returns updated `selected_id` when using keyboard navigation.
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
    var out: Result = .{ .selected_id = selected_id };

    const total: usize = items.len;
    const layout = computeLayout(bounds, total, p);
    const metrics = computeMetrics(total, bounds.height, p);

    const over_listbox = rl.checkCollisionPointRec(ui.mouse, bounds);
    const over_track = layout.can_scroll and rl.checkCollisionPointRec(ui.mouse, layout.track);

    // Clamp early so everything downstream is stable.
    state.scroll_px = clampF32(state.scroll_px, 0.0, metrics.max_scroll_px);

    const selected_index = findSelectedIndex(items, out.selected_id);

    handleKeyboardNav(
        over_listbox,
        items,
        selected_index,
        &out,
        state,
        bounds.height,
        p,
        metrics.max_scroll_px,
    );

    handleScroll(
        ui,
        state,
        id_base,
        layout,
        metrics,
        over_listbox,
        over_track,
        p,
    );

    drawChrome(bounds, layout.content);
    drawRows(ui, state, id_base, layout, metrics, font, items, &out, p);

    return out;
}
