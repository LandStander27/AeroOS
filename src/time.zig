const std = @import("std");

pub fn sleepms(ms: u64) !void {
	const boot_services = std.os.uefi.system_table.boot_services.?;
	const res = boot_services.stall(ms * 1000);
	if (res != .Success) {
		try res.err();
	}
}
