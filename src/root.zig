pub const models = struct {
    pub const AppModel = @import("models/app.zig").AppModel;
    pub const AppMsg = @import("models/app.zig").AppMsg;
};

pub const ui = struct {
    const ui_mod = @import("ui/ui.zig");
    pub const Ui = ui_mod.Ui;
    pub const WidgetId = ui_mod.WidgetId;
    pub const scrollbar = @import("ui/scrollbar.zig");
    pub const listbox = @import("ui/listbox.zig");
    pub const canvas = @import("ui/canvas.zig");
    pub const button = @import("ui/button.zig");
    pub const layout = @import("ui/layout.zig");
    pub const ids = @import("ui/ids.zig");
    pub const modals = struct {
        pub const confirm_switch = @import("ui/modals/confirm_switch.zig");
    };
};
