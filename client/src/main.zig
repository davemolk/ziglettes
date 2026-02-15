const std = @import("std");
const client = @import("client");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const check = gpa.deinit();
        if (check == .leak) std.log.err("oh no a leak", .{});
    }

    const a = gpa.allocator();
    try client.run(a);
}
