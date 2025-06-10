
pub fn main() !void {
    if (builtin.os.tag == .windows) {
        const hr = win32.system.com.CoInitializeEx(null, COINIT);
        if (hr != win32.foundation.S_OK and hr != win32.foundation.S_FALSE) {
            std.debug.print("CoInitializeEx failed. HRESULT: 0x{X:0>8}\n", .{hr});
            return error.CoInitializeFailed;
        }

        defer win32.system.com.CoUninitialize();

        const virtualHostName= "testvirtualhost";

        const webViewConttollerSettings = c.controllerSettings{
            .contextMenu = false,
            .isVirtualHost = true,
            .virtualHostName = virtualHostName,
        };

        var win_settings = settings.WindowSettings{
            .navigatge_to = "https://www.google.com",
            .webview_controller_settings = webViewConttollerSettings,
            .toolbar = false,
        };

        try window_gen.init(&win_settings);
    }
}

fn toWideString(allocator: std.mem.Allocator, str: []const u8) ![:0]u16 {
    return try std.unicode.utf8ToUtf16LeAllocZ(allocator, str);
}

const std = @import("std");
const window_gen = @import("window_gen.zig");
const win32 = @import("win32");
const COINIT = win32.system.com.COINIT_APARTMENTTHREADED;
const builtin = @import("builtin");
const settings = @import("setting.zig");
const c = @cImport({
    @cInclude("webview_wrapper_c.h");
});