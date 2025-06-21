const std = @import("std");

pub const language_controller = struct {

    allocator: std.mem.Allocator,
    language_strings: std.AutoHashMap(languageKey, []const u8),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, lang: languages) !Self {

        var self = Self{
            .allocator = allocator,
            .language_strings = std.AutoHashMap(languageKey, []const u8).init(allocator),
        };

        switch (lang) {
            .en => {
               self.language_strings.put(languageKey.file, "File") catch |err| return err;
               self.language_strings.put(languageKey.exit, "Exit") catch |err| return err;
            },
            .ja => {
               self.language_strings.put(languageKey.file, "ファイル") catch |err| return err;
               self.language_strings.put(languageKey.exit, "終了") catch |err| return err;
            },
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.language_strings.deinit();
    }
    

    pub const languages = enum {
        en,
        ja
    };

    pub const languageKey = enum {
        file,
        exit,
    };

    pub fn getLanguageString(self: Self,key: languageKey) []const u8 {
        return self.language_strings.get(key) orelse return "";
    }
};