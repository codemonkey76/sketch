const std = @import("std");
const sketch = @import("sketch");
const rl = @import("raylib");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    rl.setConfigFlags(.{ .window_resizable = true });

    rl.initWindow(900, 600, "zig gui");
    rl.setWindowMinSize(500, 400);
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    const font = try rl.loadFontEx("assets/fonts/inter/Inter_18pt-Regular.ttf", 18, null);
    rl.setTextureFilter(font.texture, rl.TextureFilter.point);

    var model = sketch.models.AppModel.init(alloc, font);
    defer model.deinit();

    var queue = std.ArrayList(sketch.models.AppMsg).empty;
    defer queue.deinit(alloc);

    while (model.running and !rl.windowShouldClose()) {
        queue.clearRetainingCapacity();
        try pollInput(alloc, &queue);
        try queue.append(alloc, .{ .Tick = rl.getFrameTime() });

        for (queue.items) |msg| {
            const cmd = model.update(msg);
            _ = cmd;
        }

        try model.view();
    }
}

fn pollInput(alloc: std.mem.Allocator, msgs: *std.ArrayList(sketch.models.AppMsg)) !void {
    const mx = @as(f32, @floatFromInt(rl.getMouseX()));
    const my = @as(f32, @floatFromInt(rl.getMouseY()));
    try msgs.append(alloc, .{ .MoveMouse = .{ .x = mx, .y = my } });

    if (rl.isMouseButtonPressed(rl.MouseButton.left)) {
        try msgs.append(alloc, .{ .MouseDown = .{ .button = rl.MouseButton.left } });
    }
    if (rl.isMouseButtonPressed(rl.MouseButton.right)) {
        try msgs.append(alloc, .{ .MouseDown = .{ .button = rl.MouseButton.right } });
    }
    if (rl.isMouseButtonReleased(rl.MouseButton.left)) {
        try msgs.append(alloc, .{ .MouseUp = .{ .button = rl.MouseButton.left } });
    }
    if (rl.isMouseButtonReleased(rl.MouseButton.right)) {
        try msgs.append(alloc, .{ .MouseUp = .{ .button = rl.MouseButton.right } });
    }

    if (rl.isKeyPressed(rl.KeyboardKey.q)) {
        try msgs.append(alloc, .{ .KeyDown = .{ .key = rl.KeyboardKey.q } });
    }

    if (rl.isKeyPressed(rl.KeyboardKey.f11)) {
        try msgs.append(alloc, .{ .KeyDown = .{ .key = rl.KeyboardKey.f11 } });
    }
    if (rl.isKeyPressed(rl.KeyboardKey.f3)) {
        try msgs.append(alloc, .{ .KeyDown = .{ .key = rl.KeyboardKey.f3 } });
    }
}
