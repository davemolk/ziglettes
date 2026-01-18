const std = @import("std");
const cat = @import("cat");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    try cat.run(alloc);
}
