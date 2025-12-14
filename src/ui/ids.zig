pub const Id = struct {
    // Toolbar
    pub const toolbar_reload_btn: u32 = 10;
    pub const toolbar_save_btn: u32 = 11;
    pub const toolbar_new_btn: u32 = 12;
    pub const toolbar_rename_btn: u32 = 13;
    pub const toolbar_duplicate_btn: u32 = 14;
    pub const toolbar_delete_btn: u32 = 15;
    pub const toolbar_flip_v_btn: u32 = 16;
    pub const toolbar_flip_h_btn: u32 = 17;

    // Main widgets
    pub const listbox_paths: u32 = 2000;
    pub const canvas_editor: u32 = 3000;

    // Modal: confirm switch
    pub const modal_yes: u32 = 90_000;
    pub const modal_no: u32 = 90_001;
    pub const modal_cancel: u32 = 90_002;

    pub const modal_create: u32 = 91_000;
    pub const modal_create_ok: u32 = 91_001;
    pub const modal_create_cancel: u32 = 91_002;

    pub const modal_delete_yes: u32 = 92_001;
    pub const modal_delete_no: u32 = 92_002;
};
