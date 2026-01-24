const std = @import("std");
const uniq = @import("uniq");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

    const alloc = gpa.allocator();
    try uniq.run(alloc);
}
