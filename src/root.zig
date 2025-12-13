pub const models = struct {
    pub const AppModel = @import("models/app.zig").AppModel;
    pub const AppMsg = @import("models/app.zig").AppMsg;
};

pub const ui = struct {
    const ui_mod = @import("ui/ui.zig");
    pub const Ui = ui_mod.Ui;
    pub const WidgetId = ui_mod.WidgetId;
    pub const scrollbar = @import("ui/scrollbar.zig");
};
