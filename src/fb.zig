const std = @import("std");

const heap = @import("heap.zig");
const io = @import("io.zig");

const graphics = @import("graphics.zig");
const Color = graphics.Color;

const font_width: u64 = 8;
const font_height: u64 = 16;

const font = blk: {

	@setEvalBranchQuota(100000);

	const data = @embedFile("vga16.psf")[4..];
	var ret: [512][16][8]bool = undefined;

	for (&ret, 0..) |*char, i| {
		for (char, 0..) |*row, j| {
			for (row, 0..) |*pixel, k| {
				pixel.* = data[i * 16 + j] & 0b10000000 >> k != 0;
			}
		}
	}

	break :blk ret;

};

const cursor = blk: {

	var ret: [16][8]bool = undefined;
	for (&ret, 0..) |*row, i| {
		for (row, 0..) |*pixel, j| {
			pixel.* = if (i >= 1 and i < ret.len-1 and j == 2) true else false;
		}
	}

	break :blk ret;

};

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

pub fn down(amount: i64) void {
	var a: i64 = @intCast(cursor_pos[1]);
	a += amount;
	cursor_pos[1] = @intCast(a);
}

pub fn right(amount: i64) void {
	var a: i64 = @intCast(cursor_pos[0]);
	a += amount;
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

	for (cursor, 0..) |row, i| {
		for (row, 0..) |pixel, j| {
			graphics.draw_pixel(actual[0]+font_padding+font_width+j, actual[1]+font_padding+i, if (pixel) White else Black);
		}
	}
}

pub fn set_color(color: Color) void {
	current_color = color;
}

fn putchar(c: u8) void {
	const actual = to_coord(cursor_pos[0], cursor_pos[1]);

	for (font[c], 0..) |row, i| {
		for (row, 0..) |pixel, j| {
			graphics.draw_pixel(actual[0]+font_padding+font_width+j, actual[1]+font_padding+i, if (pixel) current_color else Black);
		}
	}
}

pub fn puts(str: []const u8) !void {

	const max_column: u64 = graphics.current_resolution().width / (font_width+font_padding) - 2;
	const max_row: u64 = graphics.current_resolution().height / (font_height+font_padding) - 2;

	for (str) |c| {
		if (c == '\n') {
			putchar(' ');
			cursor_pos[0] = 0;
			cursor_pos[1] += 1;
			continue;
		} else if (c == 8) {
			if (cursor_pos[0] == 0 and cursor_pos[1] == 0) {
				continue;
			}
			putchar(' ');
			if (cursor_pos[0] != 0) {
				cursor_pos[0] -= 1;
			} else {
				cursor_pos[1] -= 1;
				cursor_pos[0] = max_column;
			}
			put_cursor();
			continue;
		} else if (c == '\r') {
			putchar(' ');
			cursor_pos[0] = 0;
			continue;
		}
		putchar(c);
		if (cursor_pos[0] >= max_column) {
			cursor_pos[1] += 1;
			cursor_pos[0] = 0;
		} else if (cursor_pos[1] >= max_row - 2) {
			cursor_pos[1] = 0;
			const current = graphics.current_resolution();
			graphics.draw_rectangle(0, 0, current.width, current.height, Black);
			putchar(c);
			cursor_pos[0] += 1;
		} else {
			cursor_pos[0] += 1;
		}
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
		try puts(format);
		return;
	}

	const alloc = heap.Allocator.init();
	const buf = try alloc_print(alloc, format, args);
	try puts(buf);
	alloc.free(buf);
}

pub fn println(comptime format: []const u8, args: anytype) !void {
	try print(format, args);
	try puts("\n");
}

/// Gets characters until newline.
/// Caller owns and must free memory.
pub fn getline(alloc: heap.Allocator) ![]u8 {

	var buf = try alloc.alloc(u8, 32);
	errdefer alloc.free(buf);
	var len: usize = 0;

	while (true) {
		const key = try io.getkey();
		if (key != null) {

			if (key.?.unicode.char == 0) {
				continue;
			}

			if (key.?.unicode.char == 13) {
				try print("\n", .{});
				break;
			} else if (key.?.unicode.char == 8) {
				if (len != 0) {
					try print("{c}", .{8});
					len -= 1;
					buf[len] = 0;
				}
				continue;
			}

			if (key.?.unicode.char == 'u' and key.?.ctrl) {
				putchar(' ');
				cursor_pos[0] -= 1;
				for (0..len) |_| {
					putchar(' ');
					cursor_pos[0] -= 1;
				}
				cursor_pos[0] += 1;
				len = 0;
				put_cursor();
				continue;
			}

			if (len >= buf.len) {
				buf = try alloc.realloc(u8, buf, buf.len*2);
			}

			buf[len] = key.?.unicode.convert();
			len += 1;
			try print("{c}", .{key.?.unicode.convert()});
		}
	}

	buf = try alloc.realloc(u8, buf, len);

	return buf;

}
