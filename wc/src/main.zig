const std = @import("std");
const wc = @import("wc");

pub fn main() !void {
    var alloc = std.heap.DebugAllocator(.{}).init;
    defer _ = alloc.deinit();

    const gpa = alloc.allocator();

    try wc.run(gpa);
}
