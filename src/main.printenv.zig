const std = @import("std");
const stdout = std.io.getStdOut();
var stdout_bw = std.io.bufferedWriter(stdout.writer());

const wayland = @import("wayland");
const wl = wayland.client.wl;

const logFn = @import("log.zig").logFn;

pub const std_options = .{
    .log_level = .info,
    .logFn = logFn,
};

const log = std.log;

// How can I pass null to *anyopaque instead of creating this?
const Junk = struct {};

pub fn main() anyerror!void {
    const display = try wl.Display.connect(null);
    defer display.disconnect();

    const registry = try display.getRegistry();
    defer registry.destroy();

    var junk = Junk{};
    registry.setListener(*Junk, registryListener, &junk);

    // Wait for the server to advertise globals
    if (display.roundtrip() != .SUCCESS) return error.RoundtripFailure;

    try stdout_bw.flush();
}

fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, data: *Junk) void {
    _ = registry;
    _ = data;

    switch (event) {
        .global => |global| {
            stdout_bw.writer().print("Global - name: {d}, interface: {s}, version: {d}\n", .{ global.name, global.interface, global.version }) catch |err| {
                log.err("failed to write to stdout: {any}", .{err});
            };
        },
        else => {},
    }
}
