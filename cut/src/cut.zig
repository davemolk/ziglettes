const std = @import("std");

pub fn run(alloc: std.mem.Allocator) !void {
    var args = try parseArgs(alloc);
    defer args.deinit(alloc);

    var file: std.fs.File = undefined;
    if (args.file) |f| {
        file = try std.fs.cwd().openFile(f, .{});
    } else {
        file = std.fs.File.stdin();
    }
    defer file.close();

    var r_buf: [1024]u8 = undefined;
    var reader = file.reader(&r_buf);
    const r = &reader.interface;

    var w_buf: [1024]u8 = undefined;
    var writer = std.fs.File.stdout().writer(&w_buf);
    const w = &writer.interface;

    try processFile(alloc, r, w, args.fields, args.delim);
}

const Args = struct {
    fields: std.ArrayList(u8),
    file: ?[]const u8,
    delim: u8,

    pub fn deinit(self: *Args, alloc: std.mem.Allocator) void {
        self.fields.deinit(alloc);
    }
};

const ArgErrors = error{
    MissingField,
    MissingDelim,
    InvalidDelim,
};

fn parseArgs(alloc: std.mem.Allocator) !Args {
    var iter = try std.process.argsWithAllocator(alloc);
    defer iter.deinit();

    _ = iter.skip();

    var fields: std.ArrayList(u8) = .empty;
    var file: ?[]const u8 = null;
    var delim: u8 = '\t';

    while (iter.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "-f")) {
            if (arg.len > 2) {
                // -f1,2
                if (std.mem.containsAtLeastScalar(u8, arg[2..], 1, ',')) {
                    var it = std.mem.splitScalar(u8, arg[2..], ',');
                    while (it.next()) |f| {
                        const field = try std.fmt.parseInt(u8, f, 10);
                        try fields.append(alloc, field);
                    }
                } else {
                    // -f"1 2"
                    var it = std.mem.splitScalar(u8, arg[2..], ' ');
                    while (it.next()) |f| {
                        const field = try std.fmt.parseInt(u8, f, 10);
                        try fields.append(alloc, field);
                    }
                }
            } else {
                // -f 1
                const next = iter.next() orelse return error.MissingField;
                const field = try std.fmt.parseInt(u8, next, 10);
                try fields.append(alloc, field);
            }
        } else if (std.mem.startsWith(u8, arg, "-d")) {
            if (arg.len > 2) {
                if (arg.len != 3) return error.InvalidDelim;
                delim = arg[2];
            } else {
                const next = iter.next() orelse return error.MissingDelim;
                if (next.len != 1) return error.InvalidDelim;
                delim = next[0];
            }
        } else if (std.mem.eql(u8, arg, "-")) {
            // use stdin, so keep file as null
            continue;
        } else {
            file = arg;
        }
    }

    return .{
        .fields = fields,
        .file = file,
        .delim = delim,
    };
}

fn processFile(alloc: std.mem.Allocator, reader: *std.Io.Reader, writer: *std.Io.Writer, fields: std.ArrayList(u8), delim: u8) !void {
    var line = std.Io.Writer.Allocating.init(alloc);
    defer line.deinit();

    while (true) {
        _ = reader.streamDelimiter(&line.writer, '\n') catch |err| {
            if (err == error.EndOfStream) break else return err;
        };

        _ = reader.toss(1);
        try processLine(writer, line.written(), fields, delim);
        line.clearRetainingCapacity();
    }

    if (line.written().len > 0) {
        try processLine(writer, line.written(), fields, delim);
    }

    try writer.flush();
}

fn processLine(writer: *std.Io.Writer, data: []const u8, fields: std.ArrayList(u8), delim: u8) !void {
    var i: u8 = 1;
    var iter = std.mem.splitScalar(u8, data, delim);

    const multiple = fields.items.len > 1;
    while (iter.next()) |chunk| {
        var fields_remaining = fields.items.len;
        for (fields.items) |field| {
            fields_remaining -= 1;
            if (i == field) {
                try writer.writeAll(chunk);

                if (multiple and fields_remaining > 0) {
                    try writer.writeByte('\t');
                }
            }
        }

        i += 1;
    }

    try writer.writeByte('\n');
}

test "single field" {
    const alloc = std.testing.allocator;
    var reader: std.Io.Reader = .fixed("f0\tf1\tf2\tf3\tf4\n0\t1\t2\t3\t4\n5\t6\t7\t8\t9\n");

    var buf: [512]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);

    var fields = std.ArrayList(u8).empty;
    defer fields.deinit(alloc);

    try fields.append(alloc, 2);
    const delim: u8 = '\t';

    try processFile(alloc, &reader, &w, fields, delim);
    try std.testing.expectEqualStrings("f1\n1\n6\n", w.buffered());
}

test "single field, no newline" {
    const alloc = std.testing.allocator;
    var reader: std.Io.Reader = .fixed("f0\tf1\tf2\tf3\tf4\n0\t1\t2\t3\t4\n5\t6\t7\t8\t9");

    var buf: [512]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);

    var fields = std.ArrayList(u8).empty;
    defer fields.deinit(alloc);

    try fields.append(alloc, 2);
    const delim: u8 = '\t';

    try processFile(alloc, &reader, &w, fields, delim);
    try std.testing.expectEqualStrings("f1\n1\n6\n", w.buffered());
}

test "multiple fields" {
    const alloc = std.testing.allocator;
    var reader: std.Io.Reader = .fixed("f0\tf1\tf2\tf3\tf4\n0\t1\t2\t3\t4\n5\t6\t7\t8\t9\n");

    var buf: [512]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);

    var fields = std.ArrayList(u8).empty;
    defer fields.deinit(alloc);

    try fields.append(alloc, 1);
    try fields.append(alloc, 2);
    const delim: u8 = '\t';

    try processFile(alloc, &reader, &w, fields, delim);
    try std.testing.expectEqualStrings("f0\tf1\n0\t1\n5\t6\n", w.buffered());
}

test "multiple fields no newline" {
    const alloc = std.testing.allocator;
    var reader: std.Io.Reader = .fixed("f0\tf1\tf2\tf3\tf4\n0\t1\t2\t3\t4\n5\t6\t7\t8\t9");

    var buf: [512]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);

    var fields = std.ArrayList(u8).empty;
    defer fields.deinit(alloc);

    try fields.append(alloc, 1);
    try fields.append(alloc, 2);
    const delim: u8 = '\t';

    try processFile(alloc, &reader, &w, fields, delim);
    try std.testing.expectEqualStrings("f0\tf1\n0\t1\n5\t6\n", w.buffered());
}

test "custom delim" {
    const alloc = std.testing.allocator;
    const lines =
        \\"Adore You",Harry Styles,2019,vi−I−IV−V,C minor
        \\"Africa",Toto,1982,vi−IV–I–V (chorus),F♯ minor (chorus)
        \\"Aicha",Cheb Khaled,1996,vi–IV–I–V,G minor
        \\
    ;
    var reader: std.Io.Reader = .fixed(lines);

    var buf: [512]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);

    var fields = std.ArrayList(u8).empty;
    defer fields.deinit(alloc);

    try fields.append(alloc, 1);
    const delim: u8 = ',';

    try processFile(alloc, &reader, &w, fields, delim);
    const expect =
        \\"Adore You"
        \\"Africa"
        \\"Aicha"
        \\
    ;

    try std.testing.expectEqualStrings(expect, w.buffered());
}

test "custom delim no newline" {
    const alloc = std.testing.allocator;
    const lines =
        \\"Adore You",Harry Styles,2019,vi−I−IV−V,C minor
        \\"Africa",Toto,1982,vi−IV–I–V (chorus),F♯ minor (chorus)
        \\"Aicha",Cheb Khaled,1996,vi–IV–I–V,G minor
    ;
    var reader: std.Io.Reader = .fixed(lines);

    var buf: [512]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);

    var fields = std.ArrayList(u8).empty;
    defer fields.deinit(alloc);

    try fields.append(alloc, 1);
    const delim: u8 = ',';

    try processFile(alloc, &reader, &w, fields, delim);
    const expect =
        \\"Adore You"
        \\"Africa"
        \\"Aicha"
        \\
    ;

    try std.testing.expectEqualStrings(expect, w.buffered());
}
