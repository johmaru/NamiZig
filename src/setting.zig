const std = @import("std");
const c = @cImport({
    @cInclude("webview_wrapper_c.h");
});
const win32 = @import("win32");
const lang = @import("lang.zig");
pub const WindowSettings = struct {
    title: []const u8 = "NamiZig Application",
    width: i32 = 800,
    height: i32 = 600,
    resizable: bool = true,
    fullscreen: bool = false,
    navigatge_to: ?[:0] const u8 = null,
    toolbar: bool = true,
    theme_settings: ThemeSettings = ThemeSettings{},
    language: lang.language_controller.languages = lang.language_controller.languages.en,
    start_position: WindowStartPostionSettings = WindowStartPostionSettings{},
    window_style: win32.ui.windows_and_messaging.WINDOW_STYLE = win32.ui.windows_and_messaging.WS_OVERLAPPEDWINDOW,
    wnd_class_settings: WndClassSettings = WndClassSettings{},
    create_window_settings: CreateWindowSettings = CreateWindowSettings{},
    webview_controller_settings: c.controllerSettings,
};

pub const WindowStartPostionSettings = struct {
    x: i32 = win32.ui.windows_and_messaging.CW_USEDEFAULT,
    y: i32 = win32.ui.windows_and_messaging.CW_USEDEFAULT,
};

pub const WndClassSettings = struct {
    wnd_style: win32.ui.windows_and_messaging.WNDCLASS_STYLES = win32.ui.windows_and_messaging.WNDCLASS_STYLES{},
    cbClsExtra: i32 = 0,
    cbWndExtra: i32 = 0,
    hIcon: ?win32.ui.windows_and_messaging.HICON = null,
    hCursor: ?win32.ui.windows_and_messaging.HCURSOR = null,
};

pub const CreateWindowSettings = struct {
    dwExStyle: win32.ui.windows_and_messaging.WINDOW_EX_STYLE = win32.ui.windows_and_messaging.WS_EX_APPWINDOW,
    hWndParent: ?win32.foundation.HWND  = null,
    hMenu: ?win32.ui.windows_and_messaging.HMENU = null,
};

pub const ThemeSettings = struct {
    accent_color: u32 = 0x00D1B499,
    toolbar_background_color: u32 = 0x00F0F0F0,
    toolbar_text_color: u32 = 0x00000000,
    toolbar_button_color: u32 = 0x00F0F0F0,
    toolbar_button_text_color: u32 = 0x00000000,
    window_background_color: u32 = 0x00FFFFFF,
};

// Function Section

pub fn GetMainScreenCenterPos(x: i32, y: i32) !WindowStartPostionSettings {
    const screen_width = win32.ui.windows_and_messaging.GetSystemMetrics(win32.ui.windows_and_messaging.SM_CXSCREEN);
    const screen_height = win32.ui.windows_and_messaging.GetSystemMetrics(win32.ui.windows_and_messaging.SM_CYSCREEN);

    const window_x = @divTrunc(screen_width - x, 2);
    const window_y = @divTrunc(screen_height - y, 2);

    return WindowStartPostionSettings{
        .x = window_x,
        .y = window_y,
    };
}