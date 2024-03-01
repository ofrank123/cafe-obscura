const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
        },
    });
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addSharedLibrary(.{
        .name = "main",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    lib.export_memory = true;
    lib.rdynamic = true;

    const install_step = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .{ .custom = "./" } },
    });

    b.getInstallStep().dependOn(&install_step.step);
}
