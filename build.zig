const std = @import("std");

const ReleaseTarget = struct {
    name: []const u8,
    query: std.Target.Query,
};

const release_targets = [_]ReleaseTarget{
    .{ .name = "gentree-windows-x86_64", .query = .{ .cpu_arch = .x86_64, .os_tag = .windows } },
    .{ .name = "gentree-linux-x86_64", .query = .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl } },
    .{ .name = "gentree-linux-aarch64", .query = .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .musl } },
    .{ .name = "gentree-macos-x86_64", .query = .{ .cpu_arch = .x86_64, .os_tag = .macos } },
    .{ .name = "gentree-macos-aarch64", .query = .{ .cpu_arch = .aarch64, .os_tag = .macos } },
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "gentree",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run gentree");
    run_step.dependOn(&run_cmd.step);

    const release_step = b.step("release", "Cross-compile release binaries for every platform");
    for (release_targets) |entry| {
        const release_exe = b.addExecutable(.{
            .name = entry.name,
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = b.resolveTargetQuery(entry.query),
                .optimize = .ReleaseSmall,
            }),
        });
        const install = b.addInstallArtifact(release_exe, .{
            .dest_dir = .{ .override = .{ .custom = "release" } },
        });
        release_step.dependOn(&install.step);
    }
}
