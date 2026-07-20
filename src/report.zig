const std = @import("std");
const Io = std.Io;

pub const Ctx = struct {
    io: Io,
    arena: std.mem.Allocator,
    gpa: std.mem.Allocator,
    root: []const u8,
    root_dir: Io.Dir,
    out: *Io.Writer,
    err: *Io.Writer,
    color: bool,
    env: *std.process.Environ.Map,

    pub fn flush(ctx: *Ctx) void {
        ctx.out.flush() catch {};
        ctx.err.flush() catch {};
    }
};

fn wrap(ctx: *Ctx, open: []const u8, close: []const u8, text: []const u8) []const u8 {
    if (!ctx.color) return text;
    return std.fmt.allocPrint(ctx.arena, "{s}{s}{s}", .{ open, text, close }) catch text;
}

pub fn dim(ctx: *Ctx, text: []const u8) []const u8 {
    return wrap(ctx, "\x1b[2m", "\x1b[22m", text);
}

pub fn bold(ctx: *Ctx, text: []const u8) []const u8 {
    return wrap(ctx, "\x1b[1m", "\x1b[22m", text);
}

fn green(ctx: *Ctx, text: []const u8) []const u8 {
    return wrap(ctx, "\x1b[32m", "\x1b[39m", text);
}

fn yellow(ctx: *Ctx, text: []const u8) []const u8 {
    return wrap(ctx, "\x1b[33m", "\x1b[39m", text);
}

fn red(ctx: *Ctx, text: []const u8) []const u8 {
    return wrap(ctx, "\x1b[31m", "\x1b[39m", text);
}

fn cyan(ctx: *Ctx, text: []const u8) []const u8 {
    return wrap(ctx, "\x1b[36m", "\x1b[39m", text);
}

fn tag(ctx: *Ctx) []const u8 {
    return dim(ctx, "gentree");
}

pub fn info(ctx: *Ctx, message: []const u8) void {
    ctx.out.print("{s} {s}\n", .{ tag(ctx), message }) catch {};
    ctx.out.flush() catch {};
}

pub fn step(ctx: *Ctx, message: []const u8) void {
    ctx.out.print("{s} {s} {s}\n", .{ tag(ctx), green(ctx, "+"), message }) catch {};
    ctx.out.flush() catch {};
}

pub fn warn(ctx: *Ctx, message: []const u8) void {
    ctx.err.print("{s} {s} {s}\n", .{ tag(ctx), yellow(ctx, "warning"), message }) catch {};
    ctx.err.flush() catch {};
}

pub fn err(ctx: *Ctx, message: []const u8) void {
    ctx.err.print("{s} {s} {s}\n", .{ tag(ctx), red(ctx, "error"), message }) catch {};
    ctx.err.flush() catch {};
}

pub fn build(
    ctx: *Ctx,
    module_count: usize,
    written: usize,
    removed: usize,
    project_changed: bool,
    warnings: []const []const u8,
    out_name: []const u8,
    mirror_dir: []const u8,
    time: ?[]const u8,
) void {
    for (warnings) |w| warn(ctx, w);

    const stamp = if (time) |t|
        std.fmt.allocPrint(ctx.arena, "{s} ", .{dim(ctx, t)}) catch ""
    else
        "";

    const modules = std.fmt.allocPrint(ctx.arena, "{d} {s}", .{
        module_count,
        if (module_count == 1) "module" else "modules",
    }) catch "";

    var changes: std.ArrayList([]const u8) = .empty;
    if (written != 0)
        changes.append(ctx.arena, std.fmt.allocPrint(ctx.arena, "{d} updated", .{written}) catch "") catch {};
    if (removed != 0)
        changes.append(ctx.arena, std.fmt.allocPrint(ctx.arena, "{d} removed", .{removed}) catch "") catch {};
    if (project_changed) changes.append(ctx.arena, out_name) catch {};

    if (changes.items.len == 0) {
        info(ctx, std.fmt.allocPrint(ctx.arena, "{s}{s}{s}", .{
            stamp,
            modules,
            dim(ctx, ", no change"),
        }) catch "");
        return;
    }

    const joined = std.mem.join(ctx.arena, ", ", changes.items) catch "";
    const suffix = std.fmt.allocPrint(ctx.arena, "({s})", .{joined}) catch "";
    info(ctx, std.fmt.allocPrint(ctx.arena, "{s}{s} {s} {s} {s}", .{
        stamp,
        modules,
        dim(ctx, "->"),
        cyan(ctx, mirror_dir),
        dim(ctx, suffix),
    }) catch "");
}

pub fn fail(ctx: *Ctx, message: []const u8) error{Reported} {
    err(ctx, message);
    return error.Reported;
}

pub fn clock(ctx: *Ctx) []const u8 {
    const ts = Io.Timestamp.now(ctx.io, .real);
    const secs: u64 = @intCast(@divFloor(ts.nanoseconds, std.time.ns_per_s));
    const day = secs % 86400;
    const hh = day / 3600;
    const mm = (day % 3600) / 60;
    const ss = day % 60;
    return std.fmt.allocPrint(ctx.arena, "{d:0>2}:{d:0>2}:{d:0>2}", .{ hh, mm, ss }) catch "";
}
