const std = @import("std");


pub const WindowSettings = struct {
    title: []const u8 = "NamiZig Application",
    width: u32 = 800,
    height: u32 = 600,
    resizable: bool = true,
    fullscreen: bool = false,
};