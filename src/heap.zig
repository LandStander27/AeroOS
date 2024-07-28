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

	pub fn alloc(self: *const Allocator, comptime T: type, count: usize) ![]T {
		// if (count == 0) return &[0]T{};
		// var memory: [*]align(8) T = undefined;
		// const res = (try bs.init()).allocatePool(uefi.tables.MemoryType.BootServicesData, count * @sizeOf(T), @ptrCast(&memory));
		// if (res != uefi.Status.Success) {
		// 	try res.err();
		// }
		// amount += 1;
		// return memory[0..count];
		return self.alloc_type(T, count, uefi.tables.MemoryType.BootServicesData);
	}

	pub fn alloc_type(_: *const Allocator, comptime T: type, count: usize, memory_type: uefi.tables.MemoryType) ![]T {
		// if (count == 0) return &[0]T{};
		var memory: [*]align(8) T = undefined;
		const res = (try bs.init()).allocatePool(memory_type, count * @sizeOf(T), @ptrCast(&memory));
		if (res != uefi.Status.Success) {
			try res.err();
		}
		amount += 1;
		return memory[0..count];
	}

	// pub fn alloc_addr(self: *const Allocator, comptime T: type, addr: usize, count: usize) !void {
	// 	try self.alloc_addr_type(T, addr, count, uefi.tables.MemoryType.BootServicesData);
	// }

	// pub fn alloc_addr_type(_: *const Allocator, comptime T: type, addr: usize, count: usize, memory_type: uefi.tables.MemoryType) !void {
	// 	const res = (try bs.init()).allocatePool(memory_type, count * @sizeOf(T), @ptrCast(@constCast(&addr)));
	// 	if (res != uefi.Status.Success) {
	// 		try res.err();
	// 	}
	// 	amount += 1;
	// }

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
		}).freePool(@alignCast(@ptrCast(@constCast(memory.ptr))));
		if (res != uefi.Status.Success) {
			if (graphics.has_inited()) {
				fb.println("Unable to free memory", .{}) catch {
					puts("Unable to free memory");
				};
			} else {
				@import("io.zig").println("Unable to free memory: {s}", .{ @tagName(res) }) catch {
					puts("Unable to free memory");
				};
			}
			return;
		}
		amount -= 1;
	}

	pub fn create(self: *const Allocator, comptime T: type) !T {
		const data: []u8 = try self.alloc(u8, @sizeOf(T));
		const ptr: *T = @ptrCast(data.ptr);
		return ptr.*;
	}

	pub fn create_addr(_: *const Allocator, comptime T: type, addr: usize) !void {

		var memory: [*]T = @ptrFromInt(addr);
		const res = (try bs.init()).allocatePool(uefi.tables.MemoryType.BootServicesData, @sizeOf(T), @ptrCast(&memory));
		if (res != uefi.Status.Success) {
			try res.err();
		}
		amount += 1;

	}

	// pub fn create_addr(self: *const Allocator, comptime T: type, addr: usize) !void {
	// 	// const data: []u8 = try self.alloc(u8, @sizeOf(T));
	// 	// const ptr: *T = @ptrCast(data.ptr);
	// 	// return ptr.*;
	// 	try self.alloc_addr(T, addr, 1);
	// }

	pub fn destroy(self: *const Allocator, ptr: anytype) void {
		const data: [*]const u8 = @ptrCast(ptr);
		self.free(data[0..@sizeOf(@TypeOf(ptr.*))]);
	}

	// pub fn deinit(self: *const Allocator) void {
	// 	if (self.amount > 0) {
	// 		@panic("Memory leak");
	// 	}
	// }
};
