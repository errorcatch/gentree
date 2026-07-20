const std = @import("std");
const Io = std.Io;
const report = @import("report.zig");
const cfgmod = @import("config.zig");
const Ctx = report.Ctx;
const Config = cfgmod.Config;
const Bucket = cfgmod.Bucket;
const Value = std.json.Value;

pub const ScriptKind = enum { module, server, client };

pub const ParsedName = struct {
    stem: []const u8,
    kind: ScriptKind,
};

pub const Placement = struct {
    bucket: Bucket,
    folder: []const []const u8,
    name: []const u8,
    source: []const u8,
    is_directory: bool,
    file_name: []const u8,
};

pub fn defaultScaffold(ctx: *Ctx, cfg: Config) !Value {
    const a = ctx.arena;
    const dir = cfg.mirror.dir;

    var shared: std.json.ObjectMap = .empty;
    try shared.put(a, "$path", .{ .string = try std.fmt.allocPrint(a, "{s}/{s}", .{ dir, cfg.mirror.roots.shared }) });
    var packages: std.json.ObjectMap = .empty;
    try packages.put(a, "$path", .{ .string = "Packages" });
    var ui: std.json.ObjectMap = .empty;
    try ui.put(a, "$path", .{ .string = "src/ui" });

    var replicated: std.json.ObjectMap = .empty;
    try replicated.put(a, "Shared", .{ .object = shared });
    try replicated.put(a, "Packages", .{ .object = packages });
    try replicated.put(a, "UI", .{ .object = ui });

    var server: std.json.ObjectMap = .empty;
    try server.put(a, "$path", .{ .string = try std.fmt.allocPrint(a, "{s}/{s}", .{ dir, cfg.mirror.roots.server }) });

    var client: std.json.ObjectMap = .empty;
    try client.put(a, "$path", .{ .string = try std.fmt.allocPrint(a, "{s}/{s}", .{ dir, cfg.mirror.roots.client }) });
    var starter: std.json.ObjectMap = .empty;
    try starter.put(a, "StarterPlayerScripts", .{ .object = client });

    var tree: std.json.ObjectMap = .empty;
    try tree.put(a, "$className", .{ .string = "DataModel" });
    try tree.put(a, "ReplicatedStorage", .{ .object = replicated });
    try tree.put(a, "ServerScriptService", .{ .object = server });
    try tree.put(a, "StarterPlayer", .{ .object = starter });

    var root: std.json.ObjectMap = .empty;
    try root.put(a, "name", .{ .string = cfg.name });
    try root.put(a, "tree", .{ .object = tree });

    return .{ .object = root };
}

pub fn loadScaffold(ctx: *Ctx, cfg: Config) !Value {
    const text = ctx.root_dir.readFileAlloc(ctx.io, cfg.base, ctx.arena, .unlimited) catch
        return defaultScaffold(ctx, cfg);

    const parsed = std.json.parseFromSlice(Value, ctx.arena, text, .{}) catch |e|
        return report.fail(ctx, try std.fmt.allocPrint(ctx.arena, "{s} is not valid JSON: {t}", .{ cfg.base, e }));

    if (parsed.value != .object)
        return report.fail(ctx, try std.fmt.allocPrint(ctx.arena, "{s} has no `tree` object", .{cfg.base}));

    var obj = parsed.value.object;
    const tree = obj.get("tree");
    if (tree == null or tree.? != .object)
        return report.fail(ctx, try std.fmt.allocPrint(ctx.arena, "{s} has no `tree` object", .{cfg.base}));

    try obj.put(ctx.arena, "name", .{ .string = cfg.name });
    return .{ .object = obj };
}

pub fn writeProjectFile(ctx: *Ctx, cfg: Config) !bool {
    const project = try loadScaffold(ctx, cfg);
    const body = try std.json.Stringify.valueAlloc(ctx.arena, project, .{ .whitespace = .indent_2 });
    const rendered = try std.fmt.allocPrint(ctx.arena, "{s}\n", .{body});

    const existing = ctx.root_dir.readFileAlloc(ctx.io, cfg.out, ctx.arena, .unlimited) catch null;
    if (existing) |cur| {
        if (std.mem.eql(u8, cur, rendered)) return false;
    }

    try ctx.root_dir.writeFile(ctx.io, .{ .sub_path = cfg.out, .data = rendered });
    return true;
}

const Entry = struct {
    name: []const u8,
    is_dir: bool,
};

pub fn collectFiles(ctx: *Ctx, cfg: Config) ![]const []const u8 {
    var files: std.ArrayList([]const u8) = .empty;
    try collectInto(ctx, cfg, "", &files);
    return files.toOwnedSlice(ctx.arena);
}

fn collectInto(ctx: *Ctx, cfg: Config, sub: []const u8, files: *std.ArrayList([]const u8)) !void {
    const a = ctx.arena;
    const current = if (sub.len == 0) cfg.src else try std.fs.path.join(a, &.{ cfg.src, sub });

    var dir = ctx.root_dir.openDir(ctx.io, current, .{ .iterate = true }) catch return;
    defer dir.close(ctx.io);

    var entries: std.ArrayList(Entry) = .empty;
    var it = dir.iterate();
    while (try it.next(ctx.io)) |entry| {
        try entries.append(a, .{
            .name = try a.dupe(u8, entry.name),
            .is_dir = entry.kind == .directory,
        });
    }
    std.mem.sort(Entry, entries.items, {}, lessByName);

    for (entries.items) |entry| {
        const rel = if (sub.len == 0) entry.name else try std.fs.path.join(a, &.{ sub, entry.name });
        if (entry.is_dir) {
            const posix = try toPosix(a, rel);
            if (isExcluded(cfg, posix)) continue;
            try collectInto(ctx, cfg, rel, files);
        } else {
            if (cfgmod.isSourceExt(cfg, extNoDot(entry.name))) try files.append(a, rel);
        }
    }
}

fn lessByName(_: void, a: Entry, b: Entry) bool {
    return std.mem.lessThan(u8, a.name, b.name);
}

fn isExcluded(cfg: Config, relative_posix: []const u8) bool {
    for (cfg.scan.exclude) |pattern| {
        if (std.ascii.eqlIgnoreCase(pattern, relative_posix)) return true;
    }
    return false;
}

pub fn parseName(a: std.mem.Allocator, file: []const u8) !ParsedName {
    const base = std.fs.path.basename(file);
    const ext = std.fs.path.extension(base);
    const without_ext = base[0 .. base.len - ext.len];
    const lower = try std.ascii.allocLowerString(a, without_ext);

    if (std.mem.endsWith(u8, lower, ".server"))
        return .{ .stem = without_ext[0 .. without_ext.len - ".server".len], .kind = .server };
    if (std.mem.endsWith(u8, lower, ".client"))
        return .{ .stem = without_ext[0 .. without_ext.len - ".client".len], .kind = .client };
    return .{ .stem = without_ext, .kind = .module };
}

pub fn resolve(ctx: *Ctx, files: []const []const u8, cfg: Config) ![]const Placement {
    const a = ctx.arena;

    var claimed: std.ArrayList([]const []const u8) = .empty;
    for (files) |file| {
        const parsed = try parseName(a, file);
        if (cfgmod.isInitStem(cfg, parsed.stem)) try claimed.append(a, try folderSegments(a, cfg, file));
    }

    var placements: std.ArrayList(Placement) = .empty;
    for (files) |file| {
        const parsed = try parseName(a, file);
        const segments = try folderSegments(a, cfg, file);

        if (cfgmod.isInitStem(cfg, parsed.stem)) {
            const name = if (segments.len != 0) segments[segments.len - 1] else "";
            const parent_dir = std.fs.path.dirname(file);
            const source_dir = if (parent_dir == null or std.mem.eql(u8, parent_dir.?, "."))
                cfg.src
            else
                try std.fs.path.join(a, &.{ cfg.src, parent_dir.? });

            try placements.append(a, .{
                .bucket = bucketFor(cfg, name, parsed.kind),
                .folder = segments[0..if (segments.len != 0) segments.len - 1 else 0],
                .name = name,
                .source = try toPosix(a, source_dir),
                .is_directory = true,
                .file_name = name,
            });
            continue;
        }

        if (isSuppressed(claimed.items, segments)) continue;

        const parent = if (segments.len != 0) segments[segments.len - 1] else "";
        const name = if (cfgmod.isQualifiedStem(cfg, parsed.stem))
            try std.fmt.allocPrint(a, "{s}{s}", .{ parent, try pascal(a, parsed.stem) })
        else
            parsed.stem;
        const suffix = switch (parsed.kind) {
            .module => "",
            .server => ".server",
            .client => ".client",
        };

        try placements.append(a, .{
            .bucket = bucketFor(cfg, parsed.stem, parsed.kind),
            .folder = segments,
            .name = name,
            .source = try toPosix(a, try std.fs.path.join(a, &.{ cfg.src, file })),
            .is_directory = false,
            .file_name = try std.fmt.allocPrint(a, "{s}{s}{s}", .{ name, suffix, std.fs.path.extension(file) }),
        });
    }
    return placements.toOwnedSlice(a);
}

fn isSuppressed(claims: []const []const []const u8, segments: []const []const u8) bool {
    for (claims) |claim| {
        if (segments.len < claim.len) continue;
        var all = true;
        for (claim, 0..) |part, i| {
            if (!std.mem.eql(u8, part, segments[i])) {
                all = false;
                break;
            }
        }
        if (all) return true;
    }
    return false;
}

fn bucketFor(cfg: Config, stem: []const u8, kind: ScriptKind) Bucket {
    if (kind == .server) return .server;
    if (kind == .client) return .client;
    return if (cfgmod.isServerStem(cfg, stem)) .server else .shared;
}

fn folderSegments(a: std.mem.Allocator, cfg: Config, file: []const u8) ![]const []const u8 {
    const parent = std.fs.path.dirname(file);
    if (parent == null or parent.?.len == 0 or std.mem.eql(u8, parent.?, ".")) return &.{};

    var segments: std.ArrayList([]const u8) = .empty;
    var it = std.mem.tokenizeAny(u8, parent.?, "\\/");
    while (it.next()) |part| {
        try segments.append(a, if (cfg.naming.pascal_case_folders) try pascal(a, part) else part);
    }
    return segments.toOwnedSlice(a);
}

pub fn toPosix(a: std.mem.Allocator, value: []const u8) ![]const u8 {
    const copy = try a.dupe(u8, value);
    std.mem.replaceScalar(u8, copy, '\\', '/');
    return copy;
}

fn pascal(a: std.mem.Allocator, text: []const u8) ![]const u8 {
    if (text.len == 0) return "";
    const copy = try a.dupe(u8, text);
    copy[0] = std.ascii.toUpper(copy[0]);
    return copy;
}

fn extNoDot(name: []const u8) []const u8 {
    const ext = std.fs.path.extension(name);
    return if (ext.len != 0 and ext[0] == '.') ext[1..] else ext;
}
