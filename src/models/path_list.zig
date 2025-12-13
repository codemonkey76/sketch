const std = @import("std");
const arcade = @import("arcade_lib");
const sketch = @import("../root.zig");
const listbox = sketch.ui.listbox;

pub const PathList = struct {
    allocator: std.mem.Allocator,
    names: [][]const u8 = &.{},
    items: []listbox.Item = &.{},

    pub fn init(allocator: std.mem.Allocator) PathList {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *PathList) void {
        if (self.items.len != 0) self.allocator.free(self.items);
        if (self.names.len != 0) self.allocator.free(self.names);
        self.* = .{ .allocator = self.allocator };
    }

    /// Rebuild `names` + `items` from the registry.
    pub fn rebuild(self: *PathList, paths: *arcade.PathRegistry) !void {
        if (self.names.len != 0) self.allocator.free(self.names);
        if (self.items.len != 0) self.allocator.free(self.items);

        self.names = try paths.listPaths(self.allocator);

        self.items = try self.allocator.alloc(listbox.Item, self.names.len);
        for (self.names, 0..) |name, i| {
            self.items[i] = .{
                .id = @intCast(i),
                .label = name,
            };
        }
    }
};
