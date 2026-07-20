const report = @import("report.zig");
const cfgmod = @import("config.zig");
const treemod = @import("tree.zig");
const mirrormod = @import("mirror.zig");
const Ctx = report.Ctx;
const Config = cfgmod.Config;

pub const BuildOutcome = struct {
    module_count: usize,
    mirror: mirrormod.MirrorOutcome,
    project_changed: bool,
    warnings: []const []const u8,
};

pub fn build(ctx: *Ctx, cfg: Config) !BuildOutcome {
    const files = try treemod.collectFiles(ctx, cfg);
    const placements = try treemod.resolve(ctx, files, cfg);

    const mirror = try mirrormod.syncMirror(ctx, cfg, placements);
    const project_changed = try treemod.writeProjectFile(ctx, cfg);

    return .{
        .module_count = placements.len,
        .mirror = mirror,
        .project_changed = project_changed,
        .warnings = mirror.warnings,
    };
}
