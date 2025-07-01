
pub fn main() !void {
    if (builtin.os.tag == .windows) {
        
        // Absolutelly require COM Initialize
        const hr = win32.system.com.CoInitializeEx(null, COINIT);
        if (hr != win32.foundation.S_OK and hr != win32.foundation.S_FALSE) {
            std.debug.print("CoInitializeEx failed. HRESULT: 0x{X:0>8}\n", .{hr});
            return error.CoInitializeFailed;
        }

        // Absolutelly require COM Uninitialize exit a main function
        defer win32.system.com.CoUninitialize();

        // Can use some word
        const virtualHostName= "testvirtualhost";

        const webViewConttollerSettings = c.controllerSettings{
            .contextMenu = false,
            .isVirtualHost = true,
            .virtualHostName = virtualHostName,
        };

        // if you need change settings, Can
        var win_settings = settings.WindowSettings{
            .webview_controller_settings = webViewConttollerSettings,
            .theme_settings = settings.ThemeSettings{
                .toolbar_background_color = 0x00222222,
                .toolbar_button_color = 0x00555555,
                .toolbar_button_text_color = 0x00FFFFFF,
            },
            .language = lang.language_controller.languages.ja,
            .toolbar = true,
        };

        // First,Require initialize the window
        try window_gen.init(&win_settings);

        // After initialized the window,Can register event handler
        try window_gen.registerWebMessageHandler("exitAPP", handleAppExit);

        // Run the window(Once window_gen.run() is called, you can no longer register event handlers)
        try window_gen.run();
    }
}

fn toWideString(allocator: std.mem.Allocator, str: []const u8) ![:0]u16 {
    return try std.unicode.utf8ToUtf16LeAllocZ(allocator, str);
}

// Custom EventHandler
fn handleAppExit(hwnd: window_gen.HWND, message: std.json.Value) void {
    _ = message;

    _ = win32.ui.windows_and_messaging.DestroyWindow(hwnd);
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
const lang = @import("lang.zig");