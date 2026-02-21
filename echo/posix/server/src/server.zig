const std = @import("std");
const net = std.net;
const posix = std.posix;
const log = std.log;

pub fn run(alloc: std.mem.Allocator) !void {
    const args = try processArgs(alloc);
    const addr = try net.Address.parseIp(args.addr, args.port);

    if (args.udp) {
        try runUDPServer(addr);
    } else {
        try runTCPServer(addr, args.conns);
    }
}

fn runUDPServer(addr: net.Address) !void {
    log.info("connecting to {f} via udp", .{addr});

    const sockfd = try std.posix.socket(addr.any.family, posix.SOCK.DGRAM, posix.IPPROTO.UDP);
    defer posix.close(sockfd);

    try posix.bind(sockfd, &addr.any, addr.getOsSockLen());

    var buf: [1024]u8 = undefined;
    while (true) {
        var client_addr: posix.sockaddr = undefined;
        var addr_len: posix.socklen_t = @sizeOf(posix.sockaddr);

        const n = try posix.recvfrom(sockfd, &buf, 0, &client_addr, &addr_len);
        _ = try posix.sendto(sockfd, buf[0..n], 0, &client_addr, addr_len);
    }
}

fn runTCPServer(addr: net.Address, conns: u31) !void {
    log.info("connecting to {f} via tcp", .{addr});

    const sockfd = try posix.socket(addr.any.family, posix.SOCK.STREAM, posix.IPPROTO.TCP);
    defer posix.close(sockfd);

    try posix.setsockopt(sockfd, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
    try posix.bind(sockfd, &addr.any, addr.getOsSockLen());

    try posix.listen(sockfd, conns);

    while (true) {
        var client_addr: net.Address = undefined;
        var addr_len: posix.socklen_t = @sizeOf(net.Address);

        const socket = try posix.accept(sockfd, &client_addr.any, &addr_len, posix.SOCK.CLOEXEC);
        errdefer posix.close(socket);

        const thread = try std.Thread.spawn(.{}, handleTCP, .{ socket, client_addr });
        thread.detach();
    }
}

fn handleTCP(socket: posix.socket_t, addr: net.Address) !void {
    defer posix.close(socket);

    log.info("{f} connected", .{addr});

    var read_buf: [1024]u8 = undefined;
    while (true) {
        const n = try posix.read(socket, &read_buf);
        if (n == 0) break;

        try writeAll(socket, read_buf[0..n]);
    }
}

fn writeAll(socket: posix.socket_t, buf: []const u8) !void {
    var total: usize = 0;
    while (total < buf.len) {
        const written = try posix.write(socket, buf[total..]);
        if (written == 0) break;
        total += written;
    }
}

const Args = struct {
    port: u16 = 0,
    addr: []const u8 = "",
    udp: bool = false,
    conns: u8 = 5, // posix.listen takes u31
};

fn processArgs(alloc: std.mem.Allocator) !Args {
    var iter = try std.process.argsWithAllocator(alloc);
    defer iter.deinit();

    _ = iter.skip();

    var args = Args{};

    while (iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "-u") or std.mem.eql(u8, arg, "--udp")) {
            args.udp = true;
        } else if (std.mem.eql(u8, arg, "-c") or std.mem.eql(u8, arg, "--conn")) {
            const conns = try std.fmt.parseUnsigned(u8, arg, 10);
            if (conns > 128) return error.TooManyConnectionsArg;
            args.conns = conns;
        } else if (args.addr.len == 0) {
            args.addr = arg;
        } else if (args.port == 0) {
            const port = try std.fmt.parseUnsigned(u16, arg, 10);
            args.port = port;
        } else {
            return error.TooManyArgs;
        }
    }

    if (args.addr.len == 0) return error.MissingAddress;
    if (args.port == 0) return error.MissingPort;

    return args;
}
