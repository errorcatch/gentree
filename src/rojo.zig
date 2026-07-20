const std = @import("std");
const report = @import("report.zig");
const Ctx = report.Ctx;

pub const RojoStatus = struct {
    installed: bool,
    version: []const u8,
};

pub const ROJO_MISSING =
    \\Rojo was not found on PATH.
    \\
    \\  Install it with Rokit (recommended, version-pinned per project):
    \\    rokit init      # if the project has no rokit.toml yet
    \\    rokit add rojo
    \\
    \\  Or install it globally:
    \\    cargo install rojo
    \\
    \\Then run `gentree init` again.
;

pub fn detectRojo(ctx: *Ctx) RojoStatus {
    const result = std.process.run(ctx.gpa, ctx.io, .{
        .argv = &.{ "rojo", "--version" },
        .cwd = .{ .path = ctx.root },
        .environ_map = ctx.env,
    }) catch return .{ .installed = false, .version = "" };
    defer ctx.gpa.free(result.stdout);
    defer ctx.gpa.free(result.stderr);

    switch (result.term) {
        .exited => |code| {
            if (code != 0) return .{ .installed = false, .version = "" };
        },
        else => return .{ .installed = false, .version = "" },
    }

    const trimmed = std.mem.trim(u8, result.stdout, " \t\r\n");
    return .{ .installed = true, .version = ctx.arena.dupe(u8, trimmed) catch trimmed };
}
