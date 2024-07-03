const std = @import("std");

const io = @import("io.zig");

const time = @import("time.zig");
const sleepms = time.sleepms;

const heap = @import("heap.zig");
const graphics = @import("graphics.zig");
const Color = graphics.Color;

const mouse = @import("mouse.zig");

pub fn start(alloc: heap.Allocator) !void {

	var frame = try graphics.Framebuffer.init(alloc);
	defer frame.deinit();
	const res = graphics.current_resolution();


	while (true) {
		const pos = try mouse.get_position();
		try frame.draw_text_centeredf("{d}, {d}", .{pos[0], pos[1]}, res.width/2, res.height/2, null, null);
		try frame.update();
		try sleepms(100);
	}

}
