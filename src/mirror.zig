const std = @import("std");
const Io = std.Io;
const report = @import("report.zig");
const cfgmod = @import("config.zig");
const treemod = @import("tree.zig");
const Ctx = report.Ctx;
const Config = cfgmod.Config;
const Bucket = cfgmod.Bucket;
const Placement = treemod.Placement;

pub const MirrorOutcome = struct {
    written: usize,
    removed: usize,
    total: usize,
    warnings: []const []const u8,
};

const Desired = std.StringArrayHashMapUnmanaged([]const u8);

fn claim(
    ctx: *Ctx,
    desired: *Desired,
    warnings: *std.ArrayList([]const u8),
    target: []const u8,
    source: []const u8,
) !void {
    if (desired.get(target)) |existing| {
        if (!std.mem.eql(u8, existing, source)) {
            try warnings.append(ctx.arena, try std.fmt.allocPrint(ctx.arena, "{s} claimed by both {s} and {s}; keeping the first", .{
                try treemod.toPosix(ctx.arena, target),
                try treemod.toPosix(ctx.arena, existing),
                try treemod.toPosix(ctx.arena, source),
            }));
            return;
        }
    }
    try desired.put(ctx.arena, target, source);
}

pub fn syncMirror(ctx: *Ctx, cfg: Config, placements: []const Placement) !MirrorOutcome {
    const a = ctx.arena;
    const mirror_root = cfg.mirror.dir;

    var warnings: std.ArrayList([]const u8) = .empty;
    var desired: Desired = .empty;

    for (placements) |placement| {
        const bucket_dir = try std.fs.path.join(a, &.{ mirror_root, cfg.mirror.roots.get(placement.bucket) });
        const parent = try joinWith(a, bucket_dir, placement.folder);

        if (placement.is_directory) {
            const base = try std.fs.path.join(a, &.{ parent, placement.name });
            const inners = try listFiles(ctx, placement.source);
            for (inners) |inner| {
                try claim(ctx, &desired, &warnings, try std.fs.path.join(a, &.{ base, inner }), try std.fs.path.join(a, &.{ placement.source, inner }));
            }
        } else {
            try claim(ctx, &desired, &warnings, try std.fs.path.join(a, &.{ parent, placement.file_name }), placement.source);
        }
    }

    try claimEntry(ctx, cfg, &desired, &warnings, .server, cfg.entry_points.server);
    try claimEntry(ctx, cfg, &desired, &warnings, .client, cfg.entry_points.client);

    const required = try requiredDirs(ctx, cfg);
    for (required) |dir| try ctx.root_dir.createDirPath(ctx.io, dir);

    var written: usize = 0;
    var it = desired.iterator();
    while (it.next()) |pair| {
        if (try copyIfChanged(ctx, pair.value_ptr.*, pair.key_ptr.*)) written += 1;
    }

    const existing = try listFiles(ctx, mirror_root);
    var removed: usize = 0;
    for (existing) |relative| {
        const absolute = try std.fs.path.join(a, &.{ mirror_root, relative });
        if (desired.contains(absolute)) continue;
        ctx.root_dir.deleteFile(ctx.io, absolute) catch {};
        removed += 1;
    }

    return .{
        .written = written,
        .removed = removed,
        .total = desired.count(),
        .warnings = try warnings.toOwnedSlice(a),
    };
}

fn claimEntry(
    ctx: *Ctx,
    cfg: Config,
    desired: *Desired,
    warnings: *std.ArrayList([]const u8),
    bucket: Bucket,
    entry: ?[]const u8,
) !void {
    const source = entry orelse return;
    const bucket_dir = try std.fs.path.join(ctx.arena, &.{ cfg.mirror.dir, cfg.mirror.roots.get(bucket) });
    const target = try std.fs.path.join(ctx.arena, &.{ bucket_dir, std.fs.path.basename(source) });
    try claim(ctx, desired, warnings, target, source);
}

pub fn pruneMirror(ctx: *Ctx, cfg: Config) !usize {
    const keep = try requiredDirs(ctx, cfg);
    return pruneEmptyDirs(ctx, cfg.mirror.dir, keep);
}

fn pruneEmptyDirs(ctx: *Ctx, dir: []const u8, keep: []const []const u8) !usize {
    const a = ctx.arena;
    var handle = ctx.root_dir.openDir(ctx.io, dir, .{ .iterate = true }) catch return 0;

    var names: std.ArrayList([]const u8) = .empty;
    var it = handle.iterate();
    while (try it.next(ctx.io)) |entry| {
        if (entry.kind == .directory) try names.append(a, try a.dupe(u8, entry.name));
    }
    handle.close(ctx.io);

    var removed: usize = 0;
    for (names.items) |name| {
        const child = try std.fs.path.join(a, &.{ dir, name });
        removed += try pruneEmptyDirs(ctx, child, keep);

        if (contains(keep, child)) continue;

        if (try isEmptyDir(ctx, child)) {
            ctx.root_dir.deleteDir(ctx.io, child) catch continue;
            removed += 1;
        }
    }
    return removed;
}

fn isEmptyDir(ctx: *Ctx, dir: []const u8) !bool {
    var handle = ctx.root_dir.openDir(ctx.io, dir, .{ .iterate = true }) catch return false;
    defer handle.close(ctx.io);
    var it = handle.iterate();
    return (try it.next(ctx.io)) == null;
}

pub fn cleanMirror(ctx: *Ctx, cfg: Config) !void {
    ctx.root_dir.deleteTree(ctx.io, cfg.mirror.dir) catch {};
}

fn copyIfChanged(ctx: *Ctx, source: []const u8, target: []const u8) !bool {
    const contents = ctx.root_dir.readFileAlloc(ctx.io, source, ctx.arena, .unlimited) catch return false;

    const existing = ctx.root_dir.readFileAlloc(ctx.io, target, ctx.arena, .unlimited) catch null;
    if (existing) |cur| {
        if (std.mem.eql(u8, cur, contents)) return false;
    }

    if (std.fs.path.dirname(target)) |parent| try ctx.root_dir.createDirPath(ctx.io, parent);
    try ctx.root_dir.writeFile(ctx.io, .{ .sub_path = target, .data = contents });
    return true;
}

fn listFiles(ctx: *Ctx, dir: []const u8) ![]const []const u8 {
    var files: std.ArrayList([]const u8) = .empty;
    try listInto(ctx, dir, "", &files);
    return files.toOwnedSlice(ctx.arena);
}

fn listInto(ctx: *Ctx, dir: []const u8, prefix: []const u8, files: *std.ArrayList([]const u8)) !void {
    const a = ctx.arena;
    var handle = ctx.root_dir.openDir(ctx.io, dir, .{ .iterate = true }) catch return;

    var entries: std.ArrayList(NameKind) = .empty;
    var it = handle.iterate();
    while (try it.next(ctx.io)) |entry| {
        try entries.append(a, .{ .name = try a.dupe(u8, entry.name), .is_dir = entry.kind == .directory });
    }
    handle.close(ctx.io);

    for (entries.items) |entry| {
        const relative = if (prefix.len == 0) entry.name else try std.fs.path.join(a, &.{ prefix, entry.name });
        if (entry.is_dir) {
            try listInto(ctx, try std.fs.path.join(a, &.{ dir, entry.name }), relative, files);
        } else {
            try files.append(a, relative);
        }
    }
}

const NameKind = struct {
    name: []const u8,
    is_dir: bool,
};

fn requiredDirs(ctx: *Ctx, cfg: Config) ![]const []const u8 {
    const a = ctx.arena;
    var dirs: std.ArrayList([]const u8) = .empty;
    const roots = [_][]const u8{ cfg.mirror.roots.shared, cfg.mirror.roots.server, cfg.mirror.roots.client };

    for (roots) |bucket| {
        const bucket_dir = try std.fs.path.join(a, &.{ cfg.mirror.dir, bucket });
        try dirs.append(a, bucket_dir);
        if (std.mem.eql(u8, bucket, cfg.mirror.roots.client)) continue;
        for (cfg.mirror.folders) |folder| try dirs.append(a, try std.fs.path.join(a, &.{ bucket_dir, folder }));
    }
    return dirs.toOwnedSlice(a);
}

fn joinWith(a: std.mem.Allocator, head: []const u8, tail: []const []const u8) ![]const u8 {
    var parts: std.ArrayList([]const u8) = .empty;
    try parts.append(a, head);
    for (tail) |part| try parts.append(a, part);
    return std.fs.path.join(a, parts.items);
}

fn contains(list: []const []const u8, value: []const u8) bool {
    for (list) |item| {
        if (std.mem.eql(u8, item, value)) return true;
    }
    return false;
}
