const std = @import("std");

pub fn run(alloc: std.mem.Allocator) !void {
    const args = try parseArgs(alloc);

    var r_buf: [1024]u8 = undefined;
    var reader = std.fs.File.stdin().reader(&r_buf);
    const r = &reader.interface;

    var w_buf: [1024]u8 = undefined;
    var writer = std.fs.File.stdout().writer(&w_buf);
    const w = &writer.interface;

    var map: [256]u8 = undefined;

    for (map, 0..) |_, i| {
        map[i] = @intCast(i);
    }

    var delete_map: [256]bool = .{false} ** 256;
    var squeeze_map: [256]bool = .{false} ** 256;
    const opts = Options{ .delete = args.delete, .delete_map = &delete_map, .squeeze_map = &squeeze_map, .squeeze = args.squeeze };

    try constructTrMap(args.src_spec, args.dst_spec, &map, opts);

    try tr(r, w, &map, opts);
}

fn constructTrMap(src_range: []const u8, dst_range: []const u8, map: []u8, opts: Options) !void {
    var src_expanded: [256]u8 = undefined;
    var dst_expanded: [256]u8 = undefined;

    _ = try expandRange(src_range, &src_expanded);

    const dst_len = try expandRange(dst_range, &dst_expanded);
    const last_dst: u8 = if (dst_len > 0) dst_expanded[dst_len - 1] else 0;

    // if both delete and squeeze, delete pulls from src, squeeze from dst
    if (opts.delete and opts.squeeze) {
        for (src_expanded) |s| {
            opts.delete_map[s] = true;
        }

        for (dst_expanded) |d| {
            opts.squeeze_map[d] = true;
        }
        return;
    }

    // handle each case
    for (src_expanded, 0..) |s, i| {
        if (opts.delete) {
            opts.delete_map[s] = true;
        } else if (opts.squeeze) {
            opts.squeeze_map[s] = true;
        } else {
            const d = if (i < dst_len) dst_expanded[i] else last_dst;
            map[s] = d;
        }
    }
}

fn expandRange(spec: []const u8, out: []u8) !usize {
    var out_i: usize = 0;
    var i: usize = 0;

    while (i < spec.len) : (i += 1) {
        const c = spec[i];
        // A-Z
        if (i + 2 < spec.len and spec[i + 1] == '-') {
            const start = c;
            const end = spec[i + 2];

            if (start > end) return error.InvalidRange;

            for (start..end + 1) |b| {
                out[out_i] = @intCast(b);
                out_i += 1;
            }
            i += 2;
        } else {
            out[out_i] = c;
            out_i += 1;
        }
    }

    return out_i;
}

const Options = struct {
    delete: bool = false,
    delete_map: []bool,
    squeeze: bool = false,
    squeeze_map: []bool,
};

const Args = struct {
    delete: bool = false,
    squeeze: bool = false,
    src_spec: []const u8 = "",
    dst_spec: []const u8 = "",
};

fn parseArgs(alloc: std.mem.Allocator) !Args {
    var iter = try std.process.argsWithAllocator(alloc);
    defer iter.deinit();

    _ = iter.skip();

    var opts = Args{};

    while (iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "-d")) {
            opts.delete = true;
        } else if (std.mem.eql(u8, arg, "-s")) {
            opts.squeeze = true;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            return error.UnknownFlag;
        } else if (opts.src_spec.len == 0) {
            opts.src_spec = arg;
        } else if (opts.dst_spec.len == 0) {
            opts.dst_spec = arg;
        } else {
            return error.TooManyArguments;
        }
    }

    return opts;
}

fn tr(reader: *std.Io.Reader, writer: *std.Io.Writer, map: []u8, opts: Options) !void {
    var prev: ?u8 = null;
    while (true) {
        const line = reader.takeDelimiterExclusive('\n') catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        _ = reader.toss(1);

        for (line) |char| {
            if (opts.delete_map[char]) {
                continue;
            }

            const out = map[char];
            if (opts.squeeze and opts.squeeze_map[out]) {
                if (prev != null and prev.? == out) {
                    continue;
                }
            }

            try writer.writeByte(out);
            prev = out;
        }

        const nl: u8 = '\n';
        // not trying to delete newlines
        if (!opts.delete_map[nl]) {
            // not trying to squeeze them either
            if (!(opts.squeeze and opts.squeeze_map[nl] and prev != null and prev.? == nl)) {
                try writer.writeByte(nl);
                prev = nl;
            }
        }

        try writer.flush();
    }
}

test "single substitution" {
    var reader: std.Io.Reader = .fixed("foo\n");
    var buf: [512]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);

    var map: [256]u8 = undefined;
    for (map, 0..) |_, i| {
        map[i] = @intCast(i);
    }

    var delete_map: [256]bool = .{false} ** 256;
    var squeeze_map: [256]bool = .{false} ** 256;
    const opts = Options{
        .delete_map = &delete_map,
        .squeeze_map = &squeeze_map,
    };

    try constructTrMap("o", "O", &map, opts);
    try tr(&reader, &w, &map, opts);
    try std.testing.expectEqualStrings("fOO\n", w.buffered());
}

test "range substitution" {
    var reader: std.Io.Reader = .fixed("Hello World\n");
    var buf: [512]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);

    var map: [256]u8 = undefined;
    for (map, 0..) |_, i| {
        map[i] = @intCast(i);
    }

    var delete_map: [256]bool = .{false} ** 256;
    var squeeze_map: [256]bool = .{false} ** 256;
    const opts = Options{
        .delete_map = &delete_map,
        .squeeze_map = &squeeze_map,
    };

    try constructTrMap("A-Z", "a-z", &map, opts);
    try tr(&reader, &w, &map, opts);
    try std.testing.expectEqualStrings("hello world\n", w.buffered());
}

test "delete single" {
    var reader: std.Io.Reader = .fixed("Hello World\n");
    var buf: [512]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);

    var map: [256]u8 = undefined;
    for (map, 0..) |_, i| {
        map[i] = @intCast(i);
    }

    var delete_map: [256]bool = .{false} ** 256;
    var squeeze_map: [256]bool = .{false} ** 256;
    const opts = Options{
        .delete = true,
        .delete_map = &delete_map,
        .squeeze_map = &squeeze_map,
    };

    try constructTrMap("l", "", &map, opts);
    try tr(&reader, &w, &map, opts);
    try std.testing.expectEqualStrings("Heo Word\n", w.buffered());
}

test "delete multiple" {
    var reader: std.Io.Reader = .fixed("Hello World\n");
    var buf: [512]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);

    var map: [256]u8 = undefined;
    for (map, 0..) |_, i| {
        map[i] = @intCast(i);
    }

    var delete_map: [256]bool = .{false} ** 256;
    var squeeze_map: [256]bool = .{false} ** 256;
    const opts = Options{
        .delete = true,
        .delete_map = &delete_map,
        .squeeze_map = &squeeze_map,
    };

    try constructTrMap("lr", "", &map, opts);
    try tr(&reader, &w, &map, opts);
    try std.testing.expectEqualStrings("Heo Wod\n", w.buffered());
}

test "squeeze single" {
    var reader: std.Io.Reader = .fixed("aaabbbccc\n");
    var buf: [512]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);

    var map: [256]u8 = undefined;
    for (map, 0..) |_, i| {
        map[i] = @intCast(i);
    }

    var delete_map: [256]bool = .{false} ** 256;
    var squeeze_map: [256]bool = .{false} ** 256;
    const opts = Options{
        .delete = false,
        .squeeze = true,
        .delete_map = &delete_map,
        .squeeze_map = &squeeze_map,
    };

    try constructTrMap("ab", "", &map, opts);
    try tr(&reader, &w, &map, opts);
    try std.testing.expectEqualStrings("abccc\n", w.buffered());
}

test "squeeze multiple" {
    var reader: std.Io.Reader = .fixed("aaabbbcccddd\n");
    var buf: [512]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);

    var map: [256]u8 = undefined;
    for (map, 0..) |_, i| {
        map[i] = @intCast(i);
    }

    var delete_map: [256]bool = .{false} ** 256;
    var squeeze_map: [256]bool = .{false} ** 256;
    const opts = Options{
        .delete = false,
        .squeeze = true,
        .delete_map = &delete_map,
        .squeeze_map = &squeeze_map,
    };

    try constructTrMap("bd", "", &map, opts);
    try tr(&reader, &w, &map, opts);
    try std.testing.expectEqualStrings("aaabcccd\n", w.buffered());
}

test "delete and squeeze" {
    var reader: std.Io.Reader = .fixed("aabbaaa\n");
    var buf: [512]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);

    var map: [256]u8 = undefined;
    for (map, 0..) |_, i| {
        map[i] = @intCast(i);
    }

    var delete_map: [256]bool = .{false} ** 256;
    var squeeze_map: [256]bool = .{false} ** 256;
    const opts = Options{
        .delete = true,
        .squeeze = true,
        .delete_map = &delete_map,
        .squeeze_map = &squeeze_map,
    };

    try constructTrMap("a", "b", &map, opts);
    try tr(&reader, &w, &map, opts);
    try std.testing.expectEqualStrings("b\n", w.buffered());
}

test "delete and squeeze multiple" {
    var reader: std.Io.Reader = .fixed("aabbcdddaaa\n");
    var buf: [512]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);

    var map: [256]u8 = undefined;
    for (map, 0..) |_, i| {
        map[i] = @intCast(i);
    }

    var delete_map: [256]bool = .{false} ** 256;
    var squeeze_map: [256]bool = .{false} ** 256;
    const opts = Options{
        .delete = true,
        .squeeze = true,
        .delete_map = &delete_map,
        .squeeze_map = &squeeze_map,
    };

    try constructTrMap("ac", "bd", &map, opts);
    try tr(&reader, &w, &map, opts);
    try std.testing.expectEqualStrings("bd\n", w.buffered());
}
