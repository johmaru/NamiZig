const std = @import("std");
const builtin = @import("builtin");
const setting = @import("setting.zig");
const c = @cImport({
    @cInclude("webview_wrapper_c.h");
});

const S_OK: c.HRESULT = 0;

var g_webview_environment: ?*anyopaque = null;
var g_webview_controller: ?*anyopaque = null;
var g_settings: *setting.WindowSettings = undefined;

pub fn init(settings: *setting.WindowSettings) !void {
    const os_tag = builtin.os.tag;

    switch (os_tag) {
        .windows => {
            g_settings = settings;
            try win32_init(settings);
        },
        .linux => {
            return error.WIP;
        },
        else => {
            return error.UnsupportedOS;
        }
    }
}

const win32 = @import("win32");
fn win32_init(settings: *setting.WindowSettings) !void {

    const WNDCLASSW = win32.ui.windows_and_messaging.WNDCLASSW;
    const MSG = win32.ui.windows_and_messaging.MSG;

    init_navigate_to = settings.navigatge_to;

    const hInstance = win32.system.library_loader.GetModuleHandleW(null);

    const class_name_utf16_z = try std.unicode.utf8ToUtf16LeAllocZ(std.heap.page_allocator, "NamiZIgWindow");
    defer {
        const slice_u16_to_free = class_name_utf16_z.ptr[0..class_name_utf16_z.len];
        const slice_u8_to_free = std.mem.sliceAsBytes(slice_u16_to_free);
        std.heap.page_allocator.free(slice_u8_to_free);
    }

    if (settings.wnd_class_settings.hCursor == null) {
        const hCursor = win32.ui.windows_and_messaging.LoadCursorW(null, win32.ui.windows_and_messaging.IDC_ARROW);
        if (hCursor == null) {
            return error.CursorLoadFailed;
        }
        settings.wnd_class_settings.hCursor = hCursor;
    }

    var wc = WNDCLASSW{
        .style = settings.wnd_class_settings.wnd_style,
        .lpfnWndProc = windowProc,
        .cbClsExtra = settings.wnd_class_settings.cbClsExtra,
        .cbWndExtra = settings.wnd_class_settings.cbWndExtra,
        .hInstance = hInstance,
        .hIcon = if (settings.wnd_class_settings.hIcon) |icon| icon else null,
        .hCursor = settings.wnd_class_settings.hCursor.?,
        .hbrBackground = @ptrFromInt(6),
        .lpszMenuName = null,
        .lpszClassName = class_name_utf16_z.ptr,
    };

    if (win32.ui.windows_and_messaging.RegisterClassW(&wc) == 0) {
        return error.WindowRegistrationFailed;
    }

    var window_style: win32.ui.windows_and_messaging.WINDOW_STYLE = undefined;
    var x: i32 = undefined;
    var y: i32 = undefined;
    var width: i32 = undefined;
    var height: i32 = undefined;

    if (settings.fullscreen) {
        window_style = win32.ui.windows_and_messaging.WS_POPUP;
        x = 0;
        y = 0;
        width = win32.ui.windows_and_messaging.GetSystemMetrics(win32.ui.windows_and_messaging.SM_CXSCREEN);
        height = win32.ui.windows_and_messaging.GetSystemMetrics(win32.ui.windows_and_messaging.SM_CYSCREEN);
    } else {
        window_style = settings.window_style;
        x = win32.ui.windows_and_messaging.CW_USEDEFAULT;
        y = win32.ui.windows_and_messaging.CW_USEDEFAULT;
        width = @intCast(settings.width);
        height = @intCast(settings.height);
    }


    const window_title = try std.unicode.utf8ToUtf16LeAllocZ(std.heap.page_allocator, settings.title);
    defer {
        const slice_u16_to_free = window_title.ptr[0..window_title.len];
        const slice_u8_to_free = std.mem.sliceAsBytes(slice_u16_to_free);
        std.heap.page_allocator.free(slice_u8_to_free);
    }

    const hwnd = win32.ui.windows_and_messaging.CreateWindowExW(
        win32.ui.windows_and_messaging.WS_EX_APPWINDOW,
        class_name_utf16_z.ptr,
       window_title.ptr,
        window_style,
        x,
        y,
        width,
        height,
        if (settings.create_window_settings.hWndParent) |parent| parent else null,
        settings.create_window_settings.hMenu,
        hInstance,
        null,
    );

    if (hwnd == null) {
        return error.WindowCreationFailed;
    }

    if (settings.fullscreen) {
        _ = win32.ui.windows_and_messaging.SetWindowPos(
            hwnd,
            win32.ui.windows_and_messaging.HWND_TOPMOST,
            0,0,0,0,
            win32.ui.windows_and_messaging.SET_WINDOW_POS_FLAGS{.NOMOVE = 1, .NOSIZE = 1}
        );
    }

    _ = win32.ui.windows_and_messaging.ShowWindow(hwnd, win32.ui.windows_and_messaging.SW_SHOW);
    //_ = win32.graphics.gdi.UpdateWindow(hwnd);

    var msg: MSG = undefined;
    while (win32.ui.windows_and_messaging.GetMessageW(&msg, null, 0, 0) != 0) {
        _ = win32.ui.windows_and_messaging.TranslateMessage(&msg);
        _ = win32.ui.windows_and_messaging.DispatchMessageW(&msg);
    }
}

const CREATE_WEBVIEW_MSG: u32 = win32.ui.windows_and_messaging.WM_APP + 1;
var init_navigate_to: ?[:0]const u8 = null;

fn windowProc(hwnd: win32.foundation.HWND, msg: u32, wParam: win32.foundation.WPARAM, lParam: win32.foundation.LPARAM) callconv(std.os.windows.WINAPI) win32.foundation.LRESULT {
    switch (msg) {
        win32.ui.windows_and_messaging.WM_SIZE => {
            if (g_webview_controller) |controller| {
                var client_rect: win32.foundation.RECT = undefined;
                _ = win32.ui.windows_and_messaging.GetClientRect(hwnd, &client_rect);

                const c_rect = c.RECT{
                    .left = client_rect.left,
                    .top = client_rect.top,
                    .right = client_rect.right,
                    .bottom = client_rect.bottom,
                };
                c.resize_webview(controller, c_rect);
            }
            return 0;
        },
        win32.ui.windows_and_messaging.WM_CREATE => {
            
            _ = win32.ui.windows_and_messaging.PostMessageW(hwnd, CREATE_WEBVIEW_MSG, 0, 0);
            return 0;
        },
        CREATE_WEBVIEW_MSG => {
            if (g_webview_environment == null) {
                var hr = c.create_webview_environment(&g_webview_environment);
                if (hr != S_OK) {
                    std.debug.print("WM_CREATE: create_webview_environment failed. HRESULT: 0x{X:0>8}\n", .{hr});
                    return -1;
                }

            if (g_webview_controller == null) {
                const c_hwnd: c.HWND = @ptrFromInt(@intFromPtr(hwnd));
                hr = c.create_webview_controller(g_webview_environment.?, c_hwnd, &g_webview_controller,g_settings.webview_controller_settings);
                if (hr != S_OK) {
                    std.debug.print("WM_CREATE: create_webview_controller failed. HRESULT: 0x{X:0>8}\n", .{hr});
                    return -1;
                }
                std.debug.print("WebView created successfully in WM_CREATE.\n", .{});

                var client_rect: win32.foundation.RECT = undefined;
                _ = win32.ui.windows_and_messaging.GetClientRect(hwnd, &client_rect);
                const init_rect = c.RECT{
                    .left   = client_rect.left,
                    .top    = client_rect.top,
                    .right  = client_rect.right,
                    .bottom = client_rect.bottom,
                };
                c.resize_webview(g_webview_controller.?, init_rect);

                if (init_navigate_to == null) {
                    std.debug.print("WIP Feature", .{});
                    return -1;
                }
                
                hr = c.navigate_webview(g_webview_controller.?, init_navigate_to.?.ptr);
                if (hr != S_OK) {
                    std.debug.print("Failed to navigate in WM_CREATE. HRESULT: 0x{X:0>8}\n", .{hr});
                }
            }
        }
            return 0;
        },

        win32.ui.windows_and_messaging.WM_DESTROY => {
            if (g_webview_controller != null and g_webview_environment != null) {
                c.cleanup_webview(g_webview_controller.?, g_webview_environment.?);
                g_webview_controller = null;
                g_webview_environment = null;
            }
            win32.ui.windows_and_messaging.PostQuitMessage(0);
            return 0;
        },
        else => {
            return win32.ui.windows_and_messaging.DefWindowProcW(hwnd, msg, wParam, lParam);
        }
    }
}

