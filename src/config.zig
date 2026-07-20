const std = @import("std");
const report = @import("report.zig");
const Ctx = report.Ctx;
const Value = std.json.Value;

pub const CONFIG_FILE = "gentree.config.json";

pub const Bucket = enum { shared, server, client };

pub const Roots = struct {
    shared: []const u8,
    server: []const u8,
    client: []const u8,

    pub fn get(self: Roots, bucket: Bucket) []const u8 {
        return switch (bucket) {
            .shared => self.shared,
            .server => self.server,
            .client => self.client,
        };
    }
};

pub const Mirror = struct {
    dir: []const u8,
    roots: Roots,
    folders: []const []const u8,
    prune_dirs: bool,
    prune_delay_ms: u64,
};

pub const EntryPoints = struct {
    server: ?[]const u8,
    client: ?[]const u8,
};

pub const Scan = struct {
    exclude: []const []const u8,
    extensions: []const []const u8,
};

pub const Naming = struct {
    qualify: []const []const u8,
    init: []const []const u8,
    pascal_case_folders: bool,
};

pub const Routing = struct {
    server_stems: []const []const u8,
};

pub const Config = struct {
    name: []const u8,
    src: []const u8,
    out: []const u8,
    base: []const u8,
    mirror: Mirror,
    entry_points: EntryPoints,
    scan: Scan,
    naming: Naming,
    routing: Routing,
};

pub fn defaultConfig(name: []const u8) Config {
    return .{
        .name = name,
        .src = "src",
        .out = "default.project.json",
        .base = "base.project.json",
        .mirror = .{
            .dir = ".gentree",
            .roots = .{ .shared = "shared", .server = "server", .client = "client" },
            .folders = &.{ "Services", "Classes", "Modules" },
            .prune_dirs = true,
            .prune_delay_ms = 1000,
        },
        .entry_points = .{
            .server = "src/startup/Server.server.luau",
            .client = "src/startup/Client.client.luau",
        },
        .scan = .{
            .exclude = &.{ "ui", "startup" },
            .extensions = &.{ "luau", "lua" },
        },
        .naming = .{
            .qualify = &.{ "Server", "Client", "Utils", "Types" },
            .init = &.{"init"},
            .pascal_case_folders = true,
        },
        .routing = .{ .server_stems = &.{"Server"} },
    };
}

pub fn loadConfig(ctx: *Ctx) !Config {
    const name = std.fs.path.basename(ctx.root);
    const base = defaultConfig(name);

    const text = ctx.root_dir.readFileAlloc(ctx.io, CONFIG_FILE, ctx.arena, .unlimited) catch return base;

    const parsed = std.json.parseFromSlice(Value, ctx.arena, text, .{}) catch |e| {
        return report.fail(ctx, std.fmt.allocPrint(ctx.arena, "{s} is not valid JSON: {t}", .{ CONFIG_FILE, e }) catch CONFIG_FILE);
    };

    return merge(ctx, base, parsed.value);
}

fn merge(ctx: *Ctx, base: Config, value: Value) Config {
    if (value != .object) return base;
    const obj = value.object;

    var cfg = base;
    if (getStr(obj, "name")) |v| cfg.name = v;
    if (getStr(obj, "src")) |v| cfg.src = v;
    if (getStr(obj, "out")) |v| cfg.out = v;
    if (getStr(obj, "base")) |v| cfg.base = v;

    if (child(obj, "mirror")) |m| {
        if (getStr(m, "dir")) |v| cfg.mirror.dir = v;
        if (child(m, "roots")) |r| {
            if (getStr(r, "shared")) |v| cfg.mirror.roots.shared = v;
            if (getStr(r, "server")) |v| cfg.mirror.roots.server = v;
            if (getStr(r, "client")) |v| cfg.mirror.roots.client = v;
        }
        if (getStrArray(ctx, m, "folders")) |v| cfg.mirror.folders = v;
        if (getBool(m, "pruneDirs")) |v| cfg.mirror.prune_dirs = v;
        if (getU64(m, "pruneDelayMs")) |v| cfg.mirror.prune_delay_ms = v;
    }

    if (child(obj, "entryPoints")) |e| {
        if (e.get("server")) |v| cfg.entry_points.server = if (v == .string) v.string else null;
        if (e.get("client")) |v| cfg.entry_points.client = if (v == .string) v.string else null;
    }

    if (child(obj, "scan")) |s| {
        if (getStrArray(ctx, s, "exclude")) |v| cfg.scan.exclude = v;
        if (getStrArray(ctx, s, "extensions")) |v| cfg.scan.extensions = v;
    }

    if (child(obj, "naming")) |n| {
        if (getStrArray(ctx, n, "qualify")) |v| cfg.naming.qualify = v;
        if (getStrArray(ctx, n, "init")) |v| cfg.naming.init = v;
        if (getBool(n, "pascalCaseFolders")) |v| cfg.naming.pascal_case_folders = v;
    }

    if (child(obj, "routing")) |r| {
        if (getStrArray(ctx, r, "serverStems")) |v| cfg.routing.server_stems = v;
    }

    return cfg;
}

fn child(obj: std.json.ObjectMap, key: []const u8) ?std.json.ObjectMap {
    const v = obj.get(key) orelse return null;
    return if (v == .object) v.object else null;
}

fn getStr(obj: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const v = obj.get(key) orelse return null;
    return if (v == .string) v.string else null;
}

fn getBool(obj: std.json.ObjectMap, key: []const u8) ?bool {
    const v = obj.get(key) orelse return null;
    return if (v == .bool) v.bool else null;
}

fn getU64(obj: std.json.ObjectMap, key: []const u8) ?u64 {
    const v = obj.get(key) orelse return null;
    return if (v == .integer and v.integer >= 0) @intCast(v.integer) else null;
}

fn getStrArray(ctx: *Ctx, obj: std.json.ObjectMap, key: []const u8) ?[]const []const u8 {
    const v = obj.get(key) orelse return null;
    if (v != .array) return null;
    var list: std.ArrayList([]const u8) = .empty;
    for (v.array.items) |item| {
        if (item == .string) list.append(ctx.arena, item.string) catch return null;
    }
    return list.toOwnedSlice(ctx.arena) catch null;
}

pub fn configToValue(ctx: *Ctx, cfg: Config) !Value {
    const a = ctx.arena;

    var roots: std.json.ObjectMap = .empty;
    try roots.put(a, "shared", .{ .string = cfg.mirror.roots.shared });
    try roots.put(a, "server", .{ .string = cfg.mirror.roots.server });
    try roots.put(a, "client", .{ .string = cfg.mirror.roots.client });

    var mirror: std.json.ObjectMap = .empty;
    try mirror.put(a, "dir", .{ .string = cfg.mirror.dir });
    try mirror.put(a, "roots", .{ .object = roots });
    try mirror.put(a, "folders", try strArray(a, cfg.mirror.folders));
    try mirror.put(a, "pruneDirs", .{ .bool = cfg.mirror.prune_dirs });
    try mirror.put(a, "pruneDelayMs", .{ .integer = @intCast(cfg.mirror.prune_delay_ms) });

    var entry: std.json.ObjectMap = .empty;
    try entry.put(a, "server", strOrNull(cfg.entry_points.server));
    try entry.put(a, "client", strOrNull(cfg.entry_points.client));

    var scan: std.json.ObjectMap = .empty;
    try scan.put(a, "exclude", try strArray(a, cfg.scan.exclude));
    try scan.put(a, "extensions", try strArray(a, cfg.scan.extensions));

    var naming: std.json.ObjectMap = .empty;
    try naming.put(a, "qualify", try strArray(a, cfg.naming.qualify));
    try naming.put(a, "init", try strArray(a, cfg.naming.init));
    try naming.put(a, "pascalCaseFolders", .{ .bool = cfg.naming.pascal_case_folders });

    var routing: std.json.ObjectMap = .empty;
    try routing.put(a, "serverStems", try strArray(a, cfg.routing.server_stems));

    var root: std.json.ObjectMap = .empty;
    try root.put(a, "name", .{ .string = cfg.name });
    try root.put(a, "src", .{ .string = cfg.src });
    try root.put(a, "out", .{ .string = cfg.out });
    try root.put(a, "base", .{ .string = cfg.base });
    try root.put(a, "mirror", .{ .object = mirror });
    try root.put(a, "entryPoints", .{ .object = entry });
    try root.put(a, "scan", .{ .object = scan });
    try root.put(a, "naming", .{ .object = naming });
    try root.put(a, "routing", .{ .object = routing });

    return .{ .object = root };
}

fn strArray(a: std.mem.Allocator, items: []const []const u8) !Value {
    var arr = std.json.Array.init(a);
    for (items) |item| try arr.append(.{ .string = item });
    return .{ .array = arr };
}

fn strOrNull(value: ?[]const u8) Value {
    return if (value) |v| .{ .string = v } else .null;
}

fn eqCI(list: []const []const u8, value: []const u8) bool {
    for (list) |item| {
        if (std.ascii.eqlIgnoreCase(item, value)) return true;
    }
    return false;
}

pub fn isServerStem(cfg: Config, stem: []const u8) bool {
    return eqCI(cfg.routing.server_stems, stem);
}

pub fn isQualifiedStem(cfg: Config, stem: []const u8) bool {
    return eqCI(cfg.naming.qualify, stem);
}

pub fn isInitStem(cfg: Config, stem: []const u8) bool {
    return eqCI(cfg.naming.init, stem);
}

pub fn isSourceExt(cfg: Config, ext: []const u8) bool {
    return eqCI(cfg.scan.extensions, ext);
}
