// Now this an fuction exist as a TestRunner(So bad structure btw).
pub fn main() !void {
    if (builtin.os.tag == .windows) {
        
        // Absolutelly require COM Initialize
        const hr = win32.system.com.CoInitializeEx(null, window_gen.COINIT);
        if (hr != win32.foundation.S_OK and hr != win32.foundation.S_FALSE) {
            std.debug.print("CoInitializeEx failed. HRESULT: 0x{X:0>8}\n", .{hr});
            return error.CoInitializeFailed;
        }

        // Absolutelly require COM Uninitialize exit a main function
        defer win32.system.com.CoUninitialize();

        const allocator = std.heap.page_allocator;

        var window_manager  = try window_gen.WindowGen.WindowManager.init(allocator);
        defer window_manager.deinit();

        // Can use some word
        const virtualHostName= "testvirtualhost";

        const webViewConttollerSettings = window_gen.c_Controller_settings{
            .contextMenu = false,
            .isVirtualHost = true,
            .virtualHostName = virtualHostName,
            .htmlContent = null
        };

        // if you need change settings, Can do
        var win_settings = nami_settings.WindowSettings{
            .webview_controller_settings = webViewConttollerSettings,
            .theme_settings = nami_settings.ThemeSettings{
                .toolbar_background_color = try window_gen.RGB(0, 0, 0),
                .toolbar_button_color = try window_gen.RGB(128, 128, 128),
                .toolbar_button_text_color = try window_gen.RGB(255, 255, 255),
            },
            .language = nami_lang.language_controller.languages.ja,
            .toolbar = true,
        };

        const window = try window_manager.createWindow(&win_settings);

        try window.registerWebMessageHandler("exitAPP", handleAppExit);
        try window.registerWebMessageHandler("showName", callName);
        try window.registerWebMessageHandler("nav_google", navGoogle);

        try window.show();

        // To the child window will start new window.
        var child_settings = win_settings;

        // Navigates to main.html if isVirtualHost is not null.
        child_settings.webview_controller_settings.isVirtualHost = false;
        child_settings.webview_controller_settings.virtualHostName = null;

        // To create a popup window, set window_style.POPUP to 1.
        child_settings.window_style.POPUP = 1;

        // Examlple,child go to google.com.
        child_settings.navigatge_to = "https://www.google.com";


       const child = try  window_manager.createChildWindow(window.hwnd.?, &child_settings);

       try child.show();

       try window.messageLoop();
        
    }
}

// Custom EventHandler
fn handleAppExit(hwnd: window_gen.HWND, message: std.json.Value) !void {
    _ = message;

    _ = win32.ui.windows_and_messaging.DestroyWindow(hwnd);
}

const name = "Johmaru";
fn callName(hwnd: window_gen.HWND, message: std.json.Value) !void {
    _ = message;

    const allocator = std.heap.page_allocator;

    const text = std.fmt.allocPrint(allocator, "You Are {s}", .{name}) catch return;
    defer allocator.free(text);

    var message_box_settings = nami_control.Control.Message_box_struct{
        .lpText = text,
        .lpCaption = "Test",
        .uType = nami_control.Control.WINDOWS_MESSAGING.MB_OK,
    };

    try nami_control.Control.message_box(allocator, &message_box_settings,hwnd);
    
}

fn navGoogle(hwnd: window_gen.HWND, message: std.json.Value) !void {

    _ = message;


    const window = try window_gen.WindowGen.g_window_manager.?.get(hwnd);

    try window.navigate("https://www.google.com");

}

const std = @import("std");
const window_gen = @import("window_gen.zig");
const win32 = @import("win32");
const builtin = @import("builtin");
const nami_settings = @import("setting.zig");
const nami_lang = @import("lang.zig");
const nami_control = @import("control.zig");