const std = @import("std");
const cleaner = @import("clean_zig");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const check = gpa.deinit();
        if (check == .leak) {
            std.log.err("memory leak :/", .{});
        }
    }

    const alloc = gpa.allocator();
    try cleaner.run(alloc);
}
