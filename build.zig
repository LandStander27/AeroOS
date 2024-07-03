const std = @import("std");
const Target = std.Target;
const CrossTarget = std.zig.CrossTarget;

pub fn build(b: *std.Build) void {
	const target = CrossTarget{ .cpu_arch = .x86_64, .os_tag = .uefi, .abi = .msvc };

	const optimize = b.standardOptimizeOption(.{});

	const exe = b.addExecutable(.{
		.name = "bootx64",
		.root_source_file = b.path("src/main.zig"),
		.target = b.resolveTargetQuery(target),
		.optimize = optimize,
	});

	const target_output = b.addInstallArtifact(exe, .{
		.dest_dir = .{
			.override = .{
				.custom = "../bin/EFI/BOOT",
			},
		},
	});

	b.getInstallStep().dependOn(&target_output.step);

	b.installArtifact(exe);

	const run_cmd = b.addRunArtifact(exe);

	run_cmd.step.dependOn(b.getInstallStep());

	if (b.args) |args| {
		run_cmd.addArgs(args);
	}

	const run_step = b.step("run", "Run the app");
	run_step.dependOn(&run_cmd.step);
}
