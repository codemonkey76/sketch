const rl = @import("raylib");
const std = @import("std");
const arcade = @import("arcade_lib");

const ui_mod = @import("ui.zig");
const Ui = ui_mod.Ui;
const WidgetId = ui_mod.WidgetId;

pub const State = struct {
    hovered: bool = false,

    // dragging
    drag_index: ?usize = null,
    drag_off: arcade.Vec2 = .{ .x = 0, .y = 0 },
};

pub const Params = struct {
    pad: f32 = 10.0,
    font_px: f32 = 18.0,

    viewport_w: f32 = 224,
    viewport_h: f32 = 288,
    viewport_margin: f32 = 40,

    point_radius: f32 = 7.0,
    hit_radius: f32 = 10.0,
};

pub const Result = struct {
    hovered: bool,
    vp: rl.Rectangle,
    changed: bool,
};

pub fn canvasEditor(
    allocator: std.mem.Allocator,
    ui: *Ui,
    state: *State,
    id: WidgetId,
    bounds: rl.Rectangle,
    font: rl.Font,
    points: *std.ArrayList(arcade.Vec2),
    p: Params,
) !Result {
    const hovered = ui.hit(id, bounds);
    state.hovered = hovered;

    // background + border
    rl.drawRectangleRec(bounds, rl.Color.black);
    rl.drawRectangleLinesEx(bounds, 1, rl.Color.gray);

    const vp = fitAspectCenter(bounds, p.viewport_w, p.viewport_h, p.viewport_margin);
    rl.drawRectangleLinesEx(vp, 2, rl.Color.green);

    // draw points (as circles) + polyline for visibility
    drawPoints(vp, points.items, p.point_radius);

    var changed = false;

    if (hovered) {
        const m = rl.getMousePosition();

        // Find nearest point under cursor (in *screen* space)
        const hit = hitPoint(vp, points.items, m, p.hit_radius);

        // Right click removes (if hit)
        if (rl.isMouseButtonPressed(rl.MouseButton.right)) {
            if (hit) |idx| {
                _ = points.orderedRemove(idx);
                state.drag_index = null;
                changed = true;
            }
        }

        // Left click: start drag if hit, else add
        if (rl.isMouseButtonPressed(rl.MouseButton.left)) {
            if (hit) |idx| {
                state.drag_index = idx;

                const mp = mouseToPath(vp, m);
                const pt = points.items[idx];
                state.drag_off = .{ .x = mp.x - pt.x, .y = mp.y - pt.y };
            } else {
                const mp = mouseToPath(vp, m);
                try points.append(allocator, mp);
                changed = true;
            }
        }
    }

    // Dragging continues even if cursor leaves vp/bounds (your “inside and outside” goal)
    if (state.drag_index) |idx| {
        if (rl.isMouseButtonDown(rl.MouseButton.left)) {
            const m = rl.getMousePosition();
            const mp = mouseToPath(vp, m);
            points.items[idx] = .{
                .x = mp.x - state.drag_off.x,
                .y = mp.y - state.drag_off.y,
            };
            changed = true;
        } else {
            state.drag_index = null;
        }
    }

    // coords overlay (optional)
    if (hovered) {
        const m = rl.getMousePosition();
        const lx = m.x - bounds.x;
        const ly = m.y - bounds.y;
        var buf: [128:0]u8 = undefined;
        const s = std.fmt.bufPrintZ(&buf, "x: {d:.1}  y: {d:.1}", .{ lx, ly }) catch "x:? y:?";
        rl.drawTextEx(font, s, .{ .x = bounds.x + p.pad, .y = bounds.y + p.pad }, p.font_px, 0.0, rl.Color.dark_gray);
    }

    return .{ .hovered = hovered, .vp = vp, .changed = changed };
}

fn drawPoints(vp: rl.Rectangle, pts: []const arcade.Vec2, r: f32) void {
    // 1) Draw the bezier curve (sampled)
    drawBezierCurve(vp, pts);

    // 2) Draw control polygon (optional but useful)
    drawControlPolygon(vp, pts);

    // 3) Draw control points
    for (pts) |pt| {
        const s = pathToScreen(vp, pt);
        rl.drawCircleV(s, r, rl.Color.sky_blue);
        rl.drawCircleLines(@intFromFloat(s.x), @intFromFloat(s.y), r, rl.Color.black);
    }
}
fn drawControlPolygon(vp: rl.Rectangle, pts: []const arcade.Vec2) void {
    if (pts.len < 2) return;

    for (pts[0 .. pts.len - 1], 0..) |a, i| {
        const b = pts[i + 1];
        rl.drawLineEx(pathToScreen(vp, a), pathToScreen(vp, b), 2, rl.Color.dark_gray);
    }
}

fn drawBezierCurve(vp: rl.Rectangle, pts: []const arcade.Vec2) void {
    // Need at least 4 points for 1 cubic
    if (pts.len < 4) return;

    // The library expects 1 + 3*n control points (4, 7, 10, ...)
    // If you’re mid-edit and don’t match, just draw what we can.
    const usable_len: usize = 1 + ((pts.len - 1) / 3) * 3; // clamp down to valid length
    if (usable_len < 4) return;

    const def = arcade.PathDefinition{ .control_points = pts[0..usable_len] };
    const seg_count = def.getSegmentCount();
    if (seg_count == 0) return;

    // sampling density: scale with viewport size (tweak)
    const steps_per_seg: usize = @max(12, @as(usize, @intFromFloat(@floor(@max(vp.width, vp.height) / 20.0))));

    var prev: ?rl.Vector2 = null;

    var s: usize = 0;
    while (s < seg_count) : (s += 1) {
        const seg = def.getSegment(s) orelse continue;

        var i: usize = 0;
        while (i <= steps_per_seg) : (i += 1) {
            const t: f32 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps_per_seg));
            const p = seg.evaluate(t);
            const sp = pathToScreen(vp, p);

            if (prev) |a| {
                rl.drawLineEx(a, sp, 3, rl.Color.yellow);
            }
            prev = sp;
        }
    }
}
fn hitPoint(vp: rl.Rectangle, pts: []const arcade.Vec2, m: rl.Vector2, hit_r: f32) ?usize {
    const hit_r2 = hit_r * hit_r;
    var best_i: ?usize = null;
    var best_d2: f32 = 0;

    for (pts, 0..) |pt, i| {
        const s = pathToScreen(vp, pt);
        const dx = m.x - s.x;
        const dy = m.y - s.y;
        const d2 = dx * dx + dy * dy;
        if (d2 <= hit_r2 and (best_i == null or d2 < best_d2)) {
            best_i = i;
            best_d2 = d2;
        }
    }
    return best_i;
}

fn pathToScreen(vp: rl.Rectangle, p: arcade.Vec2) rl.Vector2 {
    return .{
        .x = vp.x + p.x * vp.width,
        .y = vp.y + p.y * vp.height,
    };
}

fn mouseToPath(vp: rl.Rectangle, m: rl.Vector2) arcade.Vec2 {
    return .{
        .x = (m.x - vp.x) / vp.width,
        .y = (m.y - vp.y) / vp.height,
    };
}

fn fitAspectCenter(bounds: rl.Rectangle, width: f32, height: f32, margin: f32) rl.Rectangle {
    const ar = width / height;

    const avail_w = @max(0.0, bounds.width - margin * 2.0);
    const avail_h = @max(0.0, bounds.height - margin * 2.0);

    var w = avail_w;
    var h = w / ar;

    if (h > avail_h) {
        h = avail_h;
        w = h * ar;
    }

    return .{
        .x = bounds.x + (bounds.width - w) * 0.5,
        .y = bounds.y + (bounds.height - h) * 0.5,
        .width = w,
        .height = h,
    };
}
