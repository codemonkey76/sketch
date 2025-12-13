const rl = @import("raylib");

pub fn splitV(bounds: rl.Rectangle, pos: f32, gap: f32) struct { top: rl.Rectangle, rest: rl.Rectangle } {
    const top = rl.Rectangle{
        .x = bounds.x,
        .y = bounds.y,
        .width = bounds.width,
        .height = pos,
    };

    const rest_y = bounds.y + pos + gap;
    const rest_h = @max(0.0, (bounds.y + bounds.height) - rest_y);

    const rest = rl.Rectangle{
        .x = bounds.x,
        .y = rest_y,
        .width = bounds.width,
        .height = rest_h,
    };

    return .{ .top = top, .rest = rest };
}

pub fn splitH(bounds: rl.Rectangle, pos: f32, gap: f32) struct { left: rl.Rectangle, rest: rl.Rectangle } {
    const left = rl.Rectangle{
        .x = bounds.x,
        .y = bounds.y,
        .width = pos,
        .height = bounds.height,
    };

    const rest_x = bounds.x + pos + gap;
    const rest_w = @max(0.0, (bounds.x + bounds.width) - rest_x);

    const rest = rl.Rectangle{
        .x = rest_x,
        .y = bounds.y,
        .width = rest_w,
        .height = bounds.height,
    };

    return .{ .left = left, .rest = rest };
}

pub const Flow = struct {
    row: rl.Rectangle,
    x: f32,
    gap: f32 = 8.0,
    pad_x: f32 = 12.0,
    pad_y: f32 = 8.0,

    pub fn init(row: rl.Rectangle) Flow {
        return .{ .row = row, .x = row.x };
    }

    pub fn next(self: *Flow, w: f32, h: f32) rl.Rectangle {
        const y = self.row.y + (self.row.height - h) * 0.5;
        const r = rl.Rectangle{ .x = self.x, .y = y, .width = w, .height = h };
        self.x += w + self.gap;
        return r;
    }

    pub fn nextButton(self: *Flow, font: rl.Font, font_px: f32, label: [:0]const u8) rl.Rectangle {
        const tw = rl.measureTextEx(font, label, font_px, 0).x;
        const th = font_px;
        return self.next(tw + self.pad_x * 2, th + self.pad_y * 2);
    }
};
