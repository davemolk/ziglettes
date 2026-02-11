const std = @import("std");
const log = std.log;

pub fn run(alloc: std.mem.Allocator) !void {
    const args = parseArgs(alloc) catch |err| {
        if (err == error.ShowUsage) {
            std.process.exit(0);
        } else return err;
    };

    if (args.help) {
        printUsage();
        std.process.exit(0);
    }

    if (args.verbose) {
        if (args.dry) {
            log.info("dry run", .{});
        }
        log.info("starting path: {s}\ntarget: {s}", .{ args.path, args.target });
    }

    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();

    const a = arena.allocator();

    if (args.crawl) {
        return try crawl(a, args.path, args.target, args.verbose, args.dry);
    }

    try non_crawl(a, args.path, args.target, args.verbose, args.dry);
}

const entity = struct { path: []const u8, type: std.fs.Dir.Entry.Kind };

// crawl uses an arena allocator
fn crawl(alloc: std.mem.Allocator, path: []const u8, target: []const u8, verbose: bool, dry: bool) !void {
    var dir = try std.fs.cwd().openDir(path, .{ .access_sub_paths = true, .iterate = true });
    defer dir.close();

    var walker = try dir.walk(alloc);
    defer walker.deinit();

    // arena allocator will free all the paths we store here
    var list = std.ArrayList(entity).empty;
    defer list.deinit(alloc);

    while (try walker.next()) |entry| {
        if (std.mem.eql(u8, entry.basename, target)) {
            if (dry or verbose) {
                log.info("deleting {s}", .{entry.path});
            }

            if (!dry) {
                const obj_path = try std.fs.path.join(alloc, &[_][]const u8{ path, entry.path });
                try list.append(alloc, .{
                    .path = obj_path,
                    .type = entry.kind,
                });
            }
        }
    }

    for (list.items) |obj| {
        switch (obj.type) {
            .file => try std.fs.cwd().deleteFile(obj.path),
            .directory => try std.fs.cwd().deleteTree(obj.path),
            else => {},
        }
    }
}

fn non_crawl(alloc: std.mem.Allocator, path: []const u8, target: []const u8, verbose: bool, dry: bool) !void {
    var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
    defer dir.close();

    var list = std.ArrayList(entity).empty;
    defer list.deinit(alloc);

    var entries = dir.iterate();
    while (try entries.next()) |entry| {
        if (std.mem.eql(u8, entry.name, target)) {
            if (dry or verbose) {
                log.info("deleting {s}", .{entry.name});
            }

            if (!dry) {
                const p = try std.fs.path.join(alloc, &[_][]const u8{ path, entry.name });
                try list.append(alloc, .{
                    .path = p,
                    .type = entry.kind,
                });
            }
        }
    }

    for (list.items) |obj| {
        switch (obj.type) {
            .file => try std.fs.cwd().deleteFile(obj.path),
            .directory => try std.fs.cwd().deleteTree(obj.path),
            else => {},
        }
    }
}

fn printUsage() void {
    const usage =
        \\usage: cz [OPTIONS]
        \\
        \\Clean up files
        \\
        \\OPTIONS:
        \\  -d, --dry       dry run of program
        \\  -v, --verbose   verbose output
        \\  -t, --target    target for deletion (default: .zig-cache)
        \\  -p, --path      root directory to start from (default: .)
        \\  -c, --crawl     crawl recursively
        \\  -h, --help      show this help
        \\
        \\EXAMPLES:
        \\  cz                       clean current directory
        \\  cz -d -p ~/projects      dry run in ~/projects
        \\  cz -t junk               clean current directory of junk
    ;
    std.log.info("{s}\n", .{usage});
}

const Args = struct {
    path: []const u8 = ".",
    target: []const u8 = ".zig-cache",
    dry: bool = false,
    verbose: bool = false,
    help: bool = false,
    crawl: bool = false,
};

fn parseArgs(alloc: std.mem.Allocator) !Args {
    var iter = try std.process.argsWithAllocator(alloc);
    defer iter.deinit();

    _ = iter.skip();

    var args = Args{};
    var help_needed = false;
    while (iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "-d") or (std.mem.eql(u8, arg, "--dry"))) {
            args.dry = true;
        } else if (std.mem.eql(u8, arg, "-v") or (std.mem.eql(u8, arg, "--verbose"))) {
            args.verbose = true;
        } else if (std.mem.eql(u8, arg, "-t") or (std.mem.eql(u8, arg, "--target"))) {
            const target = iter.next() orelse return error.MissingTarget;
            args.target = target;
        } else if (std.mem.eql(u8, arg, "-h") or (std.mem.eql(u8, arg, "--help"))) {
            help_needed = true;
            break;
        } else if (std.mem.eql(u8, arg, "-c") or (std.mem.eql(u8, arg, "--crawl"))) {
            args.crawl = true;
        } else if (std.mem.eql(u8, arg, "-p") or std.mem.eql(u8, arg, "--path")) {
            const path = iter.next() orelse return error.MissingPath;
            args.path = path;
        }
    }

    return args;
}
