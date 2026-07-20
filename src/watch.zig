const std = @import("std");
const Io = std.Io;
const report = @import("report.zig");
const cfgmod = @import("config.zig");
const buildmod = @import("build.zig");
const mirrormod = @import("mirror.zig");
const Ctx = report.Ctx;
const Config = cfgmod.Config;

const POLL_MS = 200;

pub fn watch(ctx: *Ctx, initial: Config) !void {
    report.info(ctx, try std.fmt.allocPrint(ctx.arena, "watching {s} {s}", .{
        report.bold(ctx, initial.src),
        report.dim(ctx, "(ctrl-c to stop)"),
    }));

    var scratch = std.heap.ArenaAllocator.init(ctx.gpa);
    defer scratch.deinit();

    var prev_acc: u128 = 0;
    var prev_count: usize = 0;
    var prev_config: i128 = 0;
    var first = true;

    while (true) {
        _ = scratch.reset(.retain_capacity);
        ctx.arena = scratch.allocator();

        const cfg = cfgmod.loadConfig(ctx) catch {
            Io.sleep(ctx.io, Io.Duration.fromMilliseconds(POLL_MS), .awake) catch {};
            continue;
        };

        var acc: u128 = 0;
        var count: usize = 0;
        scanDir(ctx, cfg.src, &acc, &count) catch {};
        const config_mtime = statMtime(ctx, cfgmod.CONFIG_FILE);
        const base_mtime = statMtime(ctx, cfg.base);
        acc +%= mix(cfgmod.CONFIG_FILE, config_mtime);
        acc +%= mix(cfg.base, base_mtime);

        const changed = first or acc != prev_acc or count != prev_count;
        const config_changed = !first and config_mtime != prev_config;

        if (changed) {
            if (config_changed) report.info(ctx, try std.fmt.allocPrint(ctx.arena, "reloaded {s}", .{cfgmod.CONFIG_FILE}));

            if (buildmod.build(ctx, cfg)) |outcome| {
                report.build(ctx, outcome.module_count, outcome.mirror.written, outcome.mirror.removed, outcome.project_changed, outcome.warnings, cfg.out, cfg.mirror.dir, report.clock(ctx));

                if (outcome.mirror.removed != 0 and cfg.mirror.prune_dirs) {
                    Io.sleep(ctx.io, Io.Duration.fromMilliseconds(@intCast(cfg.mirror.prune_delay_ms)), .awake) catch {};
                    const removed = mirrormod.pruneMirror(ctx, cfg) catch 0;
                    if (removed != 0) report.info(ctx, try std.fmt.allocPrint(ctx.arena, "{s} pruned {d} empty folder{s}", .{
                        report.dim(ctx, report.clock(ctx)),
                        removed,
                        if (removed == 1) "" else "s",
                    }));
                }
            } else |e| {
                if (e != error.Reported) report.err(ctx, @errorName(e));
            }
        }

        prev_acc = acc;
        prev_count = count;
        prev_config = config_mtime;
        first = false;

        Io.sleep(ctx.io, Io.Duration.fromMilliseconds(POLL_MS), .awake) catch {};
    }
}

fn scanDir(ctx: *Ctx, dir: []const u8, acc: *u128, count: *usize) !void {
    const a = ctx.arena;
    var handle = ctx.root_dir.openDir(ctx.io, dir, .{ .iterate = true }) catch return;
    defer handle.close(ctx.io);

    var it = handle.iterate();
    while (try it.next(ctx.io)) |entry| {
        const child = try std.fs.path.join(a, &.{ dir, entry.name });
        if (entry.kind == .directory) {
            try scanDir(ctx, child, acc, count);
        } else {
            acc.* +%= mix(child, statMtime(ctx, child));
            count.* += 1;
        }
    }
}

fn statMtime(ctx: *Ctx, path: []const u8) i128 {
    const stat = ctx.root_dir.statFile(ctx.io, path, .{}) catch return 0;
    return stat.mtime.nanoseconds;
}

fn mix(name: []const u8, mtime: i128) u128 {
    const h: u128 = std.hash.Wyhash.hash(0, name);
    return (h *% 1000003) ^ @as(u128, @bitCast(mtime));
}
