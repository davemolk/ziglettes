const std = @import("std");
const server = @import("server");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const leak = gpa.deinit();
        if (leak == .leak) {
            std.log.err("leak detected :/", .{});
        }
    }

    const a = gpa.allocator();

    try server.run(a);
}
