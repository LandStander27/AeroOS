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

pub fn init_gop() !void {
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

pub fn draw_pixel(x: u64, y: u64, color: Color) !void {
	var fb: [*]u32 = @ptrFromInt(gop.?.mode.frame_buffer_base);
	fb[x + y * gop.?.mode.info.pixels_per_scan_line] = color.to_raw();
}

pub fn draw_rectangle(x: u64, y: u64, width: u64, height: u64, color: Color) !void {
	var c = [1]uefi.protocol.GraphicsOutput.BltPixel{ color.to_gop() };
	const res = gop.?.blt(&c, uefi.protocol.GraphicsOutput.BltOperation.BltVideoFill, 0, 0, x, y, width, height, 0);
	if (res != uefi.Status.Success) {
		return res.err();
	}
}

/// Returns a list of available resolutions.
/// Caller owns and must free memory.
pub fn get_resolutions(alloc: heap.Allocator) ![]VideoMode {

	const boot_services = uefi.system_table.boot_services.?;

	if (boot_services.locateProtocol(&uefi.protocol.GraphicsOutput.guid, null, @ptrCast(&gop)) == uefi.Status.Success) {

		var resolutions = try alloc.alloc(VideoMode, gop.?.mode.max_mode);
		errdefer alloc.free(resolutions);

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
