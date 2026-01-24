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

    while (reader.takeDelimiterInclusive('\n')) |line| {
        const trimmed = std.mem.trimRight(u8, line, "\n");

        if (previous) |prev| {
            if (std.mem.eql(u8, prev, trimmed)) {
                seen_prev_count += 1;
                continue;
            }

            try display(writer, opts, prev, seen_prev_count);
            alloc.free(prev);
        }

        previous = try alloc.dupe(u8, trimmed);
        seen_prev_count = 1;
    } else |err| {
        if (err != error.EndOfStream) return err;
    }

    if (previous) |prev| {
        try display(writer, opts, prev, seen_prev_count);
    }

    try writer.flush();
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
