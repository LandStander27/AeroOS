const std = @import("std");
const uefi = std.os.uefi;

const bs = @import("boot_services.zig");

const log = @import("log.zig");

var rng: ?*uefi.protocol.Rng = null;
var inited = false;

pub fn has_inited() bool {
	return inited;
}

pub const RNGMethod = enum {
	Hardware,
	Software,
	NonRandom,
};

pub fn get_mode() RNGMethod {

	if (rng == null) {
		if (original_backup_seed == 0) {
			return .NonRandom;
		}
		return .Software;
	}

	return .Hardware;

}

pub fn init() !void {

	log.new_task("HardwareRNG");
	errdefer log.error_task();
	const boot_services = try bs.init();

	if (boot_services.locateProtocol(&uefi.protocol.Rng.guid, null, @ptrCast(&rng)) != uefi.Status.Success) {
		// return error.NoRNGFound;
		rng = null;
		log.error_task();
		log.new_task("SoftwareRNG");

		const t = @import("time.zig").Time.now() catch blk: {
			log.error_task();
			log.new_task("NonRandomRNG");
			break :blk null;
		};

		backup_seed = if (t != null) t.?.unix() else 0;
	}
	log.finish_task();

	original_backup_seed = backup_seed;
	inited = true;

}

pub fn random(low: u64, high: u64) !u64 {

	if (low == high) {
		return low;
	}

	if (low > high) {
		return error.InvalidRange;
	}

	var value: u64 = 0;
	if (rng != null) {
		if (rng.?.getRNG(null, @sizeOf(u64), @ptrCast(&value)) != uefi.Status.Success) {
			return error.CouldNotGenerateNumber;
		}
	} else {
		value = backup_rng();
	}

	return (value % (high - low)) + low;
}

var original_backup_seed: u64 = 0;
var backup_seed: u64 = 0;

fn backup_rng() u64 {
	backup_seed = (1103515245 * backup_seed + 12345) % std.math.pow(u64, 2, 31);
	return backup_seed;
}
