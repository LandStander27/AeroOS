const std = @import("std");

const io = @import("io.zig");

const time = @import("time.zig");
const sleepms = time.sleepms;

const heap = @import("heap.zig");
const graphics = @import("graphics.zig");

const rng = @import("rand.zig");
const ArrayList = @import("array.zig").ArrayList;

const square_size: u64 = 20;

const Type = enum {
	Snake,
	Food,
};

const Square = struct {
	x: u64,
	y: u64,
	typ: Type = .Snake,

	pub fn draw(self: *Square, buffer: *graphics.Framebuffer) void {
		buffer.draw_rectangle(self.x+1, self.y+1, square_size-2, square_size-2, graphics.Color{ .r = if (self.typ == .Food) 255 else 0, .g = if (self.typ == .Snake) 255 else 0, .b = 0 });
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

	var keypresses = try ArrayList(u8).init(alloc);
	defer keypresses.deinit();

	var food = try ArrayList(Square).init(alloc);
	defer food.deinit();

	const rows = res.height / square_size;
	const cols = res.width / square_size;

	try food.append(Square{ .x = (try rng.random(0, cols))*square_size, .y = (try rng.random(0, rows))*square_size, .typ = .Food });
	try food.append(Square{ .x = (try rng.random(0, cols))*square_size, .y = (try rng.random(0, rows))*square_size, .typ = .Food });

	var snake = try ArrayList(Square).init(alloc);
	defer snake.deinit();

	try snake.append(Square{ .x = 0, .y = 0 });
	try snake.append(Square{ .x = square_size, .y = 0 });

	var current_direction = Direction.Right;

	var running = true;

	while (running) {

		if (keypresses.items.len >= 128) {
			try keypresses.reset();
		} else if (std.mem.endsWith(u8, keypresses.items, "panic123")) {
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

		snake.remove(0);
		var new_square = Square{ .x = snake.last().?.x, .y = snake.last().?.y };
		switch (current_direction) {
			Direction.Up => new_square.y -= square_size,
			Direction.Down => new_square.y += square_size,
			Direction.Left => new_square.x -= square_size,
			Direction.Right => new_square.x += square_size,
		}
		try snake.append(new_square);

		for (food.items, 0..) |apple, i| {
			if (snake.last().?.x == apple.x and snake.last().?.y == apple.y) {
				food.remove(i);
				try food.append(Square{ .x = (try rng.random(0, cols))*square_size, .y = (try rng.random(0, rows))*square_size, .typ = .Food });
				try snake.insert(0, Square{ .x = snake.items[0].x, .y = snake.items[0].y });
				break;
			}
		}

		frame.clear();

		for (0..snake.items.len) |i| {
			snake.items[i].draw(&frame);
		}

		for (0..food.items.len) |i| {
			food.items[i].draw(&frame);
		}

		try frame.update();
		try sleepms(100);
	}

}
