const std = @import("std");
const uefi = std.os.uefi;
const log = @import("log.zig");

var rng: ?*uefi.protocol.Rng = null;
var inited = false;

pub fn has_inited() bool {
	return inited;
}

pub fn init() !void {

	log.new_task("Rng");
	errdefer log.error_task();
	const boot_services = uefi.system_table.boot_services.?;

	if (boot_services.locateProtocol(&uefi.protocol.Rng.guid, null, @ptrCast(&rng)) != uefi.Status.Success) {
		return error.NoRNGFound;
	}
	log.finish_task();

	inited = true;

}

pub fn random(low: u64, high: u64) !u64 {
	var value: u64 = 0;
	if (rng.?.getRNG(null, @sizeOf(u64), @ptrCast(&value)) != uefi.Status.Success) {
		return error.CouldNotGenerateNumber;
	}

	return (value % (high - low)) + low;
}
