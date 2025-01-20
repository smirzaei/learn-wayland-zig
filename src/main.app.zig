const std = @import("std");
const logFn = @import("log.zig").logFn;

pub const std_options = .{
    .log_level = .info,
    .logFn = logFn,
};

const log = std.log;
const mem = std.mem;
const posix = std.posix;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const zxdg = wayland.client.zxdg;

const AppState = struct {
    shm: ?*wl.Shm,
    compositor: ?*wl.Compositor,
    xdgWMBase: ?*xdg.WmBase,
    decorationManager: ?*zxdg.DecorationManagerV1,

    surface: ?*wl.Surface,
};

pub fn main() anyerror!void {
    log.info("starting the application", .{});
    const display = try wl.Display.connect(null);
    const registry = try display.getRegistry();

    var state = AppState{
        .compositor = null,
        .shm = null,
        .xdgWMBase = null,
        .surface = null,
        .decorationManager = null,
    };

    registry.setListener(*AppState, registryListener, &state);

    // Wait for the server to advertise globals
    if (display.roundtrip() != .SUCCESS) return error.RoundtripFailure;
    const compositor = state.compositor orelse return error.NoCompositor;
    const xdg_wm_base = state.xdgWMBase orelse return error.NoXdgWmBase;
    const decoration_manager = state.decorationManager orelse return error.NoDecorationManager;
    xdg_wm_base.setListener(*AppState, xdgWmBaseListener, &state); // TODO: find a way to pass void or null

    const surface = try compositor.createSurface();
    state.surface = surface;

    const xdg_surface = try xdg.WmBase.getXdgSurface(xdg_wm_base, surface);
    xdg_surface.setListener(*AppState, xdgSurfaceListener, &state);

    const top_level = try xdg_surface.getToplevel();
    top_level.setTitle("Hello, world!");

    const decoration = try decoration_manager.getToplevelDecoration(top_level);
    decoration.setMode(.server_side);

    surface.commit();

    log.info("waiting at the event loop\n", .{});

    while (true) {
        log.info("loop\n", .{});
        _ = display.dispatch();
    }
}

fn xdgWmBaseListener(wm_base: *xdg.WmBase, event: xdg.WmBase.Event, data: *AppState) void {
    _ = data;
    switch (event) {
        .ping => |ping| {
            log.info("ping {any}\n", .{ping});
            wm_base.pong(ping.serial);
        },
    }
}

fn xdgSurfaceListener(xdg_surface: *xdg.Surface, event: xdg.Surface.Event, state: *AppState) void {
    switch (event) {
        .configure => |configure| {
            log.info("received xdg surface configure event {any}", .{configure});
            xdg_surface.ackConfigure(configure.serial);
            const buffer = drawFrame(state) catch unreachable;
            defer buffer.destroy();

            const surface = state.surface orelse unreachable;
            surface.attach(buffer, 0, 0);
            surface.commit();
        },
    }
}

fn drawFrame(state: *AppState) anyerror!*wl.Buffer {
    const height = 480;
    const width = 640;
    const stride = width * 4;
    const size = stride * height;

    const fd = try posix.memfd_create("/tmp/hello-zig", 0);
    defer posix.close(fd);

    try posix.ftruncate(fd, size);

    const data = try posix.mmap(null, size, posix.PROT.READ | posix.PROT.WRITE, .{ .TYPE = .SHARED }, fd, 0);
    for (0..height) |y| {
        for (0..width) |x| {
            const offset = (y * width + x) * 4;

            // little endian
            data[offset] = 0x00; // Blue
            data[offset + 1] = 0xFF; // Green
            data[offset + 2] = 0x00; // Red
            data[offset + 3] = 0xFF; // ??
        }
    }

    const shm = state.shm orelse return error.NoShm;
    const pool = try shm.createPool(fd, size);
    defer pool.destroy();

    const buffer = try pool.createBuffer(0, width, height, stride, .xrgb8888);

    defer posix.munmap(data);

    buffer.setListener(*AppState, bufferListener, state);
    return buffer;
}

fn bufferListener(buffer: *wl.Buffer, event: wl.Buffer.Event, state: *AppState) void {
    _ = buffer;
    _ = event;
    _ = state;
}

fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, ctx: *AppState) void {
    switch (event) {
        .global => |global| {
            // std.debug.print("interface: '{s}', version: {d}, name {d}\n", .{ global.interface, global.version, global.name });
            // if (mem.startsWith(u8, mem.span(event.global.interface), "wl")) {
            //     std.debug.print("interface: '{s}', version: {d}, name {d}\n", .{ global.interface, global.version, global.name });
            //     std.debug.print("interface: '{s}', version: {d}, name {d}\n", .{ global.interface, global.version, global.name });
            // }

            // TODO: don't use the version advertised by the server.
            // find the minimum version you want to support and set that.
            if (mem.orderZ(u8, global.interface, wl.Compositor.getInterface().name) == .eq) {
                ctx.compositor = registry.bind(global.name, wl.Compositor, global.version) catch return;
            } else if (mem.orderZ(u8, global.interface, wl.Shm.getInterface().name) == .eq) {
                ctx.shm = registry.bind(global.name, wl.Shm, global.version) catch return;
            } else if (mem.orderZ(u8, global.interface, xdg.WmBase.getInterface().name) == .eq) {
                ctx.xdgWMBase = registry.bind(global.name, xdg.WmBase, global.version) catch return;
            } else if (mem.orderZ(u8, global.interface, zxdg.DecorationManagerV1.getInterface().name) == .eq) {
                ctx.decorationManager = registry.bind(global.name, zxdg.DecorationManagerV1, 1) catch return;
            }
        },
        .global_remove => |id| {
            std.debug.print("global remove event {d}\n", id);
        },
    }
}
