const uefi = @import("std").os.uefi;

var exists: bool = true;

pub fn init() !*uefi.tables.BootServices {
	if (uefi.system_table.boot_services == null or !exists) {
		exists = false;
		return error.BootServicesNotFound;
	}
	return uefi.system_table.boot_services.?;
}

pub fn hardware_reboot() noreturn {
	uefi.system_table.runtime_services.resetSystem(uefi.tables.ResetType.ResetCold, uefi.Status.Success, 0, null);
}

pub fn software_reboot() noreturn {
	uefi.system_table.runtime_services.resetSystem(uefi.tables.ResetType.ResetWarm, uefi.Status.Success, 0, null);
}

pub fn shutdown() noreturn {
	uefi.system_table.runtime_services.resetSystem(uefi.tables.ResetType.ResetShutdown, uefi.Status.Success, 0, null);
}

pub fn disable_watchdog() !void {
	const bs = try init();
	const res = bs.setWatchdogTimer(0, 0, 0, null);
	if (res != .Success) {
		try res.err();
	}
}

pub fn exit_services() !void {
	var memory_map: [*]uefi.tables.MemoryDescriptor = undefined;
	var memory_map_size: usize = 0;
	var memory_map_key: usize = undefined;
	var descriptor_size: usize = undefined;
	var descriptor_version: u32 = undefined;
	while (uefi.Status.BufferTooSmall == uefi.system_table.boot_services.?.getMemoryMap(&memory_map_size, memory_map, &memory_map_key, &descriptor_size, &descriptor_version)) {
		if (uefi.Status.Success != uefi.system_table.boot_services.?.allocatePool(uefi.tables.MemoryType.BootServicesData, memory_map_size, @ptrCast(&memory_map))) {
			return error.CouldNotAllocateMemoryMap;
		}
	}

	if (uefi.system_table.boot_services.?.exitBootServices(uefi.handle, memory_map_key) != uefi.Status.Success) {
		return error.CouldNotExitBootServices;
	}

	exists = false;
}