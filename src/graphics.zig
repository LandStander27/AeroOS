const std = @import("std");
const uefi = std.os.uefi;

const heap = @import("heap.zig");
const bs = @import("boot_services.zig");

var gop: ?*uefi.protocol.GraphicsOutput = null;
var inited = false;

const io = @import("io.zig");
const log = @import("log.zig");
const fb = @import("fb.zig");

var fb_base: [*]u32 = undefined;

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

	pub fn from_raw(raw: u32) Color {
		return Color{ .r = raw >> 16, .g = (raw >> 8) & 0xFF, .b = raw & 0xFF };
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
	const boot_services = try bs.init();
	log.new_task("GraphicsOutput");
	errdefer log.error_task();
	// try @import("time.zig").sleepms(350);
	if (boot_services.locateProtocol(&uefi.protocol.GraphicsOutput.guid, null, @ptrCast(&gop)) != uefi.Status.Success) {
		return error.NoGOPFound;
	}
	if (gop.?.mode.max_mode == 0) {
		return error.NoSupportedResolutions;
	}
	log.finish_task();
	// try @import("time.zig").sleepms(350);
	inited = true;
	fb_base = @ptrFromInt(gop.?.mode.frame_buffer_base);
}

pub fn draw_pixel(x: u64, y: u64, color: Color) void {
	if (x >= gop.?.mode.info.horizontal_resolution or y >= gop.?.mode.info.vertical_resolution or x < 0 or y < 0) {
		return;
	}
	fb_base[x + y * gop.?.mode.info.pixels_per_scan_line] = color.to_raw();
}

pub fn get_pixel(x: u64, y: u64) Color {
	if (x >= gop.?.mode.info.horizontal_resolution or y >= gop.?.mode.info.vertical_resolution or x < 0 or y < 0) {
		return Color{ .r = 0, .g = 0, .b = 0 };
	}
	return Color.from_raw(fb_base[x + y * gop.?.mode.info.pixels_per_scan_line]);
}

const Direction = enum {
	Down,
	Up,
};

pub fn scroll(pixels: u64, direction: Direction) void {

	const current = current_resolution();

	switch (direction) {
		.Down => {
			for (0..current.height-pixels) |y| {
				for (0..current.width) |x| {
					draw_pixel(x, y, get_pixel(x, y+pixels));
					draw_pixel(x, y+pixels, Color{ .r = 0, .g = 0, .b = 0 });
				}
			}
		},
		.Up => {
			for (0..current.height-pixels) |y| {
				for (0..current.width) |x| {
					draw_pixel(x, y+pixels, get_pixel(x, y));
					draw_pixel(x, y, Color{ .r = 0, .g = 0, .b = 0 });
				}
			}
		},
	}
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

pub const State = struct {
	alloc: heap.Allocator,
	buf: []u32,
	inited: bool,

	pub fn init(alloc: heap.Allocator) !State {
		var buf = try alloc.alloc(u32, gop.?.mode.info.horizontal_resolution * gop.?.mode.info.vertical_resolution);
		errdefer alloc.free(buf);


		for (0..buf.len) |i| {
			buf[i] = fb_base[i];
		}

		return .{
			.alloc = alloc,
			.buf = buf,
			.inited = true
		};
	}

	pub fn load(self: *const State) void {

		for (0..self.buf.len) |i| {
			fb_base[i] = self.buf[i];
		}
	}

	pub fn deinit(self: *State) void {
		self.alloc.free(self.buf);
		self.inited = false;
	}

};

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

	pub fn load_state(self: *Framebuffer, state: State) void {
		for (0..self.framebuffer.len) |i| {
			const color = Color.from_raw(state.buf[i]);
			self.framebuffer[i] = color.to_gop();
		}
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
		self.clear_color(black);
	}

	pub fn clear_color(self: *Framebuffer, color: Color) void {
		const color_gop = color.to_gop();
		for (0..self.framebuffer.len) |i| {
			self.framebuffer[i] = color_gop;
		}
	}

	pub fn draw_pixel(self: *Framebuffer, x: u64, y: u64, color: Color) void {
		self.framebuffer[x + y * gop.?.mode.info.pixels_per_scan_line] = color.to_gop();
	}

	pub fn draw_char(self: *Framebuffer, c: u8, x: u64, y: u64, color: ?Color, bg_color: ?Color) void {
		for (fb.font[c], 0..) |row, i| {
			for (row, 0..) |pixel, j| {
				self.draw_pixel(x+fb.font_width+j, y+i, if (pixel) color orelse Color{ .r = 255, .g = 255, .b = 255 } else bg_color orelse Color{ .r = 0, .g = 0, .b = 0 });
			}
		}
	}

	pub fn draw_text(self: *Framebuffer, text: []const u8, x: u64, y: u64, color: ?Color, bg_color: ?Color) void {
		var x2 = x;
		var y2 = y;

		for (text) |c| {
			self.draw_char(c, x2, y2, color orelse Color{ .r = 255, .g = 255, .b = 255 }, bg_color);
			if (c == '\n') {
				y2 += fb.font_height;
				x2 = x;
			} else {
				x2 += fb.font_width;
			}
		}
	}

	pub fn draw_text_centered(self: *Framebuffer, text: []const u8, x: u64, y: u64, color: ?Color, bg_color: ?Color) void {
		var each_line = std.mem.splitSequence(u8, text, "\n");

		var y2 = y;

		while (each_line.next()) |line| {
			self.draw_text(line, x - (line.len*fb.font_width)/2, y2 + fb.font_width, color orelse Color{ .r = 255, .g = 255, .b = 255 }, bg_color);
			y2 += fb.font_height;
		}
	}

	pub fn draw_textf(self: *Framebuffer, comptime format: []const u8, args: anytype, x: u64, y: u64, color: ?Color, bg_color: ?Color) !void {
		const msg = try io.alloc_print(self.alloc, format, args);
		defer self.alloc.free(msg);
		self.draw_text(msg, x, y, color orelse Color{ .r = 255, .g = 255, .b = 255 }, bg_color);
	}

	pub fn draw_text_centeredf(self: *Framebuffer, comptime format: []const u8, args: anytype, x: u64, y: u64, color: ?Color, bg_color: ?Color) !void {
		const msg = try io.alloc_print(self.alloc, format, args);
		defer self.alloc.free(msg);
		self.draw_text_centered(msg, x, y, color orelse Color{ .r = 255, .g = 255, .b = 255 }, bg_color);
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

	const boot_services = try bs.init();

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
