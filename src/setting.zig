const std = @import("std");
const c = @cImport({
    @cInclude("webview_wrapper_c.h");
});
const win32 = @import("win32");
pub const WindowSettings = struct {
    title: []const u8 = "NamiZig Application",
    width: u32 = 800,
    height: u32 = 600,
    resizable: bool = true,
    fullscreen: bool = false,
    start_position: WindowStartPostionSettings = WindowStartPostionSettings{},
    window_style: win32.ui.windows_and_messaging.WINDOW_STYLE = win32.ui.windows_and_messaging.WS_OVERLAPPEDWINDOW,
    wnd_class_settings: WndClassSettings = WndClassSettings{},
    create_window_settings: CreateWindowSettings = CreateWindowSettings{},
};

// Default position is set to CW_USEDEFAULT, which is a special value that tells Windows to choose the default position. 
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