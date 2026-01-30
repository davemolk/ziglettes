const std = @import("std");
const ArrayList = std.ArrayList;

pub fn run(alloc: std.mem.Allocator) !void {
    var args = try parseArgs(alloc);
    defer args.deinit(alloc);

    var w_buf: [1024]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&w_buf);
    const w = &stdout.interface;

    if (args.paths.items.len > 0) {
        for (args.paths.items) |path| {
            var file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
            defer file.close();

            var buf: [1024]u8 = undefined;
            var f_reader = file.reader(&buf);
            const reader = &f_reader.interface;

            try processFile(alloc, reader, w, args.line_numbers, args.exclude_blanks);
        }
    } else {
        var file = std.fs.File.stdin();

        var buf: [1024]u8 = undefined;
        var f_reader = file.reader(&buf);
        const reader = &f_reader.interface;

        try processFile(alloc, reader, w, args.line_numbers, args.exclude_blanks);
    }
}

const Args = struct {
    line_numbers: bool,
    exclude_blanks: bool,
    paths: std.ArrayList([]const u8),

    pub fn deinit(self: *Args, alloc: std.mem.Allocator) void {
        for (self.paths.items) |p| {
            alloc.free(p);
        }

        self.paths.deinit(alloc);
    }
};

fn parseArgs(alloc: std.mem.Allocator) !Args {
    var iter = try std.process.argsWithAllocator(alloc);
    defer iter.deinit();

    _ = iter.skip();

    var args: Args = .{
        .line_numbers = false,
        .exclude_blanks = false,
        .paths = ArrayList([]const u8).empty,
    };

    while (iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "-n")) {
            args.line_numbers = true;
        } else if (std.mem.eql(u8, arg, "-b")) {
            args.exclude_blanks = true;
            args.line_numbers = true;
        } else if (std.mem.eql(u8, arg, "-")) {
            return args;
        } else {
            const path = try alloc.dupe(u8, arg);
            try args.paths.append(alloc, path);
        }
    }

    return args;
}

fn processFile(alloc: std.mem.Allocator, reader: *std.Io.Reader, writer: *std.Io.Writer, line_numbers: bool, exclude_blanks: bool) !void {
    var line = std.Io.Writer.Allocating.init(alloc);
    defer line.deinit();

    var i: usize = 1;
    while (true) : (i += 1) {
        _ = reader.streamDelimiter(&line.writer, '\n') catch |err| {
            if (err == error.EndOfStream) break else return err;
        };

        _ = reader.toss(1);

        if (line_numbers) {
            if (exclude_blanks and line.written().len == 0) {
                i -= 1;
                try writer.writeByte('\n');
            } else {
                try writer.print("{d}  {s}\n", .{ i, line.written() });
            }
        } else {
            try writer.print("{s}\n", .{line.written()});
        }

        line.clearRetainingCapacity();
    }

    if (line.written().len > 0) {
        if (line_numbers) {
            try writer.print("{d}  {s}\n", .{ i, line.written() });
        } else {
            try writer.print("{s}\n", .{line.written()});
        }
    }
    try writer.flush();
}

test "file ending with new line" {
    const alloc = std.testing.allocator;
    var reader: std.Io.Reader = .fixed("foo\nbar\nbaz\n");
    var buf: [512]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);

    try processFile(alloc, &reader, &w, false, false);
    try std.testing.expectEqualStrings("foo\nbar\nbaz\n", w.buffered());
}

test "file not ending with new line" {
    const alloc = std.testing.allocator;
    var reader: std.Io.Reader = .fixed("foo\nbar\nbaz");
    var buf: [512]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);

    try processFile(alloc, &reader, &w, false, false);
    try std.testing.expectEqualStrings("foo\nbar\nbaz\n", w.buffered());
}

test "number lines" {
    const alloc = std.testing.allocator;
    var reader: std.Io.Reader = .fixed("foo\nbar\nbaz");
    var buf: [512]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);

    try processFile(alloc, &reader, &w, true, false);
    try std.testing.expectEqualStrings("1  foo\n2  bar\n3  baz\n", w.buffered());
}

test "number lines with blanks" {
    const alloc = std.testing.allocator;
    var reader: std.Io.Reader = .fixed("foo\n\nbar\n\nbaz");
    var buf: [512]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);

    try processFile(alloc, &reader, &w, true, false);
    try std.testing.expectEqualStrings("1  foo\n2  \n3  bar\n4  \n5  baz\n", w.buffered());
}

test "exclude blanks" {
    const alloc = std.testing.allocator;
    var reader: std.Io.Reader = .fixed("foo\n\nbar\n\nbaz");
    var buf: [512]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);

    try processFile(alloc, &reader, &w, true, true);
    try std.testing.expectEqualStrings("1  foo\n\n2  bar\n\n3  baz\n", w.buffered());
}
