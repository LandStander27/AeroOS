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

const Key = enum(u16) {
	Escape = 23,
	Down = 2,
	Up = 1,
	Left = 4,
	Right = 3,
};

const Direction = enum {
	Up,
	Down,
	Left,
	Right,
};

pub fn start(alloc: heap.Allocator) !void {

	var frame = try graphics.Framebuffer.init(alloc);
	defer frame.deinit();
	const res = graphics.current_resolution();
	_ = res;

	var keypresses = try ArrayList(u8).init(alloc);
	defer keypresses.deinit();

	var snake = try ArrayList(Square).init(alloc);
	defer snake.deinit();

	try snake.append(Square{ .x = 0, .y = 0 });
	try snake.append(Square{ .x = square_size, .y = 0 });

	var current_direction = Direction.Right;

	var running = true;

	while (running) {

		if (keypresses.items.len >= 128) {
			try keypresses.reset();
		} else if (std.mem.endsWith(u8, keypresses.items, "panic")) {
			return error.UserRequestedPanic;
		}

		const key = try io.getkey();
		if (key) |k| {
			try keypresses.append(k.unicode.convert());

			switch (k.scancode) {
				@intFromEnum(Key.Escape) => running = false,
				@intFromEnum(Key.Down) => current_direction = if (current_direction != Direction.Up) Direction.Down else current_direction,
				@intFromEnum(Key.Up) => current_direction = if (current_direction != Direction.Down) Direction.Up else current_direction,
				@intFromEnum(Key.Left) => current_direction = if (current_direction != Direction.Right) Direction.Left else current_direction,
				@intFromEnum(Key.Right) => current_direction = if (current_direction != Direction.Left) Direction.Right else current_direction,
				else => {},
			}
		}

		frame.clear();

		for (0..snake.items.len) |i| {
			snake.items[i].draw(&frame);
		}
		snake.remove(0);
		var new_square = Square{ .x = snake.items[snake.items.len-1].x, .y = snake.items[snake.items.len-1].y };
		switch (current_direction) {
			Direction.Up => new_square.y -= square_size,
			Direction.Down => new_square.y += square_size,
			Direction.Left => new_square.x -= square_size,
			Direction.Right => new_square.x += square_size,
		}
		try snake.append(new_square);

		try frame.update();
		try sleepms(100);
	}

}
