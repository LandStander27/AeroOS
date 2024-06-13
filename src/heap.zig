const uefi = @import("std").os.uefi;

const bs = @import("boot_services.zig");

const println = @import("io.zig").println;
const puts = @import("io.zig").puts;
const graphics = @import("graphics.zig");
const fb = @import("fb.zig");

pub var amount: usize = 0;

pub const Allocator = struct {

	// amount: usize = 0,

	pub fn init() Allocator {
		return Allocator{};
	}

	pub fn alloc(_: *const Allocator, comptime T: type, count: usize) ![]T {
		var memory: [*]align(8) T = undefined;
		const res = (try bs.init()).allocatePool(uefi.tables.MemoryType.BootServicesData, count * @sizeOf(T), @ptrCast(&memory));
		if (res != uefi.Status.Success) {
			try res.err();
		}
		amount += 1;
		return memory[0..count];
	}

	pub fn realloc(self: *const Allocator, comptime T: type, old_memory: []T, new_count: usize) ![]T {
		const new_memory: []T = try self.alloc(T, new_count);
		const size = blk: {
			if (old_memory.len < new_memory.len) {
				break :blk old_memory.len;
			}
			break :blk new_memory.len;
		};
		(try bs.init()).copyMem(@ptrCast(new_memory.ptr), @ptrCast(old_memory.ptr), size * @sizeOf(T));
		self.free(old_memory);
		return new_memory;
	}

	pub fn free(_: *const Allocator, memory: anytype) void {
		const res = (bs.init() catch {
			@panic("Cannot free without boot services");
		}).freePool(@alignCast(@ptrCast(memory.ptr)));
		if (res != uefi.Status.Success) {
			if (graphics.has_inited()) {
				fb.println("Unable to free memory", .{}) catch {
					puts("Unable to free memory");
				};
			} else {
				puts("Unable to free memory");
			}
			return;
		}
		amount -= 1;
	}

	// pub fn deinit(self: *const Allocator) void {
	// 	if (self.amount > 0) {
	// 		@panic("Memory leak");
	// 	}
	// }
};
