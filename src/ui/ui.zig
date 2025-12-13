const rl = @import("raylib");

pub const WidgetId = u32;

pub const Ui = struct {
    hot: ?WidgetId = null,
    active: ?WidgetId = null,

    mouse: rl.Vector2 = .{ .x = 0, .y = 0 },
    mouse_down: bool = false,
    mouse_pressed: bool = false,
    mouse_released: bool = false,
    wheel: f32 = 0,

    pub fn beginFrame(self: *Ui) void {
        self.hot = null;
        self.mouse = rl.getMousePosition();
        self.mouse_down = rl.isMouseButtonDown(rl.MouseButton.left);
        self.mouse_pressed = rl.isMouseButtonPressed(rl.MouseButton.left);
        self.mouse_released = rl.isMouseButtonReleased(rl.MouseButton.left);
        self.wheel = rl.getMouseWheelMove();
    }

    pub fn hit(self: *Ui, id: WidgetId, r: rl.Rectangle) bool {
        if (rl.checkCollisionPointRec(self.mouse, r)) {
            self.hot = id;
            return true;
        }
        return false;
    }
};
