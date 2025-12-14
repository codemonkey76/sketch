const std = @import("std");
const arcade = @import("arcade_lib");

pub const PathEditor = struct {
    allocator: std.mem.Allocator,

    current_name: ?[]u8 = null,
    points: std.ArrayList(arcade.Vec2),
    dirty: bool = false,

    pub fn init(allocator: std.mem.Allocator) PathEditor {
        return .{
            .allocator = allocator,
            .points = std.ArrayList(arcade.Vec2).empty,
        };
    }

    pub fn deinit(self: *PathEditor) void {
        if (self.current_name) |n| self.allocator.free(n);
        self.points.deinit(self.allocator);
    }

    pub fn load(self: *PathEditor, name: []const u8, path: arcade.PathDefinition) !void {
        if (self.current_name) |n| self.allocator.free(n);
        self.current_name = try self.allocator.dupe(u8, name);

        self.points.clearRetainingCapacity();
        try self.points.appendSlice(self.allocator, path.control_points);
        self.dirty = false;
    }

    pub fn markDirty(self: *PathEditor) void {
        self.dirty = true;
    }

    pub fn clear(self: *PathEditor) void {
        if (self.current_name) |n| self.allocator.free(n);
        self.current_name = null;
        self.points.clearRetainingCapacity();
        self.dirty = false;
    }

    pub fn definition(self: *PathEditor) arcade.PathDefinition {
        return .{ .control_points = self.points.items };
    }
};
