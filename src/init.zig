const std = @import("std");
const report = @import("report.zig");
const cfgmod = @import("config.zig");
const treemod = @import("tree.zig");
const buildmod = @import("build.zig");
const rojomod = @import("rojo.zig");
const Ctx = report.Ctx;

const ScaffoldFile = struct {
    path: []const u8,
    contents: []const u8,
};

const SCAFFOLD_DIRS = [_][]const u8{ "src/ui", "src/classes", "src/modules", "Packages" };

const EXAMPLE_SERVER =
    "local ExampleServiceServer = {}\n\n" ++
    "function ExampleServiceServer.init(self: ExampleServiceServer)\n" ++
    "\tprint(\"hi from ExampleServiceServer!\")\n" ++
    "end\n\n" ++
    "export type ExampleServiceServer = typeof(ExampleServiceServer) & {}\n\n" ++
    "return ExampleServiceServer\n";

const EXAMPLE_CLIENT =
    "local ExampleServiceClient = {}\n\nreturn ExampleServiceClient\n";

const EXAMPLE_UTILS =
    "local ExampleServiceUtils = {}\n\nreturn ExampleServiceUtils\n";

const STARTUP_SERVER =
    "local ServerScriptService = game:GetService(\"ServerScriptService\")\n\n" ++
    "local ExampleServiceServer = require(\n" ++
    "\tServerScriptService.Services.ExampleService.ExampleServiceServer\n" ++
    ")\n\n" ++
    "ExampleServiceServer:init()\n";

fn scaffoldFiles(ctx: *Ctx, name: []const u8) ![]const ScaffoldFile {
    const a = ctx.arena;
    const cfg = cfgmod.defaultConfig(name);

    const config_value = try cfgmod.configToValue(ctx, cfg);
    const config_json = try std.fmt.allocPrint(a, "{s}\n", .{
        try std.json.Stringify.valueAlloc(a, config_value, .{ .whitespace = .indent_2 }),
    });

    const scaffold_value = try treemod.defaultScaffold(ctx, cfg);
    const base_json = try std.fmt.allocPrint(a, "{s}\n", .{
        try std.json.Stringify.valueAlloc(a, scaffold_value, .{ .whitespace = .indent_2 }),
    });

    var files: std.ArrayList(ScaffoldFile) = .empty;
    try files.append(a, .{ .path = cfgmod.CONFIG_FILE, .contents = config_json });
    try files.append(a, .{ .path = "base.project.json", .contents = base_json });
    try files.append(a, .{ .path = "src/services/ExampleService/Server.luau", .contents = EXAMPLE_SERVER });
    try files.append(a, .{ .path = "src/services/ExampleService/Client.luau", .contents = EXAMPLE_CLIENT });
    try files.append(a, .{ .path = "src/services/ExampleService/Utils.luau", .contents = EXAMPLE_UTILS });
    try files.append(a, .{ .path = "src/startup/Server.server.luau", .contents = STARTUP_SERVER });
    try files.append(a, .{ .path = "src/startup/Client.client.luau", .contents = "" });
    return files.toOwnedSlice(a);
}

fn exists(ctx: *Ctx, path: []const u8) bool {
    ctx.root_dir.access(ctx.io, path, .{}) catch return false;
    return true;
}

pub fn init(ctx: *Ctx) !void {
    const a = ctx.arena;

    const rojo = rojomod.detectRojo(ctx);
    if (!rojo.installed) return report.fail(ctx, rojomod.ROJO_MISSING);
    report.info(ctx, try std.fmt.allocPrint(a, "found {s}", .{rojo.version}));

    const name = std.fs.path.basename(ctx.root);
    const files = try scaffoldFiles(ctx, name);
    var created: usize = 0;

    for (files) |file| {
        if (exists(ctx, file.path)) {
            report.info(ctx, try std.fmt.allocPrint(a, "{s} {s}", .{ file.path, report.dim(ctx, "already exists, skipped") }));
            continue;
        }
        if (std.fs.path.dirname(file.path)) |parent| try ctx.root_dir.createDirPath(ctx.io, parent);
        try ctx.root_dir.writeFile(ctx.io, .{ .sub_path = file.path, .data = file.contents });
        report.step(ctx, file.path);
        created += 1;
    }

    for (SCAFFOLD_DIRS) |dir| {
        if (exists(ctx, dir)) continue;
        try ctx.root_dir.createDirPath(ctx.io, dir);
        try ctx.root_dir.writeFile(ctx.io, .{ .sub_path = try std.fs.path.join(a, &.{ dir, ".gitkeep" }), .data = "" });
        report.step(ctx, try std.fmt.allocPrint(a, "{s}/", .{dir}));
    }

    const cfg = try cfgmod.loadConfig(ctx);
    try ignoreMirror(ctx, cfg.mirror.dir);

    const outcome = try buildmod.build(ctx, cfg);
    report.build(ctx, outcome.module_count, outcome.mirror.written, outcome.mirror.removed, outcome.project_changed, outcome.warnings, cfg.out, cfg.mirror.dir, null);

    if (created == 0) report.info(ctx, "project was already initialized");
    report.info(ctx, try std.fmt.allocPrint(a, "next: {s} in one terminal, {s} in another", .{
        report.bold(ctx, "gentree watch"),
        report.bold(ctx, "rojo serve"),
    }));
}

fn ignoreMirror(ctx: *Ctx, dir: []const u8) !void {
    const a = ctx.arena;
    const entry = try std.fmt.allocPrint(a, "{s}/", .{dir});

    const existing = ctx.root_dir.readFileAlloc(ctx.io, ".gitignore", a, .unlimited) catch null;
    if (existing == null) {
        try ctx.root_dir.writeFile(ctx.io, .{ .sub_path = ".gitignore", .data = try std.fmt.allocPrint(a, "{s}\n", .{entry}) });
        report.step(ctx, try std.fmt.allocPrint(a, ".gitignore {s}", .{report.dim(ctx, try std.fmt.allocPrint(a, "({s})", .{entry}))}));
        return;
    }

    const text = existing.?;
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (std.mem.eql(u8, line, entry) or std.mem.eql(u8, line, dir)) return;
    }

    const separator: []const u8 = if (std.mem.endsWith(u8, text, "\n")) "" else "\n";
    try ctx.root_dir.writeFile(ctx.io, .{ .sub_path = ".gitignore", .data = try std.fmt.allocPrint(a, "{s}{s}{s}\n", .{ text, separator, entry }) });
    report.step(ctx, try std.fmt.allocPrint(a, ".gitignore {s}", .{report.dim(ctx, try std.fmt.allocPrint(a, "(+ {s})", .{entry}))}));
}
