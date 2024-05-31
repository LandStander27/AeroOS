const std = @import("std");
const uefi = std.os.uefi;

const heap = @import("heap.zig");

var gop: ?*uefi.protocol.GraphicsOutput = null;
var inited = false;

const log = @import("log.zig");

pub const VideoMode = struct {
	_index: u32,

	width: u32,
	height: u32,
};

pub const Color = struct {
	r: u32,
	g: u32,
	b: u32,

	pub fn to_raw(self: *const Color) u32 {
		return (self.r << 16) + (self.g << 8) + self.b;
	}

	pub fn to_gop(self: *const Color) uefi.protocol.GraphicsOutput.BltPixel {
		return uefi.protocol.GraphicsOutput.BltPixel{ .red = @intCast(self.r), .green = @intCast(self.g), .blue = @intCast(self.b) };
	}

};

pub fn current_resolution() VideoMode {
	return VideoMode{ ._index = 0, .width = gop.?.mode.info.horizontal_resolution, .height = gop.?.mode.info.vertical_resolution };
}

pub fn set_videomode(mode: VideoMode) !void {
	if (gop.?.setMode(mode._index) != uefi.Status.Success) {
		return error.CouldNotSetMode;
	}
}

pub fn has_inited() bool {
	return inited;
}

pub fn init() !void {
	const boot_services = uefi.system_table.boot_services.?;
	log.new_task("GraphicsOutput");
	errdefer log.error_task();
	// try @import("time.zig").sleepms(350);
	if (boot_services.locateProtocol(&uefi.protocol.GraphicsOutput.guid, null, @ptrCast(&gop)) != uefi.Status.Success) {
		return error.NoGOPFound;
	}
	log.finish_task();
	// try @import("time.zig").sleepms(350);
	inited = true;
}

pub fn draw_pixel(x: u64, y: u64, color: Color) void {
	if (x >= gop.?.mode.info.horizontal_resolution or y >= gop.?.mode.info.vertical_resolution or x < 0 or y < 0) {
		return;
	}
	var fb: [*]u32 = @ptrFromInt(gop.?.mode.frame_buffer_base);
	fb[x + y * gop.?.mode.info.pixels_per_scan_line] = color.to_raw();
}

pub fn draw_rectangle(x: u64, y: u64, width: u64, height: u64, color: Color) void {
	var c = [1]uefi.protocol.GraphicsOutput.BltPixel{ color.to_gop() };
	_ = gop.?.blt(&c, uefi.protocol.GraphicsOutput.BltOperation.BltVideoFill, 0, 0, x, y, width, height, 0);
	// if (res != uefi.Status.Success) {
	// 	return res.err();
	// }
}

pub fn clear() void {
	draw_rectangle(0, 0, gop.?.mode.info.horizontal_resolution, gop.?.mode.info.vertical_resolution, Color{ .r = 0, .g = 0, .b = 0 });
}

pub fn save_state(alloc: heap.Allocator) ![]u32 {
	var buf = try alloc.alloc(u32, gop.?.mode.info.horizontal_resolution * gop.?.mode.info.vertical_resolution);
	errdefer alloc.free(buf);

	const fb: [*]u32 = @ptrFromInt(gop.?.mode.frame_buffer_base);

	for (0..buf.len) |i| {
		buf[i] = fb[i];
	}

	return buf;
}

pub fn load_state(buf: []u32) void {
	const fb: [*]u32 = @ptrFromInt(gop.?.mode.frame_buffer_base);

	for (0..buf.len) |i| {
		fb[i] = buf[i];
	}
}

pub const Framebuffer = struct {
	framebuffer: []uefi.protocol.GraphicsOutput.BltPixel,
	alloc: heap.Allocator,

	pub fn init(allocator: heap.Allocator) !Framebuffer {
		var self = Framebuffer{
			.framebuffer = undefined, .alloc = allocator
		};
		self.framebuffer = try self.alloc.alloc(uefi.protocol.GraphicsOutput.BltPixel, gop.?.mode.info.horizontal_resolution * gop.?.mode.info.vertical_resolution);
		errdefer self.alloc.free(self.framebuffer);
		const black = Color{ .r = 0, .g = 0, .b = 0 };
		for (0..self.framebuffer.len) |i| {
			self.framebuffer[i] = black.to_gop();
		}
		return self;
	}

	pub fn update(self: *Framebuffer) !void {
		const res = gop.?.blt(self.framebuffer.ptr, uefi.protocol.GraphicsOutput.BltOperation.BltBufferToVideo, 0, 0, 0, 0, gop.?.mode.info.horizontal_resolution, gop.?.mode.info.vertical_resolution, 0);
		if (res != uefi.Status.Success) {
			try res.err();
		}
		// const black = Color{ .r = 0, .g = 0, .b = 0 };
		// const black_gop = black.to_gop();
		// for (0..self.framebuffer.len) |i| {
		// 	self.framebuffer[i] = black_gop;
		// }
	}

	pub fn clear(self: *Framebuffer) void {
		const black = Color{ .r = 0, .g = 0, .b = 0 };
		const black_gop = black.to_gop();
		for (0..self.framebuffer.len) |i| {
			self.framebuffer[i] = black_gop;
		}
	}

	pub fn draw_pixel(self: *Framebuffer, x: u64, y: u64, color: Color) void {
		self.framebuffer[x + y * gop.?.mode.info.pixels_per_scan_line] = color.to_gop();
	}

	pub fn draw_rectangle(self: *Framebuffer, x: u64, y: u64, width: u64, height: u64, color: Color) void {
		for (x..x+width) |i| {
			for (y..y+height) |j| {
				self.draw_pixel(i, j, color);
			}
		}
	}

	pub fn deinit(self: *const Framebuffer) void {
		self.alloc.free(self.framebuffer);
	}
};

/// Returns a list of available resolutions.
/// Caller owns and must free memory.
pub fn get_resolutions(allocator: heap.Allocator) ![]VideoMode {

	const boot_services = uefi.system_table.boot_services.?;

	if (boot_services.locateProtocol(&uefi.protocol.GraphicsOutput.guid, null, @ptrCast(&gop)) == uefi.Status.Success) {

		var resolutions = try allocator.alloc(VideoMode, gop.?.mode.max_mode);
		errdefer allocator.free(resolutions);

		for (0..gop.?.mode.max_mode) |i| {
			var info: *uefi.protocol.GraphicsOutput.Mode.Info = undefined;
			var info_size: usize = undefined;
			if (gop.?.queryMode(@intCast(i), &info_size, &info) != uefi.Status.Success) {
				return error.CouldNotQueryMode;
			}
			resolutions[i] = .{
				._index = @intCast(i),
				.width = info.horizontal_resolution,
				.height = info.vertical_resolution,
			};
			// try resolutions.append(.{ .width = info.horizontal_resolution, .height = info.vertical_resolution, .index = i });
		}

		return resolutions;

		// try println("Current Mode: {d}x{d}", .{gop.?.mode.info.horizontal_resolution, gop.?.mode.info.vertical_resolution});

	} else {
		return error.NoGOPFound;
	}

}
