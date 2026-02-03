const std = @import("std");
const tr = @import("tr");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const check = gpa.deinit();
        if (check != .ok) {
            std.log.err("leak detected :/", .{});
        }
    }
    const alloc = gpa.allocator();

    try tr.run(alloc);
}
