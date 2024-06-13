const std = @import("std");
const uefi = std.os.uefi;
const time = @import("time.zig");

const heap = @import("heap.zig");
const bs = @import("boot_services.zig");

var con_out: *uefi.protocol.SimpleTextOutput = undefined;
var con_in: *uefi.protocol.SimpleTextInputEx = undefined;
var inited: bool = false;

pub fn init_io() !void {
	con_out = uefi.system_table.con_out.?;
	if ((try bs.init()).locateProtocol(&uefi.protocol.SimpleTextInputEx.guid, null, @ptrCast(&con_in)) != uefi.Status.Success) {
		return error.NoStdIn;
	}
	inited = true;
}

pub fn has_inited() bool {
	return inited;
}

pub fn puts(msg: []const u8) void {
	for (msg) |c| {
		if (c == '\n') {
			_ = con_out.outputString(&[2:0]u16{ '\r', 0 });
		}

		const c_ = [2]u16{ c, 0 }; // work around https://github.com/ziglang/zig/issues/4372
		_ = con_out.outputString(@ptrCast(&c_));
	}
}

fn printf(buf: []u8, comptime format: []const u8, args: anytype) void {
	puts(std.fmt.bufPrint(buf, format, args) catch unreachable);
}

pub fn alloc_print(alloc: heap.Allocator, comptime format: []const u8, args: anytype) ![]u8 {
	const size = std.math.cast(usize, std.fmt.count(format, args)) orelse return error.OutOfMemory;
	const buf = try alloc.alloc(u8, size);
	_ = try std.fmt.bufPrint(buf, format, args);
	return buf;
}

pub fn alloc_printZ(alloc: heap.Allocator, comptime format: []const u8, args: anytype) ![:0]u8 {
	const buf = try alloc_print(alloc, format, args);
	return buf[0 .. buf.len - 1 :0];
}

pub fn print(comptime format: []const u8, args: anytype) !void {
	const alloc = heap.Allocator.init();
	const buf = try alloc_print(alloc, format, args);
	printf(buf, format, args);
	alloc.free(buf);
}

pub fn println(comptime format: []const u8, args: anytype) !void {
	try print(format, args);
	puts("\n");
}

pub const UnicodeChar = struct {
	char: u16,

	pub fn convert(self: *const UnicodeChar) u8 {
		return @as(u8, @intCast(self.char));
	}

};

pub const Key = struct {
	scancode: u16,
	unicode: UnicodeChar,
	ctrl: bool = false,
	shift: bool = false,
};

pub fn getkey() !?Key {
	var key: uefi.protocol.SimpleTextInputEx.Key = undefined;
	const res = con_in.readKeyStrokeEx(&key);
	if (res == uefi.Status.NotReady) {
		return null;
	}
	if (res != uefi.Status.Success) {
		try res.err();
	}
	return .{
		.scancode = key.input.scan_code,
		.unicode = .{ .char = key.input.unicode_char },
		.ctrl = key.state.shift.left_control_pressed,
		.shift = key.state.shift.left_shift_pressed,
	};
}

pub fn right(amount: i64) void {
	_ = con_out.setCursorPosition(@intCast(con_out.mode.cursor_column+amount), @intCast(con_out.mode.cursor_row));
}

pub fn down(amount: i64) void {
	_ = con_out.setCursorPosition(@intCast(con_out.mode.cursor_column), @intCast(con_out.mode.cursor_row+amount));
}

/// Gets characters until newline.
/// Caller owns and must free memory.
pub fn getline(alloc: heap.Allocator) ![]u8 {

	var buf = try alloc.alloc(u8, 32);
	errdefer alloc.free(buf);
	var len: usize = 0;

	try print("_", .{});
	_ = con_out.setCursorPosition(@intCast(con_out.mode.cursor_column-1), @intCast(con_out.mode.cursor_row));

	while (true) {
		const key = try getkey();
		if (key != null) {

			if (key.?.unicode.char == 0) {
				continue;
			}

			if (key.?.unicode.char == 13) {
				try print(" \n", .{});
				break;
			} else if (key.?.unicode.char == 8) {
				if (len != 0) {
					try print("{c}_ ", .{8});
					_ = con_out.setCursorPosition(@intCast(con_out.mode.cursor_column-2), @intCast(con_out.mode.cursor_row));
					len -= 1;
					buf[len] = 0;
				}
				continue;
			}

			if (key.?.unicode.char == 'u' and key.?.ctrl) {
				_ = con_out.setCursorPosition(@intCast(con_out.mode.cursor_column-@as(i32, @intCast(len))), @intCast(con_out.mode.cursor_row));
				len = 0;
			}

			if (len >= buf.len) {
				buf = try alloc.realloc(u8, buf, buf.len*2);
			}

			buf[len] = key.?.unicode.convert();
			len += 1;
			try print("{c}_", .{key.?.unicode.convert()});
			_ = con_out.setCursorPosition(@intCast(con_out.mode.cursor_column-1), @intCast(con_out.mode.cursor_row));
		}
	}

	buf = try alloc.realloc(u8, buf, len);

	return buf;

}
