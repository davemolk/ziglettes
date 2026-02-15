const std = @import("std");
const net = std.net;
const posix = std.posix;
const log = std.log;

pub fn run(alloc: std.mem.Allocator) !void {
    const args = try processArgs(alloc);
    const addr = try net.Address.parseIp4(args.addr, args.port);

    var stream: net.Stream = undefined;
    if (args.udp) {
        log.info("connecting to {f} via udp", .{addr});
        const sockfd = try std.posix.socket(addr.any.family, posix.SOCK.DGRAM, posix.IPPROTO.UDP);
        errdefer net.Stream.close(.{ .handle = sockfd });
        try posix.connect(sockfd, &addr.any, addr.getOsSockLen());
        stream = net.Stream{ .handle = sockfd };
    } else {
        log.info("connecting to {f} via tcp", .{addr});
        stream = net.tcpConnectToAddress(addr) catch |err| {
            if (err == error.ConnectionRefused) {
                log.warn("host is not listening, connection has been refused", .{});
                std.process.exit(1);
            } else return err;
        };
    }
    defer stream.close();

    var read_buf: [1024]u8 = undefined;
    var stdin = std.fs.File.stdin().reader(&read_buf);
    const reader = &stdin.interface;

    try handleConn(alloc, reader, &stream);
}

fn handleConn(alloc: std.mem.Allocator, reader: *std.Io.Reader, stream: *net.Stream) !void {
    var line = std.Io.Writer.Allocating.init(alloc);
    defer line.deinit();

    while (true) {
        std.debug.print("say something:\n", .{});
        _ = reader.streamDelimiter(&line.writer, '\n') catch |err| {
            if (err == error.EndOfStream) break else return err;
        };

        _ = reader.toss(1);

        if (line.written().len > 0) {
            var write_buf: [1024]u8 = undefined;
            var writer = stream.writer(write_buf[0..]);
            const w = &writer.interface;
            try w.writeAll(line.written());
            try w.writeByte('\n');
            try w.flush();
            line.clearRetainingCapacity();
        } else {
            log.info("closing connection", .{});
            try posix.shutdown(stream.handle, posix.ShutdownHow.send);
            break;
        }
    }
}

const Args = struct {
    port: u16 = 80,
    addr: []const u8 = "example.com",
    udp: bool = false,
};

fn processArgs(alloc: std.mem.Allocator) !Args {
    var iter = try std.process.argsWithAllocator(alloc);
    defer iter.deinit();

    _ = iter.skip();

    var args = Args{};

    while (iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "-p") or std.mem.eql(u8, arg, "--port")) {
            const value = iter.next() orelse return error.NoPort;
            const port = try std.fmt.parseUnsigned(u16, value, 10);
            args.port = port;
        } else if (std.mem.eql(u8, arg, "-a") or std.mem.eql(u8, arg, "--address")) {
            const address = iter.next() orelse return error.NoAddress;
            args.addr = address;
        } else if (std.mem.eql(u8, arg, "-u") or std.mem.eql(u8, arg, "--udp")) {
            args.udp = true;
        }
    }

    return args;
}
