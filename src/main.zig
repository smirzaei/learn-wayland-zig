const std = @import("std");
const mem = std.mem;
const logFn = @import("log.zig").logFn;
const printEntrypoint = @import("main.printenv.zig").main;
const appEntrypoint = @import("main.app.zig").main;

pub const std_options = .{
    .log_level = .info,
    .logFn = logFn,
};

const log = std.log;

pub const Entrypoint = enum { main, print };

pub fn main() !void {
    const entrypoint = try getEntrypoint();
    switch (entrypoint) {
        .main => {
            return appEntrypoint();
        },
        .print => {
            return printEntrypoint();
        },
    }
}

fn getEntrypoint() !Entrypoint {
    // parse the entry point based on cli args

    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        return Entrypoint.main;
    }

    return std.meta.stringToEnum(Entrypoint, args[1]) orelse error.InvalidEntrypoint;
}
