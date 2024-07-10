const std = @import("std");
const uefi = std.os.uefi;

const heap = @import("heap.zig");
const bs = @import("boot_services.zig");
const log = @import("log.zig");
const fb = @import("fb.zig");

var network: ?*uefi.protocol.SimpleNetwork = null;

pub fn init() !void {
	const boot_services = try bs.init();

	log.new_task("SimpleNetwork");
	errdefer log.error_task();

	if (boot_services.locateProtocol(&uefi.protocol.SimpleNetwork.guid, null, @ptrCast(&network)) != uefi.Status.Success) {
		return error.NoNetworkProtocol;
	}

	if (network.?.initialize(8, 8) != uefi.Status.Success) {
		return error.NoNetwork;
	}

	if (network.?.start() != uefi.Status.Success) {
		return error.CouldNotStart;
	}

	log.finish_task();

}