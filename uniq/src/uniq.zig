const std = @import("std");

const ArgsError = error{
    MissingInput,
};

pub fn run(alloc: std.mem.Allocator) !void {
    var args = try parseArgs(alloc);
    defer args.deinit(alloc);

    var in_file: std.fs.File = undefined;
    if (args.stdin) {
        in_file = std.fs.File.stdin();
    } else if (args.paths.items.len > 0) {
        const path = args.paths.items[0];
        in_file = try std.fs.cwd().openFile(path, .{});
    } else {
        return ArgsError.MissingInput;
    }

    var out_file: std.fs.File = undefined;
    if (!args.stdin and args.paths.items.len == 2) {
        const path = args.paths.items[1];
        out_file = try std.fs.cwd().createFile(path, .{ .read = true });
    } else if (args.stdin and args.paths.items.len == 1) {
        const path = args.paths.items[0];
        out_file = try std.fs.cwd().createFile(path, .{ .read = true });
    } else {
        out_file = std.fs.File.stdout();
    }

    defer out_file.close();

    var buf: [1024]u8 = undefined;
    var reader = in_file.reader(&buf);
    const r = &reader.interface;

    var w_buf: [1024]u8 = undefined;
    var writer = out_file.writer(&w_buf);
    const w = &writer.interface;

    const opts = processOptions{ .display_count = args.count, .only_repeats = args.repeated, .only_uniques = args.uniques };

    try processFile(alloc, r, w, opts);
}

const Args = struct {
    paths: std.ArrayList([]const u8),
    stdin: bool,
    count: bool,
    repeated: bool,
    uniques: bool,

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
        .paths = std.ArrayList([]const u8){},
        .stdin = false,
        .count = false,
        .repeated = false,
        .uniques = false,
    };

    while (iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "-c")) {
            args.count = true;
        } else if (std.mem.eql(u8, arg, "-d")) {
            args.repeated = true;
        } else if (std.mem.eql(u8, arg, "-u")) {
            args.uniques = true;
        } else if (std.mem.eql(u8, arg, "-")) {
            args.stdin = true;
        } else {
            const path = try alloc.dupe(u8, arg);
            try args.paths.append(alloc, path);
        }
    }

    return args;
}

const processOptions = struct { display_count: bool, only_repeats: bool, only_uniques: bool };

fn processFile(alloc: std.mem.Allocator, reader: *std.Io.Reader, writer: *std.Io.Writer, opts: processOptions) !void {
    var previous: ?[]u8 = null;
    var seen_prev_count: usize = 0;

    defer {
        if (previous) |prev| alloc.free(prev);
    }

    while (true) {
        const line = reader.takeDelimiterExclusive('\n') catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };

        const buffered = reader.buffered();
        if (buffered.len > 0 and buffered[0] == '\n') {
            _ = reader.toss(1);
        }

        try processLine(alloc, writer, opts, &previous, &seen_prev_count, line);
    }

    const remainder = reader.buffered();
    if (remainder.len > 0) {
        try processLine(alloc, writer, opts, &previous, &seen_prev_count, remainder);
    }

    if (previous) |prev| {
        try display(writer, opts, prev, seen_prev_count);
    }

    try writer.flush();
}

fn processLine(alloc: std.mem.Allocator, writer: *std.Io.Writer, opts: processOptions, previous: *?[]u8, count: *usize, raw: []const u8) !void {
    if (previous.*) |prev| {
        if (std.mem.eql(u8, prev, raw)) {
            count.* += 1;
            return;
        }

        try display(writer, opts, prev, count.*);
        alloc.free(prev);
    }

    previous.* = try alloc.dupe(u8, raw);
    count.* = 1;
}

fn display(writer: *std.Io.Writer, opts: processOptions, prev: []u8, count: usize) !void {
    const should_print =
        (!opts.only_repeats and !opts.only_uniques) or
        (opts.only_repeats and count > 1) or
        (opts.only_uniques and count == 1);

    if (!should_print) return;

    if (opts.display_count) {
        try writer.print("{d} {s}\n", .{ count, prev });
    } else {
        try writer.print("{s}\n", .{prev});
    }
}

test "file with newline ending" {
    const alloc = std.testing.allocator;
    var reader: std.Io.Reader = .fixed("line1\nline2\nline2\nline3\nline4\n");
    var buf: [512]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);

    try processFile(alloc, &reader, &w, .{
        .display_count = false,
        .only_repeats = false,
        .only_uniques = false,
    });

    try std.testing.expectEqualStrings("line1\nline2\nline3\nline4\n", w.buffered());
}

test "file without newline ending" {
    const alloc = std.testing.allocator;
    var reader: std.Io.Reader = .fixed("line1\nline2\nline2\nline3\nline4\nline4");
    var buf: [512]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);

    try processFile(alloc, &reader, &w, .{
        .display_count = false,
        .only_repeats = false,
        .only_uniques = false,
    });

    try std.testing.expectEqualStrings("line1\nline2\nline3\nline4\n", w.buffered());
}

test "display count" {
    const alloc = std.testing.allocator;
    var reader: std.Io.Reader = .fixed("line1\nline2\nline2\nline3\nline4\nline4\n");
    var buf: [512]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);

    try processFile(alloc, &reader, &w, .{
        .display_count = true,
        .only_repeats = false,
        .only_uniques = false,
    });

    try std.testing.expectEqualStrings("1 line1\n2 line2\n1 line3\n2 line4\n", w.buffered());
}

test "display count w/out newline" {
    const alloc = std.testing.allocator;
    var reader: std.Io.Reader = .fixed("line1\nline2\nline2\nline3\nline4\nline4");
    var buf: [512]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);

    try processFile(alloc, &reader, &w, .{
        .display_count = true,
        .only_repeats = false,
        .only_uniques = false,
    });

    try std.testing.expectEqualStrings("1 line1\n2 line2\n1 line3\n2 line4\n", w.buffered());
}

test "only repeated" {
    const alloc = std.testing.allocator;
    var reader: std.Io.Reader = .fixed("line1\nline2\nline2\nline3\nline4\nline4\n");
    var buf: [512]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);

    try processFile(alloc, &reader, &w, .{
        .display_count = false,
        .only_repeats = true,
        .only_uniques = false,
    });

    try std.testing.expectEqualStrings("line2\nline4\n", w.buffered());
}

test "only repeated without newline" {
    const alloc = std.testing.allocator;
    var reader: std.Io.Reader = .fixed("line1\nline2\nline2\nline3\nline4\nline4");
    var buf: [512]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);

    try processFile(alloc, &reader, &w, .{
        .display_count = false,
        .only_repeats = true,
        .only_uniques = false,
    });

    try std.testing.expectEqualStrings("line2\nline4\n", w.buffered());
}

test "uniques" {
    const alloc = std.testing.allocator;
    var reader: std.Io.Reader = .fixed("line1\nline2\nline2\nline3\nline4\nline4\n");
    var buf: [512]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);

    try processFile(alloc, &reader, &w, .{
        .display_count = false,
        .only_repeats = false,
        .only_uniques = true,
    });

    try std.testing.expectEqualStrings("line1\nline3\n", w.buffered());
}

test "uniques without newline" {
    const alloc = std.testing.allocator;
    var reader: std.Io.Reader = .fixed("line1\nline2\nline2\nline3\nline4\nline4");
    var buf: [512]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);

    try processFile(alloc, &reader, &w, .{
        .display_count = false,
        .only_repeats = false,
        .only_uniques = true,
    });

    try std.testing.expectEqualStrings("line1\nline3\n", w.buffered());
}

test "duplicates with count" {
    const alloc = std.testing.allocator;
    var reader: std.Io.Reader = .fixed("line1\nline2\nline2\nline3\nline4\nline4\n");
    var buf: [512]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);

    try processFile(alloc, &reader, &w, .{
        .display_count = true,
        .only_repeats = true,
        .only_uniques = false,
    });

    try std.testing.expectEqualStrings("2 line2\n2 line4\n", w.buffered());
}

test "duplicates with count, no newline" {
    const alloc = std.testing.allocator;
    var reader: std.Io.Reader = .fixed("line1\nline2\nline2\nline3\nline4\nline4");
    var buf: [512]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);

    try processFile(alloc, &reader, &w, .{
        .display_count = true,
        .only_repeats = true,
        .only_uniques = false,
    });

    try std.testing.expectEqualStrings("2 line2\n2 line4\n", w.buffered());
}
