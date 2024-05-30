const std = @import("std");
const uefi = std.os.uefi;

const log = @import("log.zig");

var spp: ?*uefi.protocol.SimplePointer = null;

var pos: [2]i32 = .{ 0, 0 };

pub fn init() !void {

	log.new_task("SimplePointerProtocol");
	errdefer log.error_task();

	if (uefi.system_table.boot_services.?.locateProtocol(&uefi.protocol.SimplePointer.guid, null, @ptrCast(&spp)) != uefi.Status.Success) {
		return error.NoSPPFound;
	}
	log.finish_task();

}

pub fn get_position() ![2]i32 {

	var state: uefi.protocol.SimplePointer.State = undefined;
	if (spp.?.getState(&state) != uefi.Status.Success) {
		return error.CouldNotGetState;
	}

	pos[0] += state.relative_movement_x;
	pos[1] += state.relative_movement_y;

	const clone = [2]i32{ pos[0], pos[1] };
	return clone;

}
