const std = @import("std");

const heap = @import("heap.zig");
const io = @import("io.zig");
const fs = @import("fs.zig");

const graphics = @import("graphics.zig");
const Color = graphics.Color;

pub var font_width: u64 = 8;
pub var font_height: u64 = 16;

const vga_font = @embedFile("./assets/vga16.psf");

// pub const font = blk: {

// 	@setEvalBranchQuota(100000);

// 	const data = vga_font[4..];
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

pub var font: [512][][]bool = undefined;
pub var font_loaded = false;

// const cursor = blk: {

// 	var ret: [16][8]bool = undefined;
// 	for (&ret, 0..) |*row, i| {
// 		for (row, 0..) |*pixel, j| {
// 			pixel.* = if (i >= 1 and i < ret.len-1 and j == 2) true else false;
// 		}
// 	}

// 	break :blk ret;

// };

const font_padding: u64 = 0;

pub const White = Color{ .r = 255, .g = 255, .b = 255 };
pub const Black = Color{ .r = 0, .g = 0, .b = 0 };
pub const Orange = Color{ .r = 255, .g = 128, .b = 0 };
pub const Green = Color{ .r = 0, .g = 255, .b = 0 };
pub const Red = Color{ .r = 255, .g = 0, .b = 0 };
pub const Blue = Color{ .r = 0, .g = 0, .b = 255 };
pub const Cyan = Color{ .r = 0, .g = 255, .b = 255 };

var current_color = White;

var cursor_pos = [_]u64{0, 0};

pub fn load_builtin_font(alloc: heap.Allocator) !void {

	const data = vga_font[4..];

	var ret: [512][][]bool = undefined;

	const num: i64 = 0b10000000;

	for (&ret, 0..) |*char, i| {
		char.* = try alloc.alloc([]bool, 16);
		for (char.*, 0..) |*row, j| {
			row.* = try alloc.alloc(bool, 8);
			for (row.*, 0..) |*pixel, k| {
				pixel.* = data[i * 16 + j] & num >> @intCast(k) != 0;
			}
		}
	}

	font = ret;

	font_loaded = true;
	font_height = 16;
	font_width = 8;

}

pub fn load_font(alloc: heap.Allocator, width: u64, height: u64, font_name: []const u8) !void {

	const path = try alloc_print(alloc, "/fonts/{s}.psf", .{font_name});
	defer alloc.free(path);

	const file = try fs.open_file(path, .Read);
	defer file.close() catch {};

	const all = try file.read_all_alloc();
	defer alloc.free(all);

	const data = all[4..];

	var ret: [512][][]bool = undefined;

	const num: i64 = 0b10000000;

	for (&ret, 0..) |*char, i| {
		char.* = try alloc.alloc([]bool, height);
		for (char.*, 0..) |*row, j| {
			row.* = try alloc.alloc(bool, width);
			for (row.*, 0..) |*pixel, k| {
				pixel.* = data[i * height + j] & num >> @intCast(k) != 0;
			}
		}
	}

	font = ret;

	font_loaded = true;
	font_height = height;
	font_width = width;

}

pub fn free_font(alloc: heap.Allocator) void {
	font_loaded = false;
	for (&font) |*char| {
		for (char.*) |*row| {
			alloc.free(row.*);
		}
		alloc.free(char.*);
	}
}

pub fn get_cursor_pos() struct { x: u64, y: u64 } {
	return .{
		.x = cursor_pos[0],
		.y = cursor_pos[1],
	};
}

pub fn set_cursor_pos(x: u64, y: u64) void {
	cursor_pos[0] = x;
	cursor_pos[1] = y;
}

pub fn down(amount: i64) void {
	var a: i64 = @intCast(cursor_pos[1]);
	a += amount;

	const max_row: u64 = graphics.current_resolution().height / (font_height+font_padding) - 2;

	if (a >= max_row - 2) {
		graphics.scroll(font_height, .Down);
		a -= 1;
	}

	cursor_pos[1] = @intCast(a);

}

pub fn right(amount: i64) void {
	var a: i64 = @intCast(cursor_pos[0]);
	a += amount;

	const max_column: u64 = graphics.current_resolution().width / (font_width+font_padding) - 2;

	if (a >= max_column) {
		down(1); // cursor_pos[1] += 1;
		a = 0;
	} else if (a <= -1) {
		down(-1);
		a = @intCast(max_column - 1);
	}

	cursor_pos[0] = @intCast(a);

}

fn to_coord(x: u64, y: u64) [2]u64 {
	return [_]u64{@intCast(x*(font_width+font_padding)), @intCast(y*(font_height+font_padding)+2)};
}

fn to_i32(x: anytype) i32 {
	return @intCast(x);
}

fn put_cursor() void {
	const actual = to_coord(cursor_pos[0], cursor_pos[1]);

	for (0..font_height) |i| {
		for (0..font_width) |j| {
			if (i >= 1 and i < font_height-1 and (j == 0 or j == 1)) {
				graphics.draw_pixel(actual[0]+font_padding+font_width+j, actual[1]+font_padding+i, White);
			} // else {
			// 	graphics.draw_pixel(actual[0]+font_padding+font_width+j, actual[1]+font_padding+i, Black);
			// }
		}
	}

	// for (cursor, 0..) |row, i| {
	// 	for (row, 0..) |pixel, j| {
	// 		graphics.draw_pixel(actual[0]+font_padding+font_width+j, actual[1]+font_padding+i, if (pixel) White else Black);
	// 	}
	// }
}

pub fn set_color(color: Color) void {
	current_color = color;
}

// fn putchar_builtin(c: u8) void {
// 	const actual = to_coord(cursor_pos[0], cursor_pos[1]);

// 	for (builtin_font[c], 0..) |row, i| {
// 		for (row, 0..) |pixel, j| {
// 			graphics.draw_pixel(actual[0]+font_padding+font_width+j, actual[1]+font_padding+i, if (pixel) current_color else Black);
// 		}
// 	}
// }

fn putchar(c: u8) void {
	const actual = to_coord(cursor_pos[0], cursor_pos[1]);

	for (font[c], 0..) |row, i| {
		for (row, 0..) |pixel, j| {
			graphics.draw_pixel(actual[0]+font_padding+font_width+j, actual[1]+font_padding+i, if (pixel) current_color else Black);
		}
	}
}

// pub fn puts_builtin(str: []const u8) void {
// 	for (str) |c| {
// 		if (c == '\n') {
// 			putchar_builtin(' ');
// 			cursor_pos[0] = 0;
// 			down(1);
// 			continue;
// 		} else if (c == 8) {
// 			if (cursor_pos[0] == 0 and cursor_pos[1] == 0) {
// 				continue;
// 			}
// 			putchar_builtin(' ');
// 			right(-1);
// 			put_cursor();
// 			continue;
// 		} else if (c == '\r') {
// 			putchar_builtin(' ');
// 			cursor_pos[0] = 0;
// 			continue;
// 		}
// 		putchar_builtin(c);
// 		right(1);
// 	}
// 	put_cursor();
// }

pub fn puts(str: []const u8) void {

	// const max_column: u64 = graphics.current_resolution().width / (font_width+font_padding) - 2;

	for (str) |c| {
		if (c == '\n') {
			putchar(' ');
			cursor_pos[0] = 0;
			down(1); // cursor_pos[1] += 1;
			continue;
		} else if (c == 8) {
			if (cursor_pos[0] == 0 and cursor_pos[1] == 0) {
				continue;
			}
			putchar(' ');
			right(-1);
			// if (cursor_pos[0] > 0) {
			// 	right(-1);
			// } else {
			// 	cursor_pos[0] -= 1;
			// 	putchar(' ');
			// 	cursor_pos[0] += 1;
			// 	right(-1);
			// }
			// if (cursor_pos[0] > 1) {
			// 	right(-1); // cursor_pos[0] -= 1;
			// } else {
			// 	// if (cursor_pos[0] != 0) {
			// 	// 	cursor_pos[0] -= 1;
			// 	// 	putchar(' ');
			// 	// 	cursor_pos[0] += 1;
			// 	// }
			// 	right(-1);
			// 	// down(-1); // cursor_pos[1] -= 1;
			// 	cursor_pos[0] = max_column;
			// }
			put_cursor();
			continue;
		} else if (c == '\r') {
			putchar(' ');
			cursor_pos[0] = 0;
			continue;
		} else if (c == '\t') {
			for (0..4) |_| {
				putchar(' ');
				right(1);
			}
			continue;
		}
		putchar(c);
		right(1); // cursor_pos[0] += 1;
	}
	put_cursor();
}

pub fn clear() void {
	cursor_pos[0] = 0;
	cursor_pos[1] = 0;

	const current = graphics.current_resolution();
	graphics.draw_rectangle(0, 0, current.width, current.height, Black);
}

pub fn alloc_print(alloc: heap.Allocator, comptime format: []const u8, args: anytype) ![]u8 {
	const size = std.math.cast(usize, std.fmt.count(format, args)) orelse return error.OutOfMemory;
	const buf = try alloc.alloc(u8, size);
	_ = try std.fmt.bufPrint(buf, format, args);
	return buf;
}

pub fn print(comptime format: []const u8, args: anytype) !void {
    const ArgsType = @TypeOf(args);
    const args_type_info = @typeInfo(ArgsType);
    const fields_info = args_type_info.Struct.fields;

	if (fields_info.len == 0) {
		puts(format);
		return;
	}

	const alloc = heap.Allocator.init();
	const buf = try alloc_print(alloc, format, args);
	puts(buf);
	alloc.free(buf);
}

pub fn println(comptime format: []const u8, args: anytype) !void {
	try print(format, args);
	puts("\n");
}

/// Gets characters until newline.
/// Caller owns and must free memory.
pub fn getline(alloc: heap.Allocator) ![]u8 {

	// const max_column: u64 = graphics.current_resolution().width / (font_width+font_padding) - 2;

	var buf = try alloc.alloc(u8, 32);
	errdefer alloc.free(buf);
	var len: usize = 0;

	var pos: usize = 0;

	while (true) {
		const key = try io.getkey();
		if (key != null) {

			if (key.?.scancode == 4) {

				if (pos == 0) {
					continue;
				} else if (pos != len) {
					putchar(buf[pos]);
				} else {
					putchar(' ');
				}

				right(-1);
				pos -= 1;
				put_cursor();
				continue;
			} else if (key.?.scancode == 3) {
				if (pos == len) {
					continue;
				} else {
					putchar(buf[pos]);
				}

				right(1);
				pos += 1;
				put_cursor();
				continue;
			} else if (key.?.scancode == 5) {

				if (pos == 0) {
					continue;
				} else if (pos != len) {
					putchar(buf[pos]);
				} else {
					putchar(' ');
				}

				right(-@as(i64, @intCast(pos)));
				pos = 0;
				put_cursor();
				continue;

			} else if (key.?.scancode == 6) {

				if (pos == len) {
					continue;
				} else {
					putchar(buf[pos]);
				}

				right(@as(i64, @intCast(len-pos)));
				pos = len;
				put_cursor();
				continue;

			}

			if (key.?.unicode.char == 0) {
				continue;
			}

			if (key.?.unicode.char == 13) {

				if (pos != len) {
					putchar(buf[pos]);
				} else {
					putchar(' ');
				}

				right(@intCast(len-pos));
				try print("\n", .{});
				break;
			} else if (key.?.unicode.char == 8) {

				if (pos == 0) {
					continue;
				}

				if (pos == len) {
					putchar(' ');
					right(-1);
					putchar(' ');
					put_cursor();
					len -= 1;
					pos -= 1;
					buf[len] = 0;
				} else {

					right(-1);

					for (pos..len) |i| {
						buf[i-1] = buf[i];
						putchar(buf[i-1]);
						right(1);
					}

					putchar(' ');

					right(-@as(i64, @intCast(len-pos)));

					put_cursor();

					len -= 1;
					pos -= 1;
					buf[len] = 0;

				}
				continue;
			}

			if (key.?.unicode.char == 'u' and key.?.ctrl) {

				right(@intCast(len-pos));

				putchar(' ');
				right(-1); // cursor_pos[0] -= 1;
				for (0..len) |_| {
					putchar(' ');

					right(-1); // cursor_pos[0] -= 1;
				}
				right(1); // cursor_pos[0] += 1;
				len = 0;
				pos = 0;
				put_cursor();
				continue;
			} else if (key.?.unicode.char == 'c' and key.?.ctrl) {
				try println("^C", .{});
				return error.CtrlC;
			}

			if (len >= buf.len) {
				buf = try alloc.realloc(u8, buf, buf.len*2);
			}

			if (pos == len) {
				buf[len] = key.?.unicode.convert();
			} else if (pos != 0) {

				// for (len-pos..pos) |i| {
				// 	buf[len-i+1] = buf[len-i];
				// }

				right(@intCast(len-pos));

				var i = len;
				while (i >= pos) : (i -= 1) {
					buf[i] = buf[i-1];
					putchar(buf[i]);
					right(-1);
				}

				right(1);

				buf[pos] = key.?.unicode.convert();

			} else {

				right(@intCast(len));

				for (0..len) |i| {
					buf[len-i] = buf[len-i-1];
					putchar(buf[len-i]);
					right(-1);
				}

				buf[pos] = key.?.unicode.convert();

			}

			len += 1;
			pos += 1;
			try print("{c}", .{key.?.unicode.convert()});
		}
	}

	buf = try alloc.realloc(u8, buf, len);

	return buf;

}
