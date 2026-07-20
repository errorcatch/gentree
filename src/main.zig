const std = @import("std");
const Io = std.Io;
const report = @import("report.zig");
const cfgmod = @import("config.zig");
const buildmod = @import("build.zig");
const mirrormod = @import("mirror.zig");
const initmod = @import("init.zig");
const watchmod = @import("watch.zig");
const Ctx = report.Ctx;

const VERSION = "0.2.0";

const HELP =
    \\Usage: gentree [options] [command]
    \\
    \\Generate a Rojo project tree from your source layout, live.
    \\
    \\Options:
    \\  -C, --root <dir>  project root to operate on (default: ".")
    \\  -V, --version     output the version number
    \\  -h, --help        display help
    \\
    \\Commands:
    \\  init              scaffold the source layout and generate the first project file
    \\  build             generate the project file once
    \\  clean             delete the generated mirror directory
    \\  watch             generate the project file and regenerate it as sources change
;

pub fn main(init: std.process.Init) !u8 {
    const arena = init.arena.allocator();
    const io = init.io;

    var out_buf: [8192]u8 = undefined;
    var out_writer = Io.File.stdout().writer(io, &out_buf);
    var err_buf: [4096]u8 = undefined;
    var err_writer = Io.File.stderr().writer(io, &err_buf);

    const args = try init.minimal.args.toSlice(arena);

    var root: []const u8 = ".";
    var command: ?[]const u8 = null;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-C") or std.mem.eql(u8, arg, "--root")) {
            if (i + 1 < args.len) {
                i += 1;
                root = args[i];
            }
        } else if (std.mem.startsWith(u8, arg, "--root=")) {
            root = arg["--root=".len..];
        } else if (std.mem.eql(u8, arg, "-V") or std.mem.eql(u8, arg, "--version")) {
            out_writer.interface.print("{s}\n", .{VERSION}) catch {};
            out_writer.interface.flush() catch {};
            return 0;
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            out_writer.interface.print("{s}\n", .{HELP}) catch {};
            out_writer.interface.flush() catch {};
            return 0;
        } else if (command == null) {
            command = arg;
        }
    }

    const root_abs = try std.fs.path.resolve(arena, &.{root});
    const root_dir = Io.Dir.openDirAbsolute(io, root_abs, .{}) catch {
        err_writer.interface.print("gentree error cannot open {s}\n", .{root_abs}) catch {};
        err_writer.interface.flush() catch {};
        return 1;
    };

    var ctx = Ctx{
        .io = io,
        .arena = arena,
        .gpa = init.gpa,
        .root = root_abs,
        .root_dir = root_dir,
        .out = &out_writer.interface,
        .err = &err_writer.interface,
        .color = init.environ_map.get("NO_COLOR") == null and (Io.File.stdout().isTty(io) catch false),
        .env = init.environ_map,
    };

    run(&ctx, command) catch |e| {
        if (e != error.Reported) report.err(&ctx, @errorName(e));
        ctx.flush();
        return 1;
    };
    ctx.flush();
    return 0;
}

fn run(ctx: *Ctx, command: ?[]const u8) !void {
    const cmd = command orelse {
        ctx.out.print("{s}\n", .{HELP}) catch {};
        return;
    };

    if (std.mem.eql(u8, cmd, "init")) {
        try initmod.init(ctx);
    } else if (std.mem.eql(u8, cmd, "build")) {
        try cmdBuild(ctx);
    } else if (std.mem.eql(u8, cmd, "clean")) {
        try cmdClean(ctx);
    } else if (std.mem.eql(u8, cmd, "watch")) {
        try cmdWatch(ctx);
    } else {
        return report.fail(ctx, try std.fmt.allocPrint(ctx.arena, "unknown command `{s}`", .{cmd}));
    }
}

fn cmdBuild(ctx: *Ctx) !void {
    const cfg = try cfgmod.loadConfig(ctx);
    try requireSrc(ctx, cfg.src);

    const outcome = try buildmod.build(ctx, cfg);
    report.build(ctx, outcome.module_count, outcome.mirror.written, outcome.mirror.removed, outcome.project_changed, outcome.warnings, cfg.out, cfg.mirror.dir, null);

    if (cfg.mirror.prune_dirs) {
        Io.sleep(ctx.io, Io.Duration.fromMilliseconds(@intCast(cfg.mirror.prune_delay_ms)), .awake) catch {};
        const removed = try mirrormod.pruneMirror(ctx, cfg);
        if (removed != 0) report.info(ctx, try std.fmt.allocPrint(ctx.arena, "pruned {d} empty folder{s}", .{ removed, if (removed == 1) "" else "s" }));
    }
}

fn cmdClean(ctx: *Ctx) !void {
    const cfg = try cfgmod.loadConfig(ctx);
    try mirrormod.cleanMirror(ctx, cfg);
    report.info(ctx, try std.fmt.allocPrint(ctx.arena, "removed {s}", .{cfg.mirror.dir}));
}

fn cmdWatch(ctx: *Ctx) !void {
    const cfg = try cfgmod.loadConfig(ctx);
    try requireSrc(ctx, cfg.src);
    try watchmod.watch(ctx, cfg);
}

fn requireSrc(ctx: *Ctx, src: []const u8) !void {
    ctx.root_dir.access(ctx.io, src, .{}) catch {
        return report.fail(ctx, try std.fmt.allocPrint(ctx.arena, "no `{s}` directory in {s}\n\nRun `gentree init` to scaffold one.", .{ src, ctx.root }));
    };
}
