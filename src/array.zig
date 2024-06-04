const std = @import("std");
const uefi = std.os.uefi;
const heap = @import("heap.zig");

// std.ArrayList;

pub fn ArrayList(comptime T: type) type {
	return struct {

		const Self = @This();

		items: []T,
		data: []T,
		len: usize,
		capacity: usize,
		allocator: heap.Allocator,
		attached: bool = true,

		pub fn init(alloc: heap.Allocator) !Self {
			var data = try alloc.alloc(T, 16);
			return Self {
				.data = data,
				.items = data[0..0],
				.len = 0,
				.capacity = 16,
				.allocator = alloc
			};
		}

		pub fn detach(self: *Self) ![]T {
			const d: []T = try self.allocator.alloc(T, self.len);
			std.mem.copyForwards(T, d, self.items);
			self.deinit();
			return d;
		}

		pub fn deinit(self: *Self) void {
			self.attached = false;
			self.allocator.free(self.data);
		}

		pub fn remove(self: *Self, index: usize) void {
			for (index..self.len-1) |i| {
				self.data[i] = self.data[i+1];
			}
			self.items = self.data[0..self.len - 1];
			self.len -= 1;
		}

		fn grow(self: *Self) !void {
			if (self.len >= self.capacity) {
				self.data = try self.allocator.realloc(T, self.data, self.capacity * 2);
				self.capacity *= 2;
			}
		}

		pub fn insert(self: *Self, index: usize, item: T) !void {
			try self.grow();

			var i = self.len;
			while (i > index) : (i -= 1) {
				self.data[i] = self.data[i - 1];
			}
			self.data[index] = item;
			self.items = self.data[0..self.len + 1];
			self.len += 1;

		}

		pub fn last(self: *Self) ?*T {
			if (self.len == 0) {
				return null;
			}
			return &self.data[self.len - 1];
		}

		pub fn append(self: *Self, item: T) !void {
			try self.grow();
			self.data[self.len] = item;
			self.items = self.data[0..self.len + 1];
			self.len += 1;
		}

		pub fn append_slice(self: *Self, item: []const T) !void {
			for (item) |i| {
				try self.append(i);
			}
		}

		pub fn clear(self: *Self) void {
			self.len = 0;
			self.items = self.data[0..0];
		}

		pub fn reset(self: *Self) !void {
			self.data = try self.allocator.realloc(T, self.data, 16);
			self.capacity = 16;
			self.clear();
		}

	};
}
