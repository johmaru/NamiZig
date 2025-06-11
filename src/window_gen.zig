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
var g_hToolbar: ?win32.foundation.HWND = null;
var g_hMenuFile: ?win32.ui.windows_and_messaging.HMENU = null;

const ID_TOOLBAR: u32 = 1001;
const ID_FILE_BUTTON: u32 = 1002;
const ID_FILE_EXIT: u32 = 1003;

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
    const INITCOMMONCONTROLSEX = win32.ui.controls.INITCOMMONCONTROLSEX;
    const INITCOMMONCONTROLSEX_ICC = win32.ui.controls.INITCOMMONCONTROLSEX_ICC;

    if (settings.toolbar) {
        const icc_flags = INITCOMMONCONTROLSEX_ICC {
            .BAR_CLASSES = 1,
            .COOL_CLASSES = 1,
        };

        var icex = INITCOMMONCONTROLSEX{
        .dwSize = @sizeOf(INITCOMMONCONTROLSEX),
        .dwICC = @bitCast(icc_flags),
        };
        if (win32.ui.controls.InitCommonControlsEx(&icex) == 0) {
            return error.CommonControlsInitFailed;   
        }
    }

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

                var toolbar_height: i32 = 0;
                if (g_hToolbar) |hToobar| {
                    if (win32.ui.windows_and_messaging.IsWindowVisible(hToobar) != 0) {
                        var toolbar_rect: win32.foundation.RECT = undefined;
                        if (win32.ui.windows_and_messaging.GetWindowRect(hToobar, &toolbar_rect) != 0) {
                            toolbar_height = toolbar_rect.bottom - toolbar_rect.top;
                        }
                    }
                }

                const c_rect = c.RECT{
                    .left = client_rect.left,
                    .top = client_rect.top + toolbar_height,
                    .right = client_rect.right,
                    .bottom = client_rect.bottom,
                };
                if (c_rect.bottom > c_rect.top and c_rect.right > c_rect.left) {
                    c.resize_webview(controller, c_rect);
                }
            }

            if (g_hToolbar) |hToolbar| {
                _ = win32.ui.windows_and_messaging.SendMessageW(
                    hToolbar,
                    win32.ui.controls.TB_AUTOSIZE,
                    0,
                    0,
                );
            }

            return 0;
        },
        win32.ui.windows_and_messaging.WM_CREATE => {

            // Create a toolbar if it doesn't exist
            const hInstance = win32.system.library_loader.GetModuleHandleW(null);
            if (hInstance == null) {
                std.debug.print("WM_CREATE: GetModuleHandleW failed.\n", .{});
                return -1;
            }

            if (g_settings.toolbar) {
                const toolbar_class_name_u8_fixed_array_ptr: *const [15:0]u8 = win32.ui.controls.TOOLBARCLASSNAMEW;

                const toolbar_class_name_u8_c_ptr: [*c]const u8 = @ptrCast(toolbar_class_name_u8_fixed_array_ptr);

                const toolbar_class_name_u8_slice: [:0]const u8 = std.mem.sliceTo(toolbar_class_name_u8_c_ptr, 0);

                const toolbar_class_name_utf16_z = std.unicode.utf8ToUtf16LeAllocZ(
                    std.heap.page_allocator,
                    toolbar_class_name_u8_slice,
                    ) catch |err| {
                        std.debug.print("WM_CREATE: utf8ToUtf16LeAllocZ for toolbar class name failed: {any}\n", .{err});
                        return -1;
                    };

                defer std.heap.page_allocator.free(std.mem.sliceAsBytes(toolbar_class_name_utf16_z.ptr[0..toolbar_class_name_utf16_z.len]));

                g_hToolbar = win32.ui.windows_and_messaging.CreateWindowExW(
                win32.ui.windows_and_messaging.WINDOW_EX_STYLE{},
                    toolbar_class_name_utf16_z.ptr,
                    null,
                    @bitCast(
                        @as(u32, @bitCast(win32.ui.windows_and_messaging.WINDOW_STYLE{
                            .CHILD = 1,
                            .VISIBLE = 1,
                        })) | win32.ui.controls.TBSTYLE_FLAT | win32.ui.controls.TBSTYLE_TOOLTIPS
                    ),
                    0, 0, 0, 0,
                    hwnd,
                    @ptrFromInt(ID_TOOLBAR),
                    hInstance,
                    null,
                );

                if (g_hToolbar == null) {
                    std.debug.print("WM_CREATE: CreateWindowExW for toolbar failed.\n", .{});
                    return -1;
                }

                _ =win32.ui.windows_and_messaging.SendMessageW(g_hToolbar.?, win32.ui.controls.TB_BUTTONSTRUCTSIZE, @sizeOf(win32.ui.controls.TBBUTTON), 0);

                const file_button_text_utf16 = std.unicode.utf8ToUtf16LeAllocZ(std.heap.page_allocator, "File") catch |err| {
                    std.debug.print("WM_CREATE: utf8ToUtf16LeAllocZ for file_button_text_utf16 failed: {any}\n", .{err});
                    return -1;
                };
                defer std.heap.page_allocator.free(std.mem.sliceAsBytes(file_button_text_utf16.ptr[0..file_button_text_utf16.len]));

                var tbButtonFile = win32.ui.controls.TBBUTTON{
                    .iBitmap = win32.ui.controls.I_IMAGENONE,
                    .idCommand = ID_FILE_BUTTON,
                    .fsState = win32.ui.controls.TBSTATE_ENABLED,
                    .fsStyle = win32.ui.controls.BTNS_DROPDOWN | win32.ui.controls.BTNS_AUTOSIZE | win32.ui.controls.BTNS_WHOLEDROPDOWN,
                    .bReserved = [_]u8{0} ** 6,
                    .dwData = 0,
                    .iString = @intCast(@intFromPtr(file_button_text_utf16.ptr)),
                };

                _ = win32.ui.windows_and_messaging.SendMessageW(
                    g_hToolbar.?,
                    win32.ui.controls.TB_ADDBUTTONS,
                    1,
                    @intCast(@intFromPtr(&tbButtonFile)),
                );

                g_hMenuFile = win32.ui.windows_and_messaging.CreatePopupMenu();
                if (g_hMenuFile == null) {
                    std.debug.print("WM_CREATE: CreatePopupMenu for file menu failed.\n", .{});
                    return -1;
                }

                const exit_menu_text_utf16 = std.unicode.utf8ToUtf16LeAllocZ(std.heap.page_allocator, "Exit") catch |err| {
                    std.debug.print("WM_CREATE: utf8ToUtf16LeAllocZ for exit_menu_text_utf16 failed: {any}\n", .{err});
                    _ = win32.ui.windows_and_messaging.DestroyMenu(g_hMenuFile.?);
                    g_hMenuFile = null;
                    return -1;
                };  
                defer std.heap.page_allocator.free(std.mem.sliceAsBytes(exit_menu_text_utf16.ptr[0..exit_menu_text_utf16.len]));

                if (win32.ui.windows_and_messaging.AppendMenuW(
                    g_hMenuFile.?,
                    win32.ui.windows_and_messaging.MF_STRING,
                    ID_FILE_EXIT,
                    exit_menu_text_utf16.ptr,
                ) == 0) {
                    std.debug.print("WM_CREATE: AppendMenuW for exit menu item failed.\n", .{});
                    _ = win32.ui.windows_and_messaging.DestroyMenu(g_hMenuFile.?);
                    g_hMenuFile = null;
                    return -1;

                }
            }
                
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
                hr = c.create_webview_controller(
          g_webview_environment.?,
            c_hwnd,
    &g_webview_controller,
       g_settings.webview_controller_settings,
             );
                if (hr != S_OK) {
                    std.debug.print("WM_CREATE: create_webview_controller failed. HRESULT: 0x{X:0>8}\n", .{hr});
                    return -1;
                }
                std.debug.print("WebView created successfully in WM_CREATE.\n", .{});

                var client_rect: win32.foundation.RECT = undefined;
                _ = win32.ui.windows_and_messaging.GetClientRect(hwnd, &client_rect);

                var toolbar_height: i32 = 0;
                if (g_hToolbar) |hToolbar| {
                   var toolbar_rect: win32.foundation.RECT = undefined;
                    if (win32.ui.windows_and_messaging.GetWindowRect(hToolbar, &toolbar_rect) != 0) {
                        toolbar_height = toolbar_rect.bottom - toolbar_rect.top;
                    }
                }

                const init_rect = c.RECT{
                    .left   = client_rect.left,
                    .top    = client_rect.top + toolbar_height,
                    .right  = client_rect.right,
                    .bottom = client_rect.bottom,
                };
                if (init_rect.bottom > init_rect.top and init_rect.right > init_rect.left) {
                   c.resize_webview(g_webview_controller.?, init_rect);
                }

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
            std.debug.print("WM_DESTROY entered. g_webview_controller: {?}, g_webview_environment: {?}\n", .{ g_webview_controller, g_webview_environment });
            if (g_webview_controller != null and g_webview_environment != null) {
                std.debug.print("WM_DESTROY: Condition met. Calling cleanup_webview with controller: {?} and environment: {?}\n", .{g_webview_controller.?, g_webview_environment.?});
                c.cleanup_webview(g_webview_controller.?, g_webview_environment.?);
                g_webview_controller = null;
                g_webview_environment = null;
            } else {
                std.debug.print("WM_DESTROY: Condition NOT met. Skipping cleanup_webview. Controller was: {?}, Environment was: {?}\n", .{g_webview_controller, g_webview_environment});
            }
            if (g_hMenuFile) |hMenu| {
                _ = win32.ui.windows_and_messaging.DestroyMenu(hMenu);
                g_hMenuFile = null;
            }
            win32.ui.windows_and_messaging.PostQuitMessage(0);
            return 0;
        },
        win32.ui.windows_and_messaging.WM_NOTIFY => {
            const pnmh: *win32.ui.controls.NMHDR = @ptrFromInt(@as(usize, @bitCast(lParam)));
            if (pnmh.hwndFrom == g_hToolbar.?) {
                if (pnmh.code == c.WRAPPER_TBN_DROPDOWN) {
                    const pnmtb: *win32.ui.controls.NMTOOLBARW = @ptrCast(@alignCast(pnmh));
                    if (pnmtb.iItem == ID_FILE_BUTTON) {
                        if (g_hMenuFile) |hMenuFile| {
                            var rc: win32.foundation.RECT = undefined;
                            _ = win32.ui.windows_and_messaging.SendMessageW(g_hToolbar.?, win32.ui.controls.TB_GETRECT, ID_FILE_BUTTON, @intCast(@intFromPtr(&rc)));

                            var pt: win32.foundation.POINT = undefined;
                            pt.x = rc.left;
                            pt.y = rc.bottom;
                            _ = win32.graphics.gdi.ClientToScreen(g_hToolbar.?, &pt);

                            _ = win32.ui.windows_and_messaging.TrackPopupMenu(
                                hMenuFile,
                                win32.ui.windows_and_messaging.TRACK_POPUP_MENU_FLAGS{
                                    .RIGHTALIGN = 0,
                                    .BOTTOMALIGN = 0,
                                },
                                pt.x,
                                pt.y,
                                0,
                                hwnd,
                                null,
                            );
                            return 0;
                        }
                    }
        } else {
            std.debug.print("WM_NOTIFY: Unhandled notification code: {}\n", .{pnmh.code});
        }
            }
            return win32.ui.windows_and_messaging.DefWindowProcW(hwnd, msg, wParam, lParam);
        },
        win32.ui.windows_and_messaging.WM_COMMAND => {
            const wmId = win32.zig.loword(wParam);
            switch (wmId) {
                ID_FILE_EXIT => {
                    _ = win32.ui.windows_and_messaging.DestroyWindow(hwnd);
                    return 0;
                },
                else => {
                    return win32.ui.windows_and_messaging.DefWindowProcW(hwnd, msg, wParam, lParam);
                },
            }
        },
        else => {
            return win32.ui.windows_and_messaging.DefWindowProcW(hwnd, msg, wParam, lParam);
        }
    }
}

