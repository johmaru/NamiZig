const std = @import("std");
const builtin = @import("builtin");
const setting = @import("setting.zig");
const c = @cImport({
    @cInclude("webview_wrapper_c.h");
});
const lang = @import("lang.zig");

const MEASUREITEMSSTRUCT = extern struct {
    CtlType: u32,
    CtlID: u32,
    itemID: u32,
    itemWidth: i32,
    itemHeight: i32,
    itemData: usize,
};

const DRAWITEMSTRUCT = extern struct {
    CtlType: u32,
    CtlID: u32,
    itemID: u32,
    itemAction: u32,
    itemState: u32,
    hwndItem: ?win32.foundation.HWND,
    hDC: ?win32.graphics.gdi.HDC,
    rcItem: win32.foundation.RECT,
    itemData: usize,
};

pub const HWND = win32.foundation.HWND;
const S_OK: c.HRESULT = 0;
const ODT_MENU: u32 = 1;
const WM_WEB_MESSAGE = win32.ui.windows_and_messaging.WM_APP + 2;

var g_hwnd: ?win32.foundation.HWND = null;
var g_webview_environment: ?*anyopaque = null;
var g_webview_controller: ?*anyopaque = null;
var g_settings: *setting.WindowSettings = undefined;
var g_hToolbar: ?win32.foundation.HWND = null;
var g_hMenuFile: ?win32.ui.windows_and_messaging.HMENU = null;
var g_language_strings: lang.language_controller = undefined;
var g_html_content_buffer_for_virtual_host: ?[]u8 = null;

pub const WebMessageHandler = *const fn (hwnd: win32.foundation.HWND, message: std.json.Value) void;

var g_web_message_handlers: std.StringHashMap(WebMessageHandler) = undefined;
var g_web_message_handler_allocator: std.mem.Allocator = undefined;

// global text definitions
var g_text_file_button: [:0]const u16 = undefined;

const ID_TOOLBAR: u32 = 1001;
const ID_FILE_BUTTON: u32 = 1002;
const ID_FILE_EXIT: u32 = 1003;

fn webMessageReceived(message_json: [*c]const u8) callconv(.C) void {
    const message_slice = std.mem.sliceTo(message_json, 0);
    const allocator = std.heap.page_allocator;

    const messasge_copy = allocator.dupe(u8, message_slice) catch |err| {
        std.debug.print("webMessageReceived: Failed to copy message: {any}\n", .{err});
        return;
    };

    if (g_hwnd) |hwnd| {
        _ = win32.ui.windows_and_messaging.PostMessageW(
            hwnd,
            WM_WEB_MESSAGE,
            messasge_copy.len,
            @intCast(@intFromPtr(messasge_copy.ptr)),
        );
    } else {
        std.debug.print("g_hwnd is null, cannot post message.\n", .{});
        allocator.free(messasge_copy);
    }

}

/// Initializes the window generation library with the given settings.
///
/// # Important
/// On Windows, the caller is responsible for initializing COM (e.g., by calling `CoInitializeEx`)
/// on the thread that will call `run()` before calling this function.
pub fn init(settings: *setting.WindowSettings) !void {
    const os_tag = builtin.os.tag;

    g_web_message_handler_allocator = std.heap.page_allocator;
    g_web_message_handlers = std.StringHashMap(WebMessageHandler).init(g_web_message_handler_allocator);

    switch (os_tag) {
        .windows => {
            g_settings = settings;
            g_language_strings = try lang.language_controller.init(
                std.heap.page_allocator,
                settings.language,
            );
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
fn runWin32(settings: *setting.WindowSettings) !void {

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
    g_hwnd = hwnd;

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

pub fn run() !void {
    const os_tag = builtin.os.tag;
    switch (os_tag) {
        .windows => {
           try runWin32(g_settings);
        },
        .linux => return error.WIP,
        else => {
            return error.UnsupportedOS;
            }
        }

}

pub fn registerWebMessageHandler(event_key: []const u8, handler: WebMessageHandler) !void {
    try g_web_message_handlers.put(event_key, handler);
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
                
                const style_bits: u32 =
                    win32.ui.controls.TBSTYLE_FLAT |
                    win32.ui.controls.TBSTYLE_TOOLTIPS |
                    @as(u32, @bitCast(win32.ui.windows_and_messaging.WS_CHILD)) |
                    @as(u32, @bitCast(win32.ui.windows_and_messaging.WS_VISIBLE));
                
               

                g_hToolbar = win32.ui.controls.CreateToolbarEx(
                    hwnd,
                    style_bits,
                    ID_TOOLBAR,
                    0,
                    null,0,
                    null,0,
                    16,16,16,16,
                    @sizeOf(win32.ui.controls.TBBUTTON)
                );

                const empty_theme: [:0]const u16 = &[_:0]u16{0};
                _ = c.wrapper_SetWindowTheme(g_hToolbar.?, empty_theme.ptr, empty_theme.ptr);

                if (g_hToolbar == null) {
                    std.debug.print("WM_CREATE: CreateWindowExW for toolbar failed.\n", .{});
                    return -1;
                }

                _ =win32.ui.windows_and_messaging.SendMessageW(g_hToolbar.?, win32.ui.controls.TB_BUTTONSTRUCTSIZE, @sizeOf(win32.ui.controls.TBBUTTON), 0);

                const file_button_text_utf16 = std.unicode.utf8ToUtf16LeAllocZ(std.heap.page_allocator, g_language_strings.getLanguageString(.file)) catch |err| {
                    std.debug.print("WM_CREATE: utf8ToUtf16LeAllocZ for file_button_text_utf16 failed: {any}\n", .{err});
                    return -1;
                };

                g_text_file_button = file_button_text_utf16;

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

                const exit_menu_text_utf16 = std.unicode.utf8ToUtf16LeAllocZ(std.heap.page_allocator, g_language_strings.getLanguageString(.exit)) catch |err| {
                    std.debug.print("WM_CREATE: utf8ToUtf16LeAllocZ for exit_menu_text_utf16 failed: {any}\n", .{err});
                    _ = win32.ui.windows_and_messaging.DestroyMenu(g_hMenuFile.?);
                    g_hMenuFile = null;
                    return -1;
                };  
                defer std.heap.page_allocator.free(std.mem.sliceAsBytes(@as([]const u16, exit_menu_text_utf16)));

                if (win32.ui.windows_and_messaging.AppendMenuW(
                    g_hMenuFile.?,
                    win32.ui.windows_and_messaging.MF_OWNERDRAW,
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
        win32.ui.windows_and_messaging.WM_MEASUREITEM => {
            const pMesureItem: *MEASUREITEMSSTRUCT = @ptrFromInt(@as(usize, @bitCast(lParam)));
            if (pMesureItem.CtlType == ODT_MENU) {
                pMesureItem.itemWidth = 120;
                pMesureItem.itemHeight = 24;
                return 1;
            }
            return win32.ui.windows_and_messaging.DefWindowProcW(hwnd, msg, wParam, lParam);
        },
        win32.ui.windows_and_messaging.WM_DRAWITEM => {
            const pDrawItem: *DRAWITEMSTRUCT = @ptrFromInt(@as(usize, @bitCast(lParam)));

            if ( pDrawItem.CtlType == ODT_MENU) {
                const bgColor = if((pDrawItem.itemState & win32.ui.windows_and_messaging.ODS_SELECTED) != 0)
                    g_settings.theme_settings.toolbar_button_color
                else
                    g_settings.theme_settings.toolbar_background_color;

                const hBrush = win32.graphics.gdi.CreateSolidBrush(bgColor);
                if (hBrush != null) {
                    _ = win32.graphics.gdi.FillRect(pDrawItem.hDC, &pDrawItem.rcItem, hBrush);
                    _ = win32.graphics.gdi.DeleteObject(hBrush);
                }

                _ = win32.graphics.gdi.SetTextColor(pDrawItem.hDC, g_settings.theme_settings.toolbar_button_text_color);
                _ = win32.graphics.gdi.SetBkMode(pDrawItem.hDC, win32.graphics.gdi.TRANSPARENT);

                const text_u8 = switch (pDrawItem.itemID) {
                    ID_FILE_EXIT => g_language_strings.getLanguageString(.exit),
                    else => return win32.ui.windows_and_messaging.DefWindowProcW(hwnd, msg, wParam, lParam),
                };
                
                const text_alloc = std.heap.page_allocator;
                const text_utf16_z = std.unicode.utf8ToUtf16LeAllocZ(text_alloc, text_u8) catch |err| {
                    std.debug.print("WM_DRAWITEM: utf8ToUtf16LeAllocZ failed: {any}\n", .{err});
                    return win32.ui.windows_and_messaging.DefWindowProcW(hwnd, msg, wParam, lParam);
                };

                defer text_alloc.free(std.mem.sliceAsBytes(@as([]const u16, text_utf16_z)));

                var text_rect = pDrawItem.rcItem;
                _ = win32.graphics.gdi.DrawTextW(
                    pDrawItem.hDC, 
                    text_utf16_z.ptr, 
                    -1, 
                    &text_rect, 
                    win32.graphics.gdi.DRAW_TEXT_FORMAT{.CENTER = 1, .VCENTER = 1, .SINGLELINE = 1},);
                return 1;
            } else {
                std.debug.print("WM_DRAWITEM: Unhandled CtlType: {}\n", .{pDrawItem.CtlType});
                return win32.ui.windows_and_messaging.DefWindowProcW(hwnd, msg, wParam, lParam);
            }
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
                const allocator = std.heap.page_allocator;

                if (g_settings.webview_controller_settings.isVirtualHost) {

                    const exe_path = std.fs.selfExePathAlloc(allocator) catch |err| {
                        std.debug.print("WM_CREATE: Failed to get self executable path: {any}\n", .{err});
                        return -1;
                    };
                    defer allocator.free(exe_path);

                    const exe_dir = std.fs.path.dirname(exe_path).?;

                    const html_path = std.fs.path.join(allocator, &.{ exe_dir, "testvirtualhost", "main.html" }) catch |err| {
                        std.debug.print("WM_CREATE: Failed to join path: {any}\n", .{err});
                        return -1;
                    };
                    defer allocator.free(html_path);

                    if (std.fs.openFileAbsolute(html_path, .{.mode = .read_only})) |content_file| {
                        defer content_file.close();
                        const content = content_file.readToEndAlloc(allocator, 1 * 1024 * 1024) catch |read_err| {
                            std.debug.print("WM_CREATE: Failed to read HTML content for virtual host from '{s}': {any}\n", .{ html_path, read_err });
                            return -1;
                        };
                        defer allocator.free(content);

                        const buffer_with_null = allocator.alloc(u8, content.len + 1) catch |alloc_err| {
                            std.debug.print("WM_CREATE: Failed to allocate buffer for HTML content: {any}\n", .{alloc_err});
                            return -1;
                        };
                        @memcpy(buffer_with_null[0..content.len], content);
                        buffer_with_null[content.len] = 0;
                        g_html_content_buffer_for_virtual_host = buffer_with_null;
                    } else |err| {
                        if (err == error.FileNotFound) {
                            const html_dir_path = std.fs.path.dirname(html_path).?;
                            std.fs.makeDirAbsolute(html_dir_path) catch |mkdir_err| {
                                if (mkdir_err != error.PathAlreadyExists) {
                                    std.debug.print("WM_CREATE: Failed to create directory '{s}': {any}\n", .{ html_dir_path, mkdir_err });
                                    return -1;
                                }
                            };

                           const file = std.fs.createFileAbsolute(html_path, .{}) catch |create_err| {
                                std.debug.print("WM_CREATE: Failed to create HTML file at '{s}': {any}\n", .{ html_path, create_err });
                                return -1;
                            };
                            const default_html_content = "<html><head><meta charset=\"UTF-8\"></head><body><h1>Hello from NamiZig!</h1><button id=\"myButton\">Send Message to Zig</button><template click, 'myButton', timestamp: new Date().toISOString()></template></body></html>";
                            file.writeAll(default_html_content) catch |write_err| {
                                std.debug.print("WM_CREATE: Failed to write default HTML content to '{s}': {any}\n", .{ html_path, write_err });
                            };
                            file.close();

                            const new_file = std.fs.openFileAbsolute(html_path, .{.mode = .read_only}) catch |read_err| {
                                std.debug.print("WM_CREATE: Failed to read newly created HTML file: {any}\n", .{read_err});
                                return -1;
                            };
                            defer new_file.close();
                            const content = new_file.readToEndAlloc(allocator, 1 * 1024 * 1024) catch |read_err| {
                                std.debug.print("WM_CREATE: Failed to read content from newly created file: {any}\n", .{read_err});
                                return -1;
                            };
                            defer allocator.free(content);

                            const buffer_with_null = allocator.alloc(u8, content.len + 1) catch |alloc_err| {
                                std.debug.print("WM_CREATE: Failed to allocate buffer for HTML content: {any}\n", .{alloc_err});
                                return -1;
                            };
                            @memcpy(buffer_with_null[0..content.len], content);
                            buffer_with_null[content.len] = 0;
                            g_html_content_buffer_for_virtual_host = buffer_with_null;
                        } else {
                            std.debug.print("WM_CREATE: Failed to read HTML content for virtual host from '{s}': {any}\n", .{ html_path, err });
                        }
                    }

                    if (g_html_content_buffer_for_virtual_host) |buffer| {
                        g_settings.webview_controller_settings.htmlContent = @ptrCast(buffer.ptr);
                    } else {
                        g_settings.webview_controller_settings.htmlContent = null;
                    }
                }

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

                hr = c.register_web_message_handler(g_webview_controller.?, webMessageReceived);

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

                if (g_settings.webview_controller_settings.isVirtualHost) {
                    const navigate_url = "https://assets.namizig.com/main.html";
                    hr = c.navigate_webview(g_webview_controller.?, navigate_url.ptr);
                } else if (init_navigate_to) |url| {
                    hr = c.navigate_webview(g_webview_controller.?, url.ptr);
                } else {
                    hr = S_OK;
                }
                if (hr != S_OK) {
                    std.debug.print("Failed to navigate in WM_CREATE. HRESULT: 0x{X:0>8}\n", .{hr});
                }
            }
        }
            return 0;
        },

        WM_WEB_MESSAGE => {
            const message_len: usize = @intCast(wParam);
            const message_ptr: [*]u8 = @ptrFromInt(@as(usize, @bitCast(lParam)));
            const message_slice = message_ptr[0..message_len];

            std.debug.print("WM_WEB_MESSAGE received: {s}\n", .{message_slice});

            const allocator = std.heap.page_allocator;
            defer allocator.free(message_slice);

            var gpa = std.heap.GeneralPurposeAllocator(.{}){};
            const json_allocator = gpa.allocator();
            defer _ = gpa.deinit();

            const parsed = std.json.parseFromSlice(std.json.Value, json_allocator, message_slice, .{}) catch |err| {
                std.debug.print("WM_WEB_MESSAGE: Failed to parse JSON message: {any}\n", .{err});
                return 0;
            };
            defer parsed.deinit();

            const message_obj = parsed.value.object;
            if (message_obj.get("event_key")) |event_key_val| {
                if (event_key_val.string.len > 0)  {
                    const event_key = event_key_val.string;
                    if (g_web_message_handlers.get(event_key)) |handler| {
                        handler(hwnd, parsed.value);
                    } else {
                        std.debug.print("WM_WEB_MESSAGE: Unhandled event key: {s}\n", .{event_key});
                    }
                }
            }

            return 0;
        },

        win32.ui.windows_and_messaging.WM_DESTROY => {
            std.debug.print("WM_DESTROY entered. g_webview_controller: {?}, g_webview_environment: {?}\n", .{ g_webview_controller, g_webview_environment });
           
            // cleanup webview if it exists
            if (g_webview_controller != null and g_webview_environment != null) {
                std.debug.print("WM_DESTROY: Condition met. Calling cleanup_webview with controller: {?} and environment: {?}\n", .{g_webview_controller.?, g_webview_environment.?});
                c.cleanup_webview(g_webview_controller.?, g_webview_environment.?);
                g_webview_controller = null;
                g_webview_environment = null;
            } else {
                std.debug.print("WM_DESTROY: Condition NOT met. Skipping cleanup_webview. Controller was: {?}, Environment was: {?}\n", .{g_webview_controller, g_webview_environment});
            }

            // cleanup toolbar if it exists
            if (g_hMenuFile) |hMenu| {
                _ = win32.ui.windows_and_messaging.DestroyMenu(hMenu);
                g_hMenuFile = null;
            }

            // cleanup toolbar text
            if (g_text_file_button.len > 0) {
                const slice_u16: []const u16 = g_text_file_button;
                std.heap.page_allocator.free(std.mem.sliceAsBytes(slice_u16));
                g_text_file_button = undefined;
            }

            if (g_html_content_buffer_for_virtual_host) |buffer| {
                std.heap.page_allocator.free(buffer);
                g_html_content_buffer_for_virtual_host = null;
            }

            g_web_message_handlers.deinit();

            // cleanup language controller
            g_language_strings.deinit();

            win32.ui.windows_and_messaging.PostQuitMessage(0);
            return 0;
        },
        win32.ui.windows_and_messaging.WM_NOTIFY => {
            const pnmh: *win32.ui.controls.NMHDR = @ptrFromInt(@as(usize, @bitCast(lParam)));
            if (pnmh.hwndFrom == g_hToolbar.?) {

                if (pnmh.code == c.WRAPPER_NM_CUSTOMDRAW) {
                    const pcd: *win32.ui.controls.NMTBCUSTOMDRAW = @ptrCast(pnmh);
                    switch (pcd.nmcd.dwDrawStage) {
                        win32.ui.controls.CDDS_PREPAINT => {
                            const hBrush = win32.graphics.gdi.CreateSolidBrush(g_settings.theme_settings.toolbar_background_color);
                            if (hBrush != null) {
                                _ = win32.graphics.gdi.FillRect(pcd.nmcd.hdc, &pcd.nmcd.rc, hBrush);
                                _ = win32.graphics.gdi.DeleteObject(hBrush);
                            }
                            return win32.ui.controls.CDRF_NOTIFYITEMDRAW;
                        },
                        win32.ui.controls.CDDS_ITEMPREPAINT => {
                            pcd.clrText = g_settings.theme_settings.toolbar_button_text_color;
                            pcd.clrBtnFace = g_settings.theme_settings.toolbar_button_color;
                            return win32.ui.controls.CDRF_NEWFONT;
                        },
                        else => {}
                    }
                    return win32.ui.controls.CDRF_DODEFAULT;
                }

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
                        }
                    }
                    return 0;
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

