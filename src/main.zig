const std = @import("std");
const uefi = std.os.uefi;
const time = @import("time.zig");
const sleepms = time.sleepms;

const heap = @import("heap.zig");
const ArrayList = @import("array.zig").ArrayList;

var con_out: *uefi.protocol.SimpleTextOutput = undefined;

const io = @import("io.zig");
// const io.println = io.io.println;
// const io.print = io.io.print;
// const getline = io.getline;

const graphics = @import("graphics.zig");
const fb = @import("fb.zig");

const fs = @import("fs.zig");

const log = @import("log.zig");

const rng = @import("rand.zig");

fn digit_amount(n: u64) u64 {
	var amount: u64 = 0;
	var num = n;
	while (num > 0) : (num /= 10) {
		amount += 1;
	}
	return amount;
}

fn group_string(alloc: heap.Allocator, source: []const u8, current_index: u64) !struct { str: []u8, taken_in: u64 } {
	var str: []u8 = try alloc.alloc(u8, 16);
	errdefer alloc.free(str);

	var len: u64 = 0;
	var i: u64 = current_index;
	var back_slashes: u64 = 0;

	while (true) : (i += 1) {

		if (i >= source.len) {
			return error.MissingClosingQuote;
		}

		if (source[i] == '"') {
			if (back_slashes % 2 == 0) {
				break;
			} else {
				back_slashes = 0;
			}
		}

		if (len >= str.len) {
			str = try alloc.realloc(u8, str, str.len * 2);
		}

		if (source[i] == '\\') {
			back_slashes += 1;
		} else {
			str[len] = source[i];
			len += 1;
			back_slashes = 0;
		}
	}

	str = try alloc.realloc(u8, str, len);

	return .{
		.str = str,
		.taken_in = i - current_index,
	};
}

fn parse_string(alloc: heap.Allocator, str: []const u8) ![][]u8 {

	var i: u64 = 0;

	var list = try ArrayList([]u8).init(alloc);
	var current_str = try ArrayList(u8).init(alloc);
	errdefer {
		for (list.items) |item| {
			alloc.free(item);
		}
		if (current_str.attached) {
			current_str.deinit();
		}
		list.deinit();
	}
	defer current_str.deinit();

	while (i < str.len) : (i += 1) {
		if (str[i] == '"') {
			const grouped = try group_string(alloc, str, i+1);
			i += grouped.taken_in + 1;
			if (i < str.len - 1) {
				current_str.deinit();
				current_str = try ArrayList(u8).init(alloc);
			}
			try list.append(grouped.str);
			continue;
		}

		if (str[i] != ' ') {
			try current_str.append(str[i]);
		}
		if ((str[i] == ' ' or i == str.len - 1) and current_str.len != 0) {
			try list.append(try current_str.detach());
			current_str = try ArrayList(u8).init(alloc);
			continue;
		}
		// try fb.println("Data: {s}, char: {c}", .{current_str.items, str[i]});
	}

	return try list.detach();

}

const Request = enum {
	Reboot,
	Shutdown,
	Exit,
};

fn entry() !Request {

	const alloc = heap.Allocator.init();
	log.new_task("InitHeap");
	for (0..100) |_| {
		errdefer log.error_task();
		const a = try alloc.alloc(u8, 1);
		alloc.free(a);
		try time.sleepms(10);
	}
	log.finish_task();
	// try time.sleepms(250);

	try graphics.init_gop();
	const resolutions = try graphics.get_resolutions(alloc);

	var default: ?usize = null;

	for (resolutions, 1..) |res, i| {
		try io.print("{d}:", .{i});
		for (0..5-digit_amount(i)) |_| {
			try io.print(" ", .{});
		}
		try io.println("{d} x {d}", .{ res.width, res.height });
		if (res.width == 1920 and res.height == 1080) {
			default = i;
		}
	}

	try io.print("Resolution ? ", .{});

	if (default != null) {
		try io.println("{d}", .{default.?});
		try io.println("Set to {d} x {d}", .{ resolutions[default.?-1].width, resolutions[default.?-1].height });
		try time.sleepms(1500);
		try graphics.set_videomode(resolutions[default.?-1]);
	} else {
		while (!graphics.has_inited()) {
			const res = try io.getline(alloc);
			defer alloc.free(res);
			const n = std.fmt.parseInt(usize, res, 10) catch |e| {
				if (e == error.InvalidCharacter) {
					try io.println("Not a number", .{});
					continue;
				} else {
					return e;
				}
			};

			try graphics.set_videomode(resolutions[n-1]);

			try io.println("Set to {d} x {d}", .{ resolutions[n-1].width, resolutions[n-1].height });
		}
	}

	alloc.free(resolutions);
	try rng.init();
	log.new_task("InitHeap");
	log.finish_task();
	log.new_task("GraphicsOutput");
	log.finish_task();
	// try sleepms(200);

	try fs.init();
	try fs.mount_root();

	var current_path = try ArrayList(u8).init(alloc);
	defer current_path.deinit();

	try current_path.append('/');

	while (true) {

		fb.set_color(fb.Cyan);
		try fb.print("> ", .{});
		fb.set_color(fb.White);
		// try fb.print("> ", .{});
		const inp = try fb.getline(alloc);
		defer alloc.free(inp);

		const args = parse_string(alloc, inp) catch |e| {
			if (e == error.MissingClosingQuote) {
				try fb.println("Missing closing quote", .{});
			} else {
				try fb.println("Error: {s}", .{@errorName(e)});
			}
			continue;
		};
		defer {
			for (args) |s| {
				alloc.free(s);
			}
			alloc.free(args);
		}

		if (args.len == 0) {
			continue;
		}

		if (std.mem.eql(u8, args[0], "exit")) {
			break;
		} else if (std.mem.eql(u8, args[0], "clear")) {
			try fb.clear();
		} else if (std.mem.eql(u8, args[0], "shutdown")) {
			try fb.println("Shutting down...", .{});
			return Request.Shutdown;
			// uefi.system_table.runtime_services.resetSystem(uefi.tables.ResetType.ResetShutdown, uefi.Status.Success, 0, null);
		} else if (std.mem.eql(u8, args[0], "reboot")) {
			try fb.println("Rebooting...", .{});
			return Request.Reboot;
			// uefi.system_table.runtime_services.resetSystem(uefi.tables.ResetType.ResetCold, uefi.Status.Success, 0, null);
		} else if (std.mem.eql(u8, args[0], "leaks")) {
			try fb.println("Currently allocated on heap: {d}", .{heap.amount});
		} else if (std.mem.eql(u8, args[0], "echo")) {
			if (args.len == 1) {
				try fb.print("\n", .{});
				continue;
			}
			for (args[1..]) |s| {
				try fb.print("{s} ", .{s});
			}
			try fb.print("\n", .{});
		} else if (std.mem.eql(u8, args[0], "random")) {
			try fb.println("Number: {d}", .{ try rng.random(5, 10) });
		} else {
			try fb.println("Unknown command '{s}'", .{args[0]});
		}

	}

	return Request.Exit;

}

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
	io.puts("KERNEL PANIC: ");
	io.puts(msg);
	io.puts("\n");
	while (true) {
		asm volatile ("hlt");
	}
}

fn enter_loop() noreturn {
	io.println("KERNEL LOOP", .{}) catch {};

	while (true) {
		_ = uefi.system_table.con_out.?.outputString(&[_:0]u16{ 'T', 'I', 'C', 'K', '\r', '\n' });
		sleepms(5000) catch {};
	}
}

pub fn main() void {

	// io.init_io();
	// io.println("KERNEL START", .{}) catch unreachable;
	for ("KERNEL START\r\n") |c| {
		const c_ = [2]u16{ c, 0 };
		_ = uefi.system_table.con_out.?.outputString(@ptrCast(&c_));
	}

	io.init_io() catch {
		for ("COULD NOT INIT IO\r\n") |c| {
			const c_ = [2]u16{ c, 0 };
			_ = uefi.system_table.con_out.?.outputString(@ptrCast(&c_));
		}

		while (true) {
			asm volatile ("hlt");
		}

	};

	const res = uefi.system_table.boot_services.?.setWatchdogTimer(0, 0, 0, null);
	if (res != uefi.Status.Success) {
		io.println("COULD NOT SET WATCHDOG: {any}", .{res}) catch unreachable;
	}

	const req = entry() catch |e| {
		io.println("KERNEL PANIC: {any}", .{e}) catch unreachable;
		enter_loop();
	};

	if (heap.amount != 0) {
		io.println("MEMORY LEAKS: {d}", .{heap.amount}) catch unreachable;
		enter_loop();
	}

	fs.umount_root() catch |e| {
		io.println("KERNEL PANIC: {any}", .{e}) catch unreachable;
		enter_loop();
	};
	sleepms(1000) catch unreachable;

	switch (req) {
		Request.Exit => {},
		Request.Shutdown => {
			uefi.system_table.runtime_services.resetSystem(uefi.tables.ResetType.ResetShutdown, uefi.Status.Success, 0, null);
		},
		Request.Reboot => {
			uefi.system_table.runtime_services.resetSystem(uefi.tables.ResetType.ResetCold, uefi.Status.Success, 0, null);
		},
	}

	enter_loop();

}


