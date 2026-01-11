const std = @import("std");

const Errors = error{
    InvalidFlagArg,
};

pub fn run(alloc: std.mem.Allocator) !void {
    var args = try parse(alloc);
    defer args.deinit(alloc);

    var write_buf: [1024]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&write_buf);

    if (args.paths.items.len == 0) {
        const file = std.fs.File.stdin();

        const res = try processFile(file);
        try format(&stdout.interface, res, args.options, null);
    }

    const get_totals = if (args.paths.items.len > 1) true else false;
    var total_counts: Counter = .{ .bytes = 0, .words = 0, .lines = 0 };

    for (args.paths.items) |path| {
        const file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
        defer file.close();

        const res = try processFile(file);
        try format(&stdout.interface, res, args.options, path);

        if (get_totals) {
            total_counts.bytes += res.bytes;
            total_counts.lines += res.lines;
            total_counts.words += res.words;
        }
    }

    if (get_totals) {
        try format(&stdout.interface, total_counts, args.options, "total");
    }
}

fn processFile(file: std.fs.File) !Counter {
    var buf: [1024]u8 = undefined;
    var file_reader = file.reader(&buf);
    const reader = &file_reader.interface;

    const c = try count(reader);
    return c;
}

const Args = struct {
    paths: std.ArrayList([]const u8),
    options: Options,

    pub fn deinit(self: *Args, alloc: std.mem.Allocator) void {
        for (self.paths.items) |p| {
            alloc.free(p);
        }

        self.paths.deinit(alloc);
    }
};

const Options = struct {
    bytes: bool,
    words: bool,
    lines: bool,
};

fn parse(alloc: std.mem.Allocator) !Args {
    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();

    // skip executable name
    _ = args.skip();

    var paths: std.ArrayList([]const u8) = .empty;

    var opts = Options{
        .bytes = false,
        .words = false,
        .lines = false,
    };

    var show_all = true;
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-c")) {
            opts.bytes = true;
            show_all = false;
        } else if (std.mem.eql(u8, arg, "-l")) {
            opts.lines = true;
            show_all = false;
        } else if (std.mem.eql(u8, arg, "-w")) {
            opts.words = true;
            show_all = false;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            return Errors.InvalidFlagArg;
        } else {
            const path = try alloc.dupe(u8, arg);
            try paths.append(alloc, path);
        }
    }

    if (show_all) {
        opts.lines = true;
        opts.words = true;
        opts.bytes = true;
    }

    return Args{
        .paths = paths,
        .options = opts,
    };
}

const Counter = struct {
    bytes: u64,
    words: u64,
    lines: u64,
};

fn count(reader: *std.Io.Reader) !Counter {
    var c = Counter{
        .bytes = 0,
        .lines = 0,
        .words = 0,
    };

    var buf: [1024]u8 = undefined;
    var in_word = false;
    while (true) {
        const n = try reader.readSliceShort(&buf);
        if (n == 0) break;

        c.bytes += n;
        for (buf[0..n]) |b| {
            if (b == '\n') c.lines += 1;

            if (std.ascii.isWhitespace(b)) {
                if (in_word) in_word = false;
            } else {
                if (in_word) continue;
                in_word = true;
                c.words += 1;
            }
        }
    }

    return c;
}

// format does a good-enough job, spend time later figuring this out
fn format(writer: *std.Io.Writer, counter: Counter, opts: Options, file_name: ?[]const u8) !void {
    if (opts.lines) {
        try writer.print("{d}", .{counter.lines});
    }

    if (opts.words) {
        try writer.print("\t{d}", .{counter.words});
    }

    if (opts.bytes) {
        try writer.print("\t{d}", .{counter.bytes});
    }

    if (file_name) |file| {
        try writer.print("\t{s}", .{file});
    }

    try writer.print("\n", .{});
    try writer.flush();
}

test count {
    // success
    var r: std.Io.Reader = .fixed("foo\nbarg\nbaz\n");
    const c = try count(&r);
    try std.testing.expectEqual(3, c.lines);
    try std.testing.expectEqual(13, c.bytes);
    try std.testing.expectEqual(3, c.words);

    // handle empty
    r = .fixed("");
    const c_empty = try count(&r);
    try std.testing.expectEqual(0, c_empty.lines);
    try std.testing.expectEqual(0, c_empty.bytes);
    try std.testing.expectEqual(0, c_empty.words);

    // handle multiple words per line
    r = .fixed("foo bar");
    const c_words = try count(&r);
    try std.testing.expectEqual(0, c_words.lines);
    try std.testing.expectEqual(7, c_words.bytes);
    try std.testing.expectEqual(2, c_words.words);

    // handle whitespace
    r = .fixed("foo  \n  barg\nbaz \n");
    const c_whitespace = try count(&r);
    try std.testing.expectEqual(3, c_whitespace.lines);
    try std.testing.expectEqual(18, c_whitespace.bytes);
    try std.testing.expectEqual(3, c_whitespace.words);
}
