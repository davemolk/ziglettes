const std = @import("std");

pub fn run(alloc: std.mem.Allocator) !void {
    var args = try processArgs(alloc);
    defer args.deinit(alloc);

    const display_bytes = if (args.byte_count != 0) true else false;
    const multiple = if (args.files.items.len > 0) true else false;

    var write_buf: [1024]u8 = undefined;
    var writer = std.fs.File.stdout().writer(&write_buf);
    const w = &writer.interface;
    if (args.files.items.len > 0) {
        for (args.files.items) |path| {
            var file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
            defer file.close();

            if (multiple) {
                const base_name = std.fs.path.basename(path);
                try w.print("==> {s} <==\n", .{base_name});
                try w.flush();
            }
            if (display_bytes) {
                try processBytes(file, w, args.byte_count);
            } else {
                try processLines(file, w, args.line_count);
            }
        }
    } else {
        const stdin = std.fs.File.stdin();

        if (display_bytes) {
            try processBytes(stdin, w, args.byte_count);
        } else {
            try processLines(stdin, w, args.line_count);
        }
    }
}

const ArgParseError = error{ MissingArgs, UnknownFlag, InvalidArgs };

const Args = struct {
    files: std.ArrayList([]const u8),
    line_count: u32,
    byte_count: u32,

    pub fn deinit(self: *Args, alloc: std.mem.Allocator) void {
        for (self.files.items) |item| {
            alloc.free(item);
        }

        self.files.deinit(alloc);
    }
};

fn processArgs(alloc: std.mem.Allocator) !Args {
    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();

    _ = args.next();

    var line_count: u32 = 10;
    var byte_count: u32 = 0;
    var files: std.ArrayList([]const u8) = .empty;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-n")) {
            const value = args.next() orelse return error.MissingArgs;
            line_count = try std.fmt.parseInt(u32, value, 10);
        } else if (std.mem.eql(u8, arg, "-c")) {
            const value = args.next() orelse return error.MissingArgs;
            byte_count = try std.fmt.parseInt(u32, value, 10);
        } else if (std.mem.startsWith(u8, arg, "-")) {
            return error.UnknownFlag;
        } else {
            const duped = try alloc.dupe(u8, arg);
            try files.append(alloc, duped);
        }
    }

    return Args{
        .files = files,
        .line_count = line_count,
        .byte_count = byte_count,
    };
}

fn processLines(file: std.fs.File, writer: *std.Io.Writer, lines_to_read: u32) !void {
    var read_buf: [1024]u8 = undefined;
    var reader = file.reader(&read_buf);
    const r = &reader.interface;

    var lines: usize = 0;
    while (lines < lines_to_read) : (lines += 1) {
        const line = r.takeDelimiterExclusive('\n') catch |err| {
            if (err == error.EndOfStream) {
                try writer.writeByte('\n');
                try writer.flush();
                break;
            } else return err;
        };

        r.toss(1);
        try writer.writeAll(line);
        try writer.writeByte('\n');
        try writer.flush();
    }
}

fn processBytes(file: std.fs.File, writer: *std.Io.Writer, bytes_to_read: u32) !void {
    var reader_buf: [1024]u8 = undefined;
    var reader = file.reader(&reader_buf);
    const r = &reader.interface;

    defer writer.flush() catch {};

    var buf: [1024]u8 = undefined;
    var remaining = bytes_to_read;
    while (remaining > 0) {
        const len: usize = @intCast(@min(remaining, buf.len));
        const n = r.readSliceShort(buf[0..len]) catch |err| {
            if (err == error.EndOfStream) break else return err;
        };

        if (n == 0) break;

        try writer.writeAll(buf[0..n]);
        remaining -= @intCast(n);
    }
}

// fn processLines(file: std.fs.File, lines_to_read: u32) !void {
//     var buf: [1024]u8 = undefined;
//     const stdout = std.fs.File.stdout();
//     var remaining: usize = lines_to_read;

//     while (remaining > 0) {
//         const n = try file.read(&buf);
//         if (n == 0) break;

//         var i: usize = 0;
//         while (i < n) : (i += 1) {
//             if (buf[i] == '\n') {}
//         }
//         for (buf[0..n]) |b| {
//             if (b == '\n') {
//                 if (remaining == 0) break;
//                 remaining -= 1;
//             }
//         }
//         try stdout.writeAll(buf[0..n]);
//     }
// }

// fn processBytes(file: std.fs.File, bytes_to_read: u32) !void {
//     var buf: [1024]u8 = undefined;

//     const stdout = std.fs.File.stdout();

//     var remaining: usize = bytes_to_read;

//     while (remaining > 0) {
//         const to_read = @min(buf.len, remaining);
//         const n = try file.read(buf[0..to_read]);

//         if (n == 0) break;

//         try stdout.writeAll(buf[0..n]);
//         remaining -= n;
//     }
// }
