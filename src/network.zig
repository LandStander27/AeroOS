const std = @import("std");
const uefi = std.os.uefi;

const heap = @import("heap.zig");
const log = @import("log.zig");
const fb = @import("fb.zig");

var network: ?*uefi.protocol.SimpleNetwork = null;

pub fn init() !void {
	const boot_services = uefi.system_table.boot_services.?;

	log.new_task("SimpleNetwork");
	errdefer log.error_task();

	if (boot_services.locateProtocol(&uefi.protocol.SimpleNetwork.guid, null, @ptrCast(&network)) != uefi.Status.Success) {
		return error.NoNetworkProtocol;
	}

	if (network.?.initialize(8, 8) != uefi.Status.Success) {
		return error.NoNetwork;
	}

	log.finish_task();

}