const std = @import("std");
const builtin = @import("builtin");
const setting = @import("setting.zig");
const c = @cImport({
    @cInclude("webview_wrapper_c.h");
});
const lang = @import("lang.zig");
const win32 = @import("win32");

pub const c_Controller_settings = c.controllerSettings;

pub const HWND_HANDLE = c.HWND_HANDLE;
pub const COINIT = win32.system.com.COINIT_APARTMENTTHREADED;
pub const HWND = win32.foundation.HWND;
const S_OK: c.HRESULT = 0;
const ODT_MENU: u32 = 1;
const WM_WEB_MESSAGE = win32.ui.windows_and_messaging.WM_APP + 2;

pub fn RGB(r: u8, g: u8, b: u8) !u32 {
    return @as(u32, r) | (@as(u32, g) << 8) | (@as(u32, b) << 16);
}


pub const WindowGen = struct {

    const Self = @This();
    const NAVIGATE_TIMER_ID: usize = 1;


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

    allocator: std.mem.Allocator,
    hwnd: ?HWND = null,
    webview_environment: ?*anyopaque = null,
    webview_controller: ?*anyopaque = null,
    settings: *setting.WindowSettings = undefined,
    hToolbar: ?win32.foundation.HWND = null,
    hMenuFile: ?win32.ui.windows_and_messaging.HMENU = null,
    language_strings: lang.language_controller = undefined,
    html_content_buffer_for_virtual_host: ?[]u8 = null,
    init_navigate_to: ?[:0]const u8 = null,


    web_message_handlers: std.StringHashMap(WebMessageHandler) = undefined,
    web_message_handler_allocator: std.mem.Allocator = undefined,

    text_file_button: [:0]const u16 = undefined,

const ID_TOOLBAR: u32 = 1001;
const ID_FILE_BUTTON: u32 = 1002;
const ID_FILE_EXIT: u32 = 1003;

pub const WebMessageHandler = *const fn (hwnd: HWND, message: std.json.Value) anyerror!void;

pub var g_window_manager: ?*WindowManager = null;

fn webMessageReceived(hwnd_handle: HWND_HANDLE, message_json: [*c]const u8) callconv(std.os.windows.WINAPI) void {
    std.debug.print("Zig: webMessageReceived entered. HWND_HANDLE={?}, message_ptr={*}\n", .{hwnd_handle, message_json});

    const hwnd: HWND = @ptrFromInt(@intFromPtr(hwnd_handle orelse {
        std.debug.print("Zig: webMessageReceived received a null HWND. Aborting.\n", .{});
        return;
    }));

    if (g_window_manager) |wm| {
        if (wm.windows.get(hwnd)) |window_instance| {
            _ = window_instance;

            const message_len: usize = if (message_json == null) 0 else std.mem.len(message_json);
            const message_ptr_for_lparam: win32.foundation.LPARAM = @intCast(@intFromPtr(message_json));

            std.debug.print("Zig: Posting WM_WEB_MESSAGE to message queue...\n", .{});
            _ = win32.ui.windows_and_messaging.PostMessageW(hwnd, WM_WEB_MESSAGE, message_len, message_ptr_for_lparam);
            std.debug.print("Zig: PostMessageW returned. webMessageReceived exiting.\n", .{});
            return;
        }
    }
    std.debug.print("Zig: webMessageReceived: Could not find window instance for HWND={?} or g_window_manager is null.\n", .{hwnd});
}

fn onWebViewCreated(hr: c.HRESULT, controller: ?*anyopaque, context: ?*anyopaque) callconv(std.os.windows.WINAPI) void {
    std.debug.print("Zig: onWebViewCreated callback entered. HR=0x{X:0>8}, controller={?}, context={?}\n", .{ hr, controller, context });

    const window_instance: *WindowGen = @ptrCast(@alignCast(context orelse {
        std.debug.print("onWebViewCreated: context is null, cannot proceed.\n", .{});
        if (controller) |controller_ptr| {
            c.cleanup_webview(controller_ptr, null);
        }
        return;
    }));

    if (hr != S_OK) {
        std.debug.print("onWebViewCreated: WebView creation failed. HRESULT: 0x{X:0>8}\n", .{hr});
        return;
    }

    if (controller == null) {
        std.debug.print("onWebViewCreated: Succeeded but controller is null.\n", .{});
        return;
    }

    window_instance.webview_controller = controller;
    std.debug.print("WebView created successfully and assigned to window instance.\n", .{});

    var post_create_hr = c.setup_accelerator_handler(window_instance.webview_controller.?);
    if (post_create_hr != S_OK) {
        std.debug.print("onWebViewCreated: setup_accelerator_handler failed. HRESULT: 0x{X:0>8}\n", .{post_create_hr});
    }

    post_create_hr = c.register_web_message_handler(window_instance.webview_controller.?, webMessageReceived);
    if (post_create_hr != S_OK) {
        std.debug.print("onWebViewCreated: register_web_message_handler failed. HRESULT: 0x{X:0>8}\n", .{post_create_hr});
    }

    var client_rect: win32.foundation.RECT = undefined;
    _ = win32.ui.windows_and_messaging.GetClientRect(window_instance.hwnd.?, &client_rect);

    var toolbar_height: i32 = 0;
    if (window_instance.hToolbar) |hToolbar| {
        var toolbar_rect: win32.foundation.RECT = undefined;
        if (win32.ui.windows_and_messaging.GetWindowRect(hToolbar, &toolbar_rect) != 0) {
            toolbar_height = toolbar_rect.bottom - toolbar_rect.top;
        }
    }

    const init_rect = c.RECT{
        .left = client_rect.left,
        .top = client_rect.top + toolbar_height,
        .right = client_rect.right,
        .bottom = client_rect.bottom,
    };
    if (init_rect.bottom > init_rect.top and init_rect.right > init_rect.left) {
        c.resize_webview(window_instance.webview_controller.?, init_rect);
    }

    _ = win32.ui.windows_and_messaging.SetTimer(window_instance.hwnd.?, NAVIGATE_TIMER_ID, 100, null);
}

pub const WindowManager = struct {
    allocator: std.mem.Allocator,
    windows: std.AutoHashMap(HWND, *WindowGen),

    pub fn init(allocator: std.mem.Allocator) !*WindowManager{
        const self = try allocator.create(WindowManager);
        self.* = .{
            .allocator = allocator,
            .windows = std.AutoHashMap(HWND, *WindowGen).init(allocator),
        };
        g_window_manager = self;
        return self;   
    }

    pub fn deinit(self: *WindowManager) void {
        self.windows.deinit();
        g_window_manager = null;
        self.allocator.destroy(self);
    }

    pub fn createWindow(self: *WindowManager, settings: *setting.WindowSettings) !*WindowGen {
        const window = try self.allocator.create(WindowGen);
        errdefer self.allocator.destroy(window);

        window.* = .{
            .allocator = undefined,
            .hwnd = null,
            .webview_environment = null,
            .webview_controller = null,
            .settings = undefined,
            .hToolbar = null,
            .hMenuFile = null,
            .language_strings = undefined,
            .html_content_buffer_for_virtual_host = null,
            .init_navigate_to = null,
            .web_message_handlers = undefined,
            .web_message_handler_allocator = undefined,
            .text_file_button = undefined,
        };

        try window.init(self.allocator, settings);

        try createWin32Window(window);

        return window;
    }

    pub fn get(self: *WindowManager, hwnd: HWND) !*WindowGen {
        return self.windows.get(hwnd).?;
    }

};


pub fn init(self: *Self, allocator: std.mem.Allocator, settings: *setting.WindowSettings) !void {
    self.allocator = allocator;
    self.settings = settings;
    self.web_message_handlers = std.StringHashMap(WebMessageHandler).init(allocator);
    self.language_strings = try lang.language_controller.init(allocator, settings.language);
}

pub fn deinit(self: *Self) void {
    self.web_message_handlers.deinit();
    self.language_strings.deinit();
}

pub fn registerWebMessageHandler(self: *Self,event_key: []const u8, handler: WebMessageHandler) !void {
    try self.web_message_handlers.put(event_key, handler);
}


pub fn navigate(self: *Self, url: [:0]const u8) !void {
    if (self.webview_controller) |controller| {
        const hr = c.navigate_webview(controller, url.ptr);
        if (hr != S_OK) return error.NavigationFailed;
    } else {
        return error.WebViewNotReady;
    }
}

fn createWin32Window(window: *WindowGen) !void {
    const settings = window.settings;

    const WNDCLASSW = win32.ui.windows_and_messaging.WNDCLASSW;
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

    window.init_navigate_to = settings.navigatge_to;

    const hInstance = win32.system.library_loader.GetModuleHandleW(null);

    const class_name_utf16_z = try std.unicode.utf8ToUtf16LeAllocZ(window.allocator, "NamiZIgWindow");
    defer window.allocator.free(std.mem.sliceAsBytes(@as([]const u16, class_name_utf16_z)));

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


    const window_title = try std.unicode.utf8ToUtf16LeAllocZ(window.allocator, settings.title);
    defer window.allocator.free(std.mem.sliceAsBytes(@as([]const u16, window_title)));

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
        window,
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
}

pub fn show(self: *Self) !void {
    if (self.hwnd) |hwnd| {
        _ = win32.ui.windows_and_messaging.ShowWindow(hwnd, win32.ui.windows_and_messaging.SW_SHOW);
    }
}

pub fn messageLoop(self: *Self) !void {
     _ = self;

     const MSG = win32.ui.windows_and_messaging.MSG;
        var msg: MSG = undefined;
        while (win32.ui.windows_and_messaging.GetMessageW(&msg, null, 0, 0) != 0) {

            _ = win32.ui.windows_and_messaging.TranslateMessage(&msg);
            _ = win32.ui.windows_and_messaging.DispatchMessageW(&msg);
    }
}

// Procedure

const CREATE_WEBVIEW_MSG: u32 = win32.ui.windows_and_messaging.WM_APP + 1;

fn windowProc(hwnd: win32.foundation.HWND, msg: u32, wParam: win32.foundation.WPARAM, lParam: win32.foundation.LPARAM) callconv(std.os.windows.WINAPI) win32.foundation.LRESULT {
    var self: ?*WindowGen = @ptrFromInt(@as(usize, @bitCast(win32.ui.windows_and_messaging.GetWindowLongPtrW(hwnd, win32.ui.windows_and_messaging.GWLP_USERDATA))));

    if (self == null) {
        if (msg == win32.ui.windows_and_messaging.WM_NCCREATE) {
            const create_struct: *const win32.ui.windows_and_messaging.CREATESTRUCTW = @ptrFromInt(@as(usize, @bitCast(lParam)));
            const window_instance: *WindowGen = @alignCast(@ptrCast(create_struct.lpCreateParams.?));
            window_instance.hwnd = hwnd;
            
            _ = win32.ui.windows_and_messaging.SetWindowLongPtrW(hwnd, win32.ui.windows_and_messaging.GWLP_USERDATA, @intCast(@intFromPtr(window_instance)));

            g_window_manager.?.windows.put(hwnd, window_instance) catch |err| {
                std.debug.print("Failed to add window to manager: {any}\n", .{err});
                return 0;
            };
            self = window_instance;

        } else {
            return win32.ui.windows_and_messaging.DefWindowProcW(hwnd, msg, wParam, lParam);
        }
    }

    const window_instance = self.?;
    
    switch (msg) {
        win32.ui.windows_and_messaging.WM_SIZE => {
            if (window_instance.webview_controller) |controller| {
                var client_rect: win32.foundation.RECT = undefined;
                _ = win32.ui.windows_and_messaging.GetClientRect(hwnd, &client_rect);

                var toolbar_height: i32 = 0;
                if (window_instance.hToolbar) |hToobar| {
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

            if (window_instance.hToolbar) |hToolbar| {
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

            const hInstance = win32.system.library_loader.GetModuleHandleW(null);
            if (hInstance == null) {
                std.debug.print("WM_CREATE: GetModuleHandleW failed.\n", .{});
                return -1;
            }

            if (window_instance.settings.toolbar) {
                const toolbar_class_name_u8_fixed_array_ptr: *const [15:0]u8 = win32.ui.controls.TOOLBARCLASSNAMEW;

                const toolbar_class_name_u8_c_ptr: [*c]const u8 = @ptrCast(toolbar_class_name_u8_fixed_array_ptr);

                const toolbar_class_name_u8_slice: [:0]const u8 = std.mem.sliceTo(toolbar_class_name_u8_c_ptr, 0);

                const toolbar_class_name_utf16_z = std.unicode.utf8ToUtf16LeAllocZ(
                    window_instance.allocator,
                    toolbar_class_name_u8_slice,
                    ) catch |err| {
                        std.debug.print("WM_CREATE: utf8ToUtf16LeAllocZ for toolbar class name failed: {any}\n", .{err});
                        return -1;
                    };

                defer window_instance.allocator.free(std.mem.sliceAsBytes(@as([]const u16, toolbar_class_name_utf16_z)));
                
                const style_bits: u32 =
                    win32.ui.controls.TBSTYLE_FLAT |
                    win32.ui.controls.TBSTYLE_TOOLTIPS |
                    @as(u32, @bitCast(win32.ui.windows_and_messaging.WS_CHILD)) |
                    @as(u32, @bitCast(win32.ui.windows_and_messaging.WS_VISIBLE));
                
               

                window_instance.hToolbar = win32.ui.controls.CreateToolbarEx(
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
                _ = c.wrapper_SetWindowTheme(@ptrFromInt(@intFromPtr(window_instance.hToolbar.?)), empty_theme.ptr, empty_theme.ptr);

                if (window_instance.hToolbar == null) {
                    std.debug.print("WM_CREATE: CreateWindowExW for toolbar failed.\n", .{});
                    return -1;
                }

                _ =win32.ui.windows_and_messaging.SendMessageW(window_instance.hToolbar.?, win32.ui.controls.TB_BUTTONSTRUCTSIZE, @sizeOf(win32.ui.controls.TBBUTTON), 0);

                const file_button_text_utf16 = std.unicode.utf8ToUtf16LeAllocZ(window_instance.allocator, window_instance.language_strings.getLanguageString(.file)) catch |err| {
                    std.debug.print("WM_CREATE: utf8ToUtf16LeAllocZ for file_button_text_utf16 failed: {any}\n", .{err});
                    return -1;
                };

                window_instance.text_file_button = file_button_text_utf16;

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
                    window_instance.hToolbar.?,
                    win32.ui.controls.TB_ADDBUTTONS,
                    1,
                    @intCast(@intFromPtr(&tbButtonFile)),
                );

                window_instance.hMenuFile = win32.ui.windows_and_messaging.CreatePopupMenu();
                if (window_instance.hMenuFile == null) {
                    std.debug.print("WM_CREATE: CreatePopupMenu for file menu failed.\n", .{});
                    return -1;
                }

                const exit_menu_text_utf16 = std.unicode.utf8ToUtf16LeAllocZ(window_instance.allocator, window_instance.language_strings.getLanguageString(.exit)) catch |err| {
                    std.debug.print("WM_CREATE: utf8ToUtf16LeAllocZ for exit_menu_text_utf16 failed: {any}\n", .{err});
                    _ = win32.ui.windows_and_messaging.DestroyMenu(window_instance.hMenuFile.?);
                    window_instance.hMenuFile = null;
                    return -1;
                };  
                defer window_instance.allocator.free(std.mem.sliceAsBytes(@as([]const u16, exit_menu_text_utf16)));

                if (win32.ui.windows_and_messaging.AppendMenuW(
                    window_instance.hMenuFile.?,
                    win32.ui.windows_and_messaging.MF_OWNERDRAW,
                    ID_FILE_EXIT,
                    exit_menu_text_utf16.ptr,
                ) == 0) {
                    std.debug.print("WM_CREATE: AppendMenuW for exit menu item failed.\n", .{});
                    _ = win32.ui.windows_and_messaging.DestroyMenu(window_instance.hMenuFile.?);
                    window_instance.hMenuFile = null;
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
                    window_instance.settings.theme_settings.toolbar_button_color
                else
                    window_instance.settings.theme_settings.toolbar_background_color;

                const hBrush = win32.graphics.gdi.CreateSolidBrush(bgColor);
                if (hBrush != null) {
                    _ = win32.graphics.gdi.FillRect(pDrawItem.hDC, &pDrawItem.rcItem, hBrush);
                    _ = win32.graphics.gdi.DeleteObject(hBrush);
                }

                _ = win32.graphics.gdi.SetTextColor(pDrawItem.hDC, window_instance.settings.theme_settings.toolbar_button_text_color);
                _ = win32.graphics.gdi.SetBkMode(pDrawItem.hDC, win32.graphics.gdi.TRANSPARENT);

                const text_u8 = switch (pDrawItem.itemID) {
                    ID_FILE_EXIT => window_instance.language_strings.getLanguageString(.exit),
                    else => return win32.ui.windows_and_messaging.DefWindowProcW(hwnd, msg, wParam, lParam),
                };
                
                const text_alloc = window_instance.allocator;
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
        win32.ui.windows_and_messaging.WM_TIMER => {
            if (wParam == NAVIGATE_TIMER_ID) {
                _ = win32.ui.windows_and_messaging.KillTimer(hwnd, NAVIGATE_TIMER_ID);

                if (window_instance.webview_controller) |controller| {
                    var hr: c.HRESULT = S_OK;
                    if (window_instance.settings.webview_controller_settings.isVirtualHost) {
                    const vhost_name = window_instance.settings.webview_controller_settings.virtualHostName;
                    const navigate_url_z = std.fmt.allocPrintZ(
                        window_instance.allocator,
                        "https://{s}/main.html",
                        .{vhost_name},
                    ) catch |err| {
                        std.debug.print("Failed to allocate navigate URL: {any}\n", .{err});
                        return -1;
                    };
                    defer window_instance.allocator.free(navigate_url_z);
                    std.debug.print("Navigating to virtual host URL: {s}\n", .{navigate_url_z});
                    hr = c.navigate_webview(controller, navigate_url_z.ptr);
                } else if (window_instance.init_navigate_to) |url| {
                    hr = c.navigate_webview(controller, url.ptr);
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

        CREATE_WEBVIEW_MSG => {
            if (window_instance.webview_controller == null) {

                var hr = c.create_webview_environment(&window_instance.webview_environment);
                if (hr != S_OK) {
                    std.debug.print("WM_CREATE: create_webview_environment failed. HRESULT: 0x{X:0>8}\n", .{hr});
                    return -1;
                }

               
                var final_settings = window_instance.settings.webview_controller_settings;

               
                if (final_settings.isVirtualHost) {
                    const allocator = window_instance.allocator;
                    const exe_path = std.fs.selfExePathAlloc(allocator) catch |err| {
                        std.debug.print("WM_CREATE: Failed to get self exe path: {any}\n", .{err});
                        return -1;
                    };
                    defer allocator.free(exe_path);

                    const exe_dir = std.fs.path.dirname(exe_path) orelse ".";

                    const vhost_name_slice = std.mem.span(final_settings.virtualHostName);
                    const vhost_folder_path = std.fs.path.joinZ(allocator, &.{ exe_dir, vhost_name_slice }) catch |err| {
                        std.debug.print("WM_CREATE: Failed to join vhost folder path: {any}\n", .{err});
                        return -1;
                    };

                  
                    window_instance.html_content_buffer_for_virtual_host = vhost_folder_path;

                    std.fs.makeDirAbsolute(vhost_folder_path) catch |mkdir_err| {
                        if (mkdir_err != error.PathAlreadyExists) {
                            std.debug.print("WM_CREATE: Failed to create directory '{s}': {any}\n", .{ vhost_folder_path, mkdir_err });
                            return -1;
                        }
                    };
                    const main_html_path = std.fs.path.join(allocator, &.{ vhost_folder_path, "main.html" }) catch |err| {
                        std.debug.print("WM_CREATE: Failed to join main.html path: {any}\n", .{err});
                        return -1;
                    };
                    defer allocator.free(main_html_path);

                    const file = std.fs.createFileAbsolute(main_html_path, .{}) catch |create_err| {
                        std.debug.print("WM_CREATE: Failed to create/overwrite HTML file '{s}': {any}\n", .{ main_html_path, create_err });
                        return -1;
                    };
                    defer file.close();

                    const default_html_content = "<html><head><meta charset=\"UTF-8\"></head><body>" ++
                        "<h1>Hello from NamiZig Virtual Host!</h1>" ++
                        "<button onclick=\"window.chrome.webview.postMessage({event_key: 'exitAPP'})\">Exit App</button>" ++
                        "<button onclick=\"window.chrome.webview.postMessage({event_key: 'showName'})\">Show Name</button>" ++
                        "<button onclick=\"window.chrome.webview.postMessage({event_key: 'nav_google'})\">Navigate to Google</button>" ++
                        "</body></html>";
                    file.writer().writeAll(default_html_content) catch |write_err| {
                        std.debug.print("WM_CREATE: Failed to write default HTML to '{s}': {any}\n", .{ main_html_path, write_err });
                    };

                    final_settings.htmlContent = @ptrCast(vhost_folder_path.ptr);
                    std.debug.print("Setting htmlContent (folder path) to: {s}\n", .{vhost_folder_path});
                }

                hr = c.create_webview_controller_async(
                    window_instance.webview_environment.?,
                    @ptrFromInt(@intFromPtr(hwnd)),
                    &final_settings,
                    onWebViewCreated,
                    window_instance,
                );

                if (hr != S_OK) {
                    std.debug.print("CREATE_WEBVIEW_MSG: create_webview_controller_async failed to start. HRESULT: 0x{X:0>8}\n", .{hr});
                    return -1;
                }
            }
            return 0;
        },

        WM_WEB_MESSAGE => {
            std.debug.print("Zig: windowProc received WM_WEB_MESSAGE.\n", .{});


            const message_len: usize = @intCast(wParam);
            const message_ptr: ?*anyopaque = @ptrFromInt(@as(usize, @bitCast(lParam)));

            if (message_ptr == null) {
                std.debug.print("Zig: WM_WEB_MESSAGE lParam is null. Aborting.\n", .{});
                return 0;
            }
            defer win32.system.com.CoTaskMemFree(message_ptr.?);

            const message_slice = (@as([*]u8, @ptrCast(message_ptr.?)))[0..message_len];

            std.debug.print("Zig: WM_WEB_MESSAGE payload: {s}\n", .{message_slice});

            const allocator = window_instance.allocator;
            var arena = std.heap.ArenaAllocator.init(allocator);
            defer arena.deinit();
            const json_allocator = arena.allocator();

            const parsed = std.json.parseFromSlice(std.json.Value, json_allocator, message_slice, .{}) catch |err| {
                std.debug.print("WM_WEB_MESSAGE: Failed to parse JSON message: {any}\n", .{err});
                return 0;
            };

            const message_obj = parsed.value.object;
            if (message_obj.get("event_key")) |event_key_val| {
                if (event_key_val.string.len > 0)  {
                    const event_key = event_key_val.string;
                    if (window_instance.web_message_handlers.get(event_key)) |handler| {
                        handler(hwnd, parsed.value) catch |err| {
                            std.debug.print("WM_WEB_MESSAGE: Handler failed: {any}\n", .{err});
                        };
                    } else {
                        std.debug.print("WM_WEB_MESSAGE: Unhandled event key: {s}\n", .{event_key});
                    }
                }
            }

            return 0;
        },

        win32.ui.windows_and_messaging.WM_DESTROY => {
            std.debug.print("WM_DESTROY entered. webview_controller: {?}, webview_environment: {?}\n", .{ window_instance.webview_controller, window_instance.webview_environment });
           
            if (window_instance.webview_controller != null and window_instance.webview_environment != null) {
                std.debug.print("WM_DESTROY: Condition met. Calling cleanup_webview with controller: {?} and environment: {?}\n", .{window_instance.webview_controller.?, window_instance.webview_environment.?});
                c.cleanup_webview(window_instance.webview_controller.?, window_instance.webview_environment.?);
                window_instance.webview_controller = null;
                window_instance.webview_environment = null;
            } else {
                std.debug.print("WM_DESTROY: Condition NOT met. Skipping cleanup_webview. Controller was: {?}, Environment was: {?}\n", .{window_instance.webview_controller, window_instance.webview_environment});
            }

            if (window_instance.hMenuFile) |hMenu| {
                _ = win32.ui.windows_and_messaging.DestroyMenu(hMenu);
                window_instance.hMenuFile = null;
            }


            if (window_instance.text_file_button.len > 0) {
                const slice_u16: []const u16 = window_instance.text_file_button;
                window_instance.allocator.free(std.mem.sliceAsBytes(slice_u16));
                window_instance.text_file_button = undefined;
            }

            if (window_instance.html_content_buffer_for_virtual_host) |buffer| {
                window_instance.allocator.free(buffer);
                window_instance.html_content_buffer_for_virtual_host = null;
            }

            if (g_window_manager.?.windows.fetchRemove(hwnd)) |removed| {
                const removed_instance = removed.value;
                removed_instance.deinit();
                g_window_manager.?.allocator.destroy(removed_instance);
            }


            if (g_window_manager.?.windows.count() == 0) {
                win32.ui.windows_and_messaging.PostQuitMessage(0);
            }
            
            return 0;
        },
        win32.ui.windows_and_messaging.WM_NCDESTROY => {
            _ = win32.ui.windows_and_messaging.SetWindowLongPtrW(hwnd, win32.ui.windows_and_messaging.GWLP_USERDATA, 0);
            return 0;
        },
        win32.ui.windows_and_messaging.WM_NOTIFY => {
            const pnmh: *win32.ui.controls.NMHDR = @ptrFromInt(@as(usize, @bitCast(lParam)));
            if (pnmh.hwndFrom == window_instance.hToolbar.?) {

                if (pnmh.code == c.WRAPPER_NM_CUSTOMDRAW) {
                    const pcd: *win32.ui.controls.NMTBCUSTOMDRAW = @ptrCast(pnmh);
                    switch (pcd.nmcd.dwDrawStage) {
                        win32.ui.controls.CDDS_PREPAINT => {
                            const hBrush = win32.graphics.gdi.CreateSolidBrush(window_instance.settings.theme_settings.toolbar_background_color);
                            if (hBrush != null) {
                                _ = win32.graphics.gdi.FillRect(pcd.nmcd.hdc, &pcd.nmcd.rc, hBrush);
                                _ = win32.graphics.gdi.DeleteObject(hBrush);
                            }
                            return win32.ui.controls.CDRF_NOTIFYITEMDRAW;
                        },
                        win32.ui.controls.CDDS_ITEMPREPAINT => {
                            const item_state = pcd.nmcd.uItemState;
                            if ((item_state & win32.ui.controls.CDIS_HOT) != 0 or (item_state & win32.ui.controls.CDIS_SELECTED) != 0) {
                                pcd.clrBtnFace = window_instance.settings.theme_settings.toolbar_button_color;
                            }
                            pcd.clrText = window_instance.settings.theme_settings.toolbar_button_text_color;
                            return win32.ui.controls.CDRF_NEWFONT;
                        },
                        else => {}
                    }
                    return win32.ui.controls.CDRF_DODEFAULT;
                }

                if (pnmh.code == c.WRAPPER_TBN_DROPDOWN) {
                    const pnmtb: *win32.ui.controls.NMTOOLBARW = @ptrCast(@alignCast(pnmh));
                    if (pnmtb.iItem == ID_FILE_BUTTON) {
                        if (window_instance.hMenuFile) |hMenuFile| {
                            var rc: win32.foundation.RECT = undefined;
                            _ = win32.ui.windows_and_messaging.SendMessageW(window_instance.hToolbar.?, win32.ui.controls.TB_GETRECT, ID_FILE_BUTTON, @intCast(@intFromPtr(&rc)));

                            var pt: win32.foundation.POINT = undefined;
                            pt.x = rc.left;
                            pt.y = rc.bottom;
                            _ = win32.graphics.gdi.ClientToScreen(window_instance.hToolbar.?, &pt);

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
};
