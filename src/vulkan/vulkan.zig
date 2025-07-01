const std = @import("std");
const bk = @import("backend.zig");
usingnamespace bk;
pub const c = @cImport({
    @cInclude("vulkan/vulkan.h");
});

pub const Context = struct {
    const Self = @This();

    var instance: c.VkInstance = undefined;

    pub fn init() !Self {}

    pub fn deinit(self: Self) void {}
};
