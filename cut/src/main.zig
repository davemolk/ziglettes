const std = @import("std");
const cut = @import("cut");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const check = gpa.deinit();
        if (check == .leak) {
            std.log.err("leak detected", .{});
        }
    }
    const alloc = gpa.allocator();

    try cut.run(alloc);
}
