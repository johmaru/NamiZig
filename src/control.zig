const std = @import("std");
const window_gen = @import("window_gen.zig");
const win32 = @import("win32");

pub const Control = struct {


    pub const Message_box_struct = struct {
        lpText: ?[]const u8,
        lpCaption: ?[]const u8,
        uType: WINDOWS_MESSAGING.MESSAGEBOX_STYLE,
    };

    pub const WINDOWS_MESSAGING = win32.ui.windows_and_messaging;

    pub fn message_box(allocator: std.mem.Allocator, message_box_struct: *Message_box_struct, hwnd: window_gen.HWND) !void {
        
        if (message_box_struct.lpText == null) {
            message_box_struct.lpText = "";
        }

        if (message_box_struct.lpCaption == null) {
            message_box_struct.lpCaption = "";
        }

        const title_w = toWideString(allocator, message_box_struct.lpCaption.?) catch return;
        defer allocator.free(std.mem.sliceAsBytes(@as([]const u16, title_w)));

        const text_w = toWideString(allocator, message_box_struct.lpText.?) catch return;
        defer allocator.free(std.mem.sliceAsBytes(@as([]const u16, text_w)));

        _ = win32.ui.windows_and_messaging.MessageBoxW(
            hwnd,
            text_w.ptr,
            title_w.ptr,
            message_box_struct.uType,
        );
    }

};

pub fn toWideString(allocator: std.mem.Allocator, str: []const u8) ![:0]u16 {
    return try std.unicode.utf8ToUtf16LeAllocZ(allocator, str);
}