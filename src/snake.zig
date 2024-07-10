const std = @import("std");

const io = @import("io.zig");

const time = @import("time.zig");
const sleepms = time.sleepms;

const heap = @import("heap.zig");
const graphics = @import("graphics.zig");
const fb = @import("fb.zig");
const Color = graphics.Color;

const rng = @import("rand.zig");
const ArrayList = @import("array.zig").ArrayList;

const square_size: u64 = 20;

const Type = enum {
	Snake,
	Food,
};

const Square = struct {
	x: i64,
	y: i64,
	typ: Type = .Snake,

	pub fn draw(self: *Square, buffer: *graphics.Framebuffer) void {
		// buffer.draw_rectangle(self.x+1, self.y+1, square_size-2, square_size-2, Color{ .r = if (self.typ == .Food) 255 else 0, .g = if (self.typ == .Snake) 255 else 0, .b = 0 });
		self.draw_color(buffer, Color{ .r = if (self.typ == .Food) 255 else 0, .g = if (self.typ == .Snake) 255 else 0, .b = 0 });
	}

	pub fn draw_color(self: *Square, buffer: *graphics.Framebuffer, color: Color) void {
		if (self.x < 0 or self.y < 0) {
			return;
		}
		buffer.draw_rectangle(@intCast(self.x+1), @intCast(self.y+1), square_size-2, square_size-2, color);
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

// const fb.font = blk: {

// 	@setEvalBranchQuota(100000);

// 	const data = @embedFile("./assets/vga16.psf")[4..];
// 	var ret: [512][16][8]bool = undefined;

// 	for (&ret, 0..) |*char, i| {
// 		for (char, 0..) |*row, j| {
// 			for (row, 0..) |*pixel, k| {
// 				pixel.* = data[i * 16 + j] & 0b10000000 >> k != 0;
// 			}
// 		}
// 	}

// 	break :blk ret;

// };

// fn draw_char(frame: *graphics.Framebuffer, c: u8, x: u64, y: u64) void {
// 	for (fb.font[c], 0..) |row, i| {
// 		for (row, 0..) |pixel, j| {
// 			frame.draw_pixel(x+fb.font_width+j, y+i, if (pixel) Color{ .r = 255, .g = 255, .b = 255 } else Color{ .r = 0, .g = 0, .b = 0 });
// 		}
// 	}
// }

// fn draw_text(frame: *graphics.Framebuffer, text: []const u8, x: u64, y: u64) void {
// 	var x2 = x;
// 	var y2 = y;

// 	for (text) |c| {
// 		draw_char(frame, c, x2, y2);
// 		if (c == '\n') {
// 			y2 += 16;
// 			x2 = x;
// 		} else {
// 			x2 += fb.font_width;
// 		}
// 	}
// }

// fn draw_text_centered(frame: *graphics.Framebuffer, text: []const u8, x: u64, y: u64) void {
// 	draw_text(frame, text, x - text.len/2*8, y + 8);
// }

const starting_len = 2;

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

	try food.append(Square{ .x = @intCast((try rng.random(0, cols))*square_size), .y = @intCast((try rng.random(0, rows))*square_size), .typ = .Food });
	try food.append(Square{ .x = @intCast((try rng.random(0, cols))*square_size), .y = @intCast((try rng.random(0, rows))*square_size), .typ = .Food });

	var snake = try ArrayList(Square).init(alloc);
	defer snake.deinit();

	try snake.append(Square{ .x = 0, .y = 0 });

	for (0..starting_len) |_| {
		try snake.append(Square{ .x = snake.last().?.x + square_size, .y = 0 });
	}

	var current_direction = Direction.Right;

	var dead = false;
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

			if (@intFromEnum(Key.Escape) == k.scancode) {
				running = false;
			}

			if (!dead) {
				switch (k.scancode) {
					@intFromEnum(Key.Down) => current_direction = if (current_direction != Direction.Up) Direction.Down else current_direction,
					@intFromEnum(Key.Up) => current_direction = if (current_direction != Direction.Down) Direction.Up else current_direction,
					@intFromEnum(Key.Left) => current_direction = if (current_direction != Direction.Right) Direction.Left else current_direction,
					@intFromEnum(Key.Right) => current_direction = if (current_direction != Direction.Left) Direction.Right else current_direction,
					else => {},
				}
			} else if (k.unicode.convert() == ' ') {
				dead = false;
				food.clear();
				snake.clear();

				try food.append(Square{ .x = @intCast((try rng.random(0, cols))*square_size), .y = @intCast((try rng.random(0, rows))*square_size), .typ = .Food });
				try food.append(Square{ .x = @intCast((try rng.random(0, cols))*square_size), .y = @intCast((try rng.random(0, rows))*square_size), .typ = .Food });

				try snake.append(Square{ .x = 0, .y = 0 });

				for (0..starting_len) |_| {
					try snake.append(Square{ .x = snake.last().?.x + square_size, .y = 0 });
				}

				current_direction = Direction.Right;

				dead = false;
			}
		}

		if (!dead) {
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
					try food.append(Square{ .x = @intCast((try rng.random(0, cols))*square_size), .y = @intCast((try rng.random(0, rows))*square_size), .typ = .Food });
					try snake.insert(0, Square{ .x = snake.items[0].x, .y = snake.items[0].y });
					break;
				}
			}

			for (snake.items[0..snake.items.len - 2]) |*s| {
				if (snake.last().?.x == s.x and snake.last().?.y == s.y) {
					dead = true;
					break;
				}
			}


			if (snake.last().?.x < 0 or snake.last().?.x >= res.width or snake.last().?.y < 0 or snake.last().?.y >= res.height) {
				dead = true;
			}

		}

		frame.clear();

		for (0..snake.items.len) |i| {
			snake.items[i].draw(&frame);
		}

		for (0..food.items.len) |i| {
			food.items[i].draw(&frame);
		}

		if (dead) {
			snake.last().?.draw_color(&frame, Color{ .r = 255, .g = 165, .b = 0 });
			frame.draw_text_centered("Oh no! You died!", res.width/2, res.height/2, null, null);
			frame.draw_text_centered("Press space to restart", res.width/2, res.height/2+fb.font_height, null, null);
			frame.draw_text_centered("Press escape to exit", res.width/2, res.height/2+fb.font_height*2, null, null);
		}

		try frame.update();

		try sleepms(100);
	}

}
