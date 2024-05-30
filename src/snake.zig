const std = @import("std");

const io = @import("io.zig");

const time = @import("time.zig");
const sleepms = time.sleepms;

const heap = @import("heap.zig");
const graphics = @import("graphics.zig");

const rng = @import("rand.zig");
const ArrayList = @import("array.zig").ArrayList;

const square_size = 20;

const Square = struct {
	x: u64,
	y: u64,

	pub fn draw(self: *Square, buffer: *graphics.Framebuffer) void {
		buffer.draw_rectangle(self.x+1, self.y+1, square_size-2, square_size-2, graphics.Color{ .r = 0, .g = 255, .b = 0 });
	}

};

pub fn start(alloc: heap.Allocator) !void {

	var buffer = try graphics.Framebuffer.init(alloc);
	defer buffer.deinit();
	const res = graphics.current_resolution();
	_ = res;

	var snake = try ArrayList(Square).init(alloc);
	defer snake.deinit();

	try snake.append(Square{ .x = 100, .y = 100 });
	try snake.append(Square{ .x = 120, .y = 100 });
	try snake.append(Square{ .x = 120, .y = 120 });

	var running = true;

	while (running) {

		const key = try io.getkey();
		if (key) |k| {
			switch (k.scancode) {
				23 => running = false,
				else => {},
			}
		}

		buffer.clear();

		for (0..snake.items.len) |i| {
			snake.items[i].draw(&buffer);
		}
		snake.remove(0);
		try snake.append(Square{ .x = snake.items[1].x+square_size, .y = 120 });

		try buffer.update();
		try sleepms(50);
	}

}
