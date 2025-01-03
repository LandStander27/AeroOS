const std = @import("std");
const uefi = std.os.uefi;
const time = @import("time.zig");
const sleepms = time.sleepms;

const heap = @import("heap.zig");
const bs = @import("boot_services.zig");
const ArrayList = @import("array.zig").ArrayList;

var con_out: *uefi.protocol.SimpleTextOutput = undefined;

const io = @import("io.zig");
// const io.println = io.io.println;
// const io.print = io.io.print;
// const getline = io.getline;

const graphics = @import("graphics.zig");
const fb = @import("fb.zig");
const pointer = @import("mouse.zig");

const fs = @import("fs.zig");
const log = @import("log.zig");
const rng = @import("rand.zig");

const network = @import("network.zig");

const snake_on_boot: bool = false;
const choose_resolution: bool = false;

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
	SoftwareReboot,
	Reboot,
	Shutdown,
	Exit,
};

fn snake(alloc: heap.Allocator) !void {
	log.new_task("Snake");
	errdefer log.error_task();

	var state = try graphics.State.init(alloc);
	defer state.deinit();

	const pos = fb.get_cursor_pos();
	fb.set_cursor_pos(0, 0);

	@import("snake.zig").start(alloc) catch |e| {
		state.load();
		fb.set_cursor_pos(pos.x, pos.y);
		log.error_task();
		try fb.println("Error: {s}", .{@errorName(e)});
		return;
	};

	state.load();
	fb.set_cursor_pos(pos.x, pos.y);

	log.finish_task();
}

fn gol(alloc: heap.Allocator) !void {
	log.new_task("GameOfLife");
	errdefer log.error_task();

	var state = try graphics.State.init(alloc);
	defer state.deinit();

	const pos = fb.get_cursor_pos();
	fb.set_cursor_pos(0, 0);

	@import("gol.zig").start(alloc) catch |e| {
		state.load();
		fb.set_cursor_pos(pos.x, pos.y);
		log.error_task();
		try fb.println("Error: {s}", .{@errorName(e)});
		return;
	};

	state.load();
	fb.set_cursor_pos(pos.x, pos.y);

	log.finish_task();
}

fn entry() !Request {

	log.new_task("BootServices");
	_ = bs.init() catch {
		@panic("Could not start boot services");
	};
	log.finish_task();

	const alloc = heap.Allocator.init();
	log.new_task("InitHeap");
	for (0..100) |_| {
		const a = alloc.alloc(u8, 1) catch |e| {
			log.error_task();
			@panic(@errorName(e));
		};
		alloc.free(a);
		try time.sleepms(10);
	}
	log.finish_task();
	// try time.sleepms(250);

	try fb.load_builtin_font(alloc);
	defer fb.free_font(alloc);

	try graphics.init();
	const resolutions = try graphics.get_resolutions(alloc);

	var default: ?usize = null;
	default = null;

	for (resolutions, 1..) |res, i| {
		try io.print("{d}:", .{i});
		for (0..5-digit_amount(i)) |_| {
			try io.print(" ", .{});
		}
		try io.println("{d} x {d}", .{ res.width, res.height });
		if (res.width == 1920 and res.height == 1080 and choose_resolution) {
			default = i;
		}
	}

	try io.print("Resolution ? ", .{});

	if (default != null) {
		try io.println("{d}", .{default.?});
		try io.println("Set to {d} x {d}", .{ resolutions[default.?-1].width, resolutions[default.?-1].height });
		try time.sleepms(1000);
		try graphics.set_videomode(resolutions[default.?-1]);
	} else {
		var done = false;
		while (!done) {
			const res = try io.getline(alloc);
			defer alloc.free(res);
			const n = std.fmt.parseInt(usize, res, 10) catch |e| {
				if (e == error.InvalidCharacter) {
					try io.println("Not a number", .{});
					try io.print("Resolution ? ", .{});
					continue;
				} else {
					return e;
				}
			};

			try io.println("Set to {d} x {d}", .{ resolutions[n-1].width, resolutions[n-1].height });

			try graphics.set_videomode(resolutions[n-1]);
			done = true;
		}
	}

	alloc.free(resolutions);

	graphics.clear();

	try fs.init(alloc);
	defer fs.deinit();

	try fs.mount_root();
	defer {
		fs.umount_root() catch |e| {
			kernel_panic("On root umount: {any}", .{e});
		};
	}

	// try fb.load_font(alloc, 8, 16, "vga16");

	try rng.init();
	// log.new_task("BootServices");
	// log.finish_task();
	// log.new_task("InitHeap");
	// log.finish_task();
	// log.new_task("GraphicsOutput");
	// log.finish_task();
	// try sleepms(200);

	log.new_task("Watchdog");
	bs.disable_watchdog() catch |e| {
		log.error_task_msg("{any}", .{e});
	};
	log.finish_task();

	try pointer.init();

	network.init() catch {};

	if (rng.get_mode() == .NonRandom) {
		try fb.println("Warning! Firmware does not support RNG.\nAll random numbers generated will not be random.", .{});
	}

	try fb.println("Run `help` for help", .{});

	if (snake_on_boot) {
		try fb.println("Booting directly into snake...", .{});
		fb.set_color(fb.Cyan);
		try fb.print("> ", .{});
		fb.set_color(fb.White);
		try fb.println("snake", .{});
		try sleepms(1000);
		try snake(alloc);
	}

	outer: while (true) {

		fb.set_color(fb.Orange);
		try fb.print("{s}", .{fs.cwd()});
		fb.set_color(fb.Cyan);
		try fb.print(" > ", .{});
		fb.set_color(fb.White);
		// try fb.print("> ", .{});
		const inp = fb.getline(alloc) catch |e| {
			if (e == error.CtrlC) {
				continue;
			} else {
				return e;
			}
		};
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
		} else if (std.mem.eql(u8, args[0], "help")) {
			const str =
				\\exit                                         Exit the shell
				\\help                                         Show this help
				\\clear                                        Clear the screen
				\\shutdown                                     Shut down
				\\reboot                                       Reboot
				\\leaks                                        Show heap allocations
				\\echo <str>                                   Print <str>
				\\ls <dir>                                     List files in <dir>. If <dir> is not specified, list files in current directory
				\\cd <dir>                                     Change directory to <dir>
				\\cat <file>                                   Print contents of <file>
				\\loadfont <name>                              Load font <name>. Available fonts are in `/fonts` (excluding extension).
				\\random <min> <max>                           Random number between <min> and <max>
				\\time                                         Print unix time
				\\date                                         Print date
				\\snake                                        Start a builtin snake game
				\\getkey                                       Print keypress info
				\\allocate <size>                              Allocate <size> bytes on heap. In other words, artificially creates a memory leak (for debugging)
				\\panic <str>                                  Initiate a kernel panic with message <str>
				\\resolution [set/get/list] <width> <height>   Manage the resolution
			;
			try fb.println("{s}\n", .{str});
		} else if (std.mem.eql(u8, args[0], "allocate")) {

			if (args.len == 1) {
				try fb.println("Invalid usage", .{});
			}
			const size = std.fmt.parseInt(usize, args[1], 10) catch 0;
			_ = try alloc.alloc(u8, size);

		} else if (std.mem.eql(u8, args[0], "test")) {

			// const exe = @import("exe.zig");

			// const hdr = exe.load_exe(alloc) catch |e| {
			// 	try fb.println("Error: {s}", .{@errorName(e)});
			// 	continue;
			// };

			// defer alloc.destroy(hdr);

			// try fb.println("hdr: {any}", .{hdr});

			// // const mainfn: *fn() anyerror!void = @ptrFromInt(hdr.e_entry);
			// // try mainfn();

			// const mainfn: *fn() anyerror!void = @ptrCast(@constCast(&hdr.e_entry));
			// try mainfn();

		} else if (std.mem.eql(u8, args[0], "loadfont")) {

			if (args.len == 1) {
				try fb.println("Invalid usage", .{});
				continue;
			}

			const path = try fb.alloc_print(alloc, "/fonts/{s}.psf", .{args[1]});
			defer alloc.free(path);

			const file = fs.open_file(path, .Read) catch |e| {
				if (e == error.NotFound) {
					try fb.println("Font not found", .{});
				} else {
					try fb.println("Error: {s}", .{@errorName(e)});
				}
				continue;
			};
			file.close() catch {};

			var width: usize = 0;
			var height: usize = 0;

			if (std.mem.eql(u8, args[1], "vga09")) {
				width = 8;
				height = 9;
			} else if (std.mem.startsWith(u8, args[1], "vga16")) {
				width = 8;
				height = 16;
			} else if (std.mem.startsWith(u8, args[1], "vga18")) {
				width = 8;
				height = 18;
			} else {

				try fb.print("Width: ", .{});
				const width_line = fb.getline(alloc) catch |e| {
					if (e == error.CtrlC) {
						continue;
					} else {
						return e;
					}
				};
				defer alloc.free(width_line);

				width = std.fmt.parseInt(usize, width_line, 10) catch 0;

				try fb.print("Height: ", .{});
				const height_line = fb.getline(alloc) catch |e| {
					if (e == error.CtrlC) {
						continue;
					} else {
						return e;
					}
				};
				defer alloc.free(height_line);

				height = std.fmt.parseInt(usize, height_line, 10) catch 0;
				
			}

			fb.clear();
			fb.free_font(alloc);
			try fb.load_font(alloc, width, height, args[1]);

		} else if (std.mem.eql(u8, args[0], "resolution")) {
			if (args.len == 1 and (args.len != 2 or args.len != 4)) {
				try fb.println("Invalid usage: resolution {set/get/list} <width> <height>", .{});
				continue;
			}
			
			if (std.mem.eql(u8, args[1], "get") and args.len == 2) {
				try fb.println("Current resolution: {d}x{d}", .{ graphics.current_resolution().width, graphics.current_resolution().height });
			} else if (std.mem.eql(u8, args[1], "set") and args.len == 4) {
				const list = try graphics.get_resolutions(alloc);
				defer alloc.free(list);
				const width = std.fmt.parseInt(u64, args[2], 10) catch |e| {
					try fb.println("Error: {s}", .{ @errorName(e) });
					continue;
				};
				const height = std.fmt.parseInt(u64, args[3], 10) catch |e| {
					try fb.println("Error: {s}", .{ @errorName(e) });
					continue;
				};
				var found = false;
				for (0..list.len) |i| {
					if (list[i].width == width and list[i].height == height) {
						found = true;
						graphics.set_videomode(list[i]) catch |e| {
							try fb.println("Error: {s}", .{ @errorName(e) });
							continue;
						};
						fb.clear();
						break;
					}
				}
				if (!found) {
					try fb.println("Resolution does not exist.", .{});
					continue;
				}
			} else if (std.mem.eql(u8, args[1], "list") and args.len == 2) {
				const list = try graphics.get_resolutions(alloc);
				for (0..list.len) |i| {
					try fb.println("{d}: {d}x{d}", .{i, list[i].width, list[i].height});
				}
				defer alloc.free(list);
			} else {
				try fb.println("Invalid usage: resolution {set/get/list} <width> <height>", .{});
				continue;
			}
		} else if (std.mem.eql(u8, args[0], "clear")) {
			fb.clear();
		} else if (std.mem.eql(u8, args[0], "shutdown")) {
			// try fb.println("Shutting down...", .{});
			return Request.Shutdown;
			// uefi.system_table.runtime_services.resetSystem(uefi.tables.ResetType.ResetShutdown, uefi.Status.Success, 0, null);
		} else if (std.mem.eql(u8, args[0], "reboot")) {
			// try fb.println("Rebooting...", .{});
			return Request.Reboot;
			// uefi.system_table.runtime_services.resetSystem(uefi.tables.ResetType.ResetCold, uefi.Status.Success, 0, null);
		} else if (std.mem.eql(u8, args[0], "cd")) {

			if (args.len == 1) {
				try fb.println("Invalid usage", .{});
				continue;
			}

			fs.set_cwd(args[1]) catch |e| {
				switch (e) {
					error.NotFound => {
						try fb.println("Directory not found", .{});
					},
					error.AlreadyAtRoot => {
						continue;
					},
					else => {
						try fb.println("Error: {s}", .{@errorName(e)});
					}
				}
			};

		} else if (std.mem.eql(u8, args[0], "ls")) {

			const dir_to_list = if (args.len == 1) fs.cwd() else args[1];

			const dir = fs.open_dir(dir_to_list) catch |e| {
				try fb.println("Error: {s}", .{@errorName(e)});
				continue;
			};
			defer dir.close() catch {
				fb.println("Error: Could not close directory", .{}) catch {};
			};

			const info = dir.get_info() catch |e| {
				try fb.println("Error: Could not read directory: {s}", .{@errorName(e)});
				continue;
			};
			defer info.free();

			if (info.filetype != .Directory) {
				try fb.println("Error: Not a directory", .{});
				continue;
			}

			var max_size_len: usize = 0;

			while (dir.next() catch |e| {
				try fb.println("Error: Could not read directory: {s}", .{@errorName(e)});
				continue;
			}) |dirent| {
				defer dirent.free();
				const size = std.fmt.count("{d}", .{dirent.size});
				if (size > max_size_len) {
					max_size_len = size;
				}
			}

			try dir.restart();

			while (dir.next() catch |e| {
				try fb.println("Error: Could not read directory: {s}", .{@errorName(e)});
				continue;
			}) |dirent| {
				defer dirent.free();
				try fb.print("{d}", .{dirent.size});
				for (0..max_size_len-std.fmt.count("{d}", .{dirent.size})) |_| {
					try fb.print(" ", .{});
				}
				if (dirent.filetype == .Directory) {
					fb.set_color(fb.Cyan);
				} else {
					fb.set_color(fb.White);
				}
				try fb.println("  {s}", .{dirent.filename});
				fb.set_color(fb.White);

				{
					const key = io.getkey() catch blk: {
						break :blk null;
					};
					if (key == null) {
						continue;
					}
					if (key.?.unicode.convert() == 'c' and key.?.ctrl) {
						break;
					}
				}

			}

			try fb.print("\n", .{});

		} else if (std.mem.eql(u8, args[0], "cat")) {

			const file = fs.open_file(args[1], .Read) catch |e| {
				try fb.println("Error: {s}", .{@errorName(e)});
				continue;
			};

			defer file.close() catch {
				fb.println("Error: Could not close file", .{}) catch {};
			};

			const data = file.read_all_alloc() catch |e| {
				try fb.println("Error: {s}", .{@errorName(e)});
				continue;
			};
			defer alloc.free(data);

			for (data, 0..) |c, i| {
				fb.puts(&[_]u8{ c });
				if (i % 32 == 0) {

					const key = io.getkey() catch blk: {
						break :blk null;
					};

					if (key == null) {
						continue;
					}

					if (key.?.unicode.convert() == 'c' and key.?.ctrl) {
						break;
					}

				}
			}

			if (data[data.len - 1] != '\n') {
				try fb.print("\n", .{});
			}

		} else if (std.mem.eql(u8, args[0], "leaks")) {
			try fb.println("Objects currently allocated on heap: {d}", .{heap.amount});
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
			if (args.len == 1) {
				try fb.println("{d}", .{ try rng.random(0, std.math.maxInt(u64)) });
			} else if (args.len == 3) {
				const num: ?u64 = rng.random(std.fmt.parseInt(u64, args[1], 10) catch 0, std.fmt.parseInt(u64, args[2], 10) catch 0) catch |e| blk: {
					if (e == error.InvalidRange) {
						try fb.println("Invalid range", .{});
					} else {
						try fb.println("Error: {s}", .{@errorName(e)});
					}
					break :blk null;
				};
				if (num != null) {
					try fb.println("{d}", .{ num.? });
				}
			} else {
				try fb.println("Usage: random <min> <max>", .{});
			}
		} else if (std.mem.eql(u8, args[0], "time")) {
			const t: ?time.Time = time.Time.timezone_now() catch |e| blk: {
				try fb.println("Error: {s}", .{@errorName(e)});
				break :blk null;
			};

			if (t != null) {
				try fb.println("{d}", .{ t.?.unix() });
			}

		} else if (std.mem.eql(u8, args[0], "date")) {
			const t: ?time.Time = time.Time.timezone_now() catch |e| blk: {
				try fb.println("Error: {s}", .{@errorName(e)});
				break :blk null;
			};

			if (t != null) {
				for ([_]u16{ @intCast(t.?.month), @intCast(t.?.day), t.?.year }) |i| {
					if (i < 10) {
						try fb.print("0{d}/", .{i});
						continue;
					}
					try fb.print("{d}/", .{i});
				}
				fb.right(-1);
				try fb.print(" ", .{});
				for ([_]u8{ t.?.hour, t.?.minute, t.?.second }) |i| {
					if (i < 10) {
						try fb.print("0{d}:", .{i});
						continue;
					}
					try fb.print("{d}:", .{i});
				}
				fb.right(-1);
				try fb.print(" \n", .{});
			}

		} else if (std.mem.eql(u8, args[0], "snake")) {
			try snake(alloc);
		} else if (std.mem.eql(u8, args[0], "gameoflife")) {
			try fb.println("Not implemented", .{});
			// try gol(alloc);
		} else if (std.mem.eql(u8, args[0], "getkey")) {

			var key: ?io.Key = null;
			try fb.println("Waiting for keypress... ^C to stop", .{});

			while (true) {
				while (key == null) {
					key = io.getkey() catch |e| {
						try fb.println("Error: {s}", .{@errorName(e)});
						continue :outer;
					};
				}

				if (key.?.ctrl and key.?.unicode.convert() == 'c') {
					break;
				}

				try fb.println("scancode: {d} char: '{c}'", .{ key.?.scancode, key.?.unicode.convert() });
				key = null;
			}
		} else if (std.mem.eql(u8, args[0], "panic")) {
			if (args.len == 1) {
				@panic("User requested panic");
			} else {
				@panic(args[1]);
			}
		} else {
			try fb.println("Unknown command '{s}'", .{args[0]});
		}

	}

	return Request.Exit;

}

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
	// if (graphics.has_inited()) {
	// 	const res: bool = blk: {
	// 		fb.set_color(fb.Red);
	// 		fb.puts("KERNEL PANIC: ");
	// 		fb.puts(msg);
	// 		fb.puts("\n");
	// 		fb.set_color(fb.White);
	// 		break :blk false;
	// 	};
	// 	if (res) {
	// 		io.puts("KERNEL PANIC: ");
	// 		io.puts(msg);
	// 		io.puts("\n");
	// 	}
	// } else {
	// 	io.puts("KERNEL PANIC: ");
	// 	io.puts(msg);
	// 	io.puts("\n");
	// }

	// enter_loop();

	kernel_panic_raw(msg);

}

fn kernel_panic_raw(msg: []const u8) noreturn {

	const on_heap = heap.amount;

	const alloc = heap.Allocator.init();

	if (graphics.has_inited()) {

		// var framebuffer_worked = true;

		(blk: {

			if (fb.font_loaded) {
				fb.free_font(alloc);
			}

			fb.load_builtin_font(alloc) catch |e| {
				break :blk e;
			};

			var framebuffer = graphics.Framebuffer.init(alloc) catch |e| {
				break :blk e;
			};
			defer framebuffer.deinit();

			framebuffer.clear_color(graphics.Color{ .r = 0, .g = 0, .b = 255 });
			const res = graphics.current_resolution();

			// const line_amount = std.mem.count(u8, msg, "\n");

			const y_offset: u32 = if (on_heap > 0) 32 else 16;
			framebuffer.draw_text_centered("KERNEL PANIC !", res.width/2, res.height/2-y_offset, fb.White, fb.Blue);

			if (on_heap > 0) {
				framebuffer.draw_text_centeredf("OBJECTS ON HEAP FROM BEFORE PANIC: {d}", .{on_heap}, res.width/2, res.height/2-16, fb.White, fb.Blue) catch |e| {
					break :blk e;
				};
			}

			framebuffer.draw_text_centered(msg, res.width/2, res.height/2+16, fb.White, fb.Blue);

			var input_works = true;
			_ = io.getkey() catch {
				input_works = false;
			};

			if (input_works) {

				framebuffer.draw_text_centered("Press `Esc` to load framebuffer state from before panic (debugging)\nPress `Enter` to attempt a software reboot (recommended)\nPress `Space` to attempt a hardware reboot\nPress `^C` to attempt a shutdown", res.width/2, res.height-80, fb.White, fb.Blue);

				var state = graphics.State.init(alloc) catch |e| {
					break :blk e;
				};
				defer {
					if (state.inited) state.deinit();
				}

				var framebuffer_before = graphics.Framebuffer.init(alloc) catch |e| {
					break :blk e;
				};
				defer framebuffer_before.deinit();

				framebuffer_before.load_state(state);
				state.deinit();

				framebuffer_before.draw_text_centered("Press `Esc` to go back to panic screen\nPress `Enter` to attempt a software reboot (recommended)\nPress `Space` to attempt a hardware reboot\nPress `^C` to attempt a shutdown", res.width/2, res.height-80, fb.White, fb.Blue);

				framebuffer.update() catch |e| {
					break :blk e;
				};

				var panic_state = graphics.State.init(alloc) catch |e| {
					break :blk e;
				};
				defer panic_state.deinit();

				var before_loaded = false;

				while (true) {
					const key = io.getkey() catch |e| {
						break :blk e;
					};

					if (key == null) continue;

					if (key.?.unicode.convert() == ' ') {
						framebuffer.draw_text_centered("Attempting to hardware reboot", res.width/2, 16, fb.White, fb.Blue);
						framebuffer.update() catch |e| {
							break :blk e;
						};
						sleepms(750) catch {};
						bs.hardware_reboot();
					} else if (key.?.unicode.char == 13) {
						framebuffer.draw_text_centered("Attempting to software reboot", res.width/2, 16, fb.White, fb.Blue);
						framebuffer.update() catch |e| {
							break :blk e;
						};
						sleepms(750) catch {};
						bs.software_reboot();
					} else if (key.?.scancode == 23) {
						if (!before_loaded) {
							framebuffer_before.update() catch |e| {
								break :blk e;
							};
						} else {
							framebuffer.update() catch |e| {
								break :blk e;
							};
						}
						before_loaded = !before_loaded;
					} else if (key.?.ctrl and key.?.unicode.convert() == 'c') {
						framebuffer.draw_text_centered("Attempting to shutdown", res.width/2, 16, fb.White, fb.Blue);
						framebuffer.update() catch |e| {
							break :blk e;
						};
						sleepms(750) catch {};
						bs.shutdown();
					}

				}

			} else {
				framebuffer.update() catch |e| {
					break :blk e;
				};
			}

		} catch {
			fb.set_color(fb.Red);
			fb.puts("KERNEL PANIC: ");
			fb.puts(msg);
			fb.puts("\n");
			fb.puts("OBJECTS ON HEAP: ");
			fb.print("{d}\n", .{heap.amount}) catch {
				io.println("{d}", .{heap.amount}) catch {
					io.puts("COULD NOT PRINT OBJECTS ON HEAP\n");
				};
			};
			fb.set_color(fb.White);
		});

	} else {
		io.puts("KERNEL PANIC: ");
		io.puts(msg);
		io.puts("\n");
		io.puts("OBJECTS ON HEAP: ");
		io.print("{d}\n", .{heap.amount}) catch {
			io.puts("COULD NOT PRINT OBJECTS ON HEAP\n");
		};
	}

	enter_loop();

}

fn kernel_panic(comptime format: []const u8, args: anytype) noreturn {

	const ArgsType = @TypeOf(args);
	const args_type_info = @typeInfo(ArgsType);
	const fields_info = args_type_info.Struct.fields;

	const alloc = heap.Allocator.init();

	const msg = blk: {
		if (fields_info.len == 0) {
			break :blk format;
		} else {
			break :blk io.alloc_print(alloc, format, args) catch {
				break :blk format;
			};
		}
	};

	defer {
		if (msg.ptr != format.ptr) alloc.free(msg);
	}

	kernel_panic_raw(msg);

	// // var graphics_worked = true;

	// if (graphics.has_inited()) {

	// 	// var framebuffer_worked = true;

	// 	(blk: {
	// 		var framebuffer = graphics.Framebuffer.init(alloc) catch |e| {
	// 			break :blk e;
	// 		};
	// 		defer framebuffer.deinit();

	// 		framebuffer.clear_color(graphics.Color{ .r = 0, .g = 0, .b = 255 });
	// 		const res = graphics.current_resolution();

	// 		// const line_amount = std.mem.count(u8, msg, "\n");

	// 		framebuffer.draw_text_centered("KERNEL PANIC !", res.width/2, res.height/2-32, fb.White, fb.Blue);

	// 		if (heap.amount > 0) {
	// 			framebuffer.draw_text_centeredf("OBJECTS ON HEAP: {d}", .{heap.amount}, res.width/2, res.height/2-16, fb.White, fb.Blue) catch |e| {
	// 				break :blk e;
	// 			};
	// 		}

	// 		framebuffer.draw_text_centered(msg, res.width/2, res.height/2+16, fb.White, fb.Blue);

	// 		framebuffer.update() catch |e| {
	// 			break :blk e;
	// 		};

	// 	} catch {
	// 		fb.set_color(fb.Red);
	// 		fb.puts("KERNEL PANIC: ");
	// 		fb.puts(msg);
	// 		fb.puts("\n");
	// 		fb.set_color(fb.White);
	// 	});

	// } else {
	// 	io.puts("KERNEL PANIC: ");
	// 	io.puts(msg);
	// 	io.puts("\n");
	// }

	// if (msg.ptr != format.ptr) alloc.free(msg);
	// enter_loop();

}

fn enter_loop() noreturn {
	bs.exit_services() catch {
		// print_either("EXIT SERVICES FAILED");
		// graphics.draw_rectangle(5, 5, 10, 10, fb.Red);

		while (true) {
			asm volatile ("hlt");
		}

	};

	// graphics.draw_rectangle(5, 5, 10, 10, fb.Green);

	// _ = bs.init() catch {
	// 	fb.puts("INIT FAILED");
	// };
	// fb.puts("done");

	print_either("Reached target kernel loop");

	while (true) {
		// if (graphics.has_inited()) {
		// 	fb.puts("TICK\n") catch {};
		// } else {
		// 	_ = uefi.system_table.con_out.?.outputString(&[_:0]u16{ 'T', 'I', 'C', 'K', '\r', '\n' });
		// }
		// sleepms(5000) catch {};
		asm volatile ("hlt");
	}
}

fn printf_either(comptime format: []const u8, args: anytype) void {
	if (graphics.has_inited()) {
		fb.println(format, args) catch {
			if (io.has_inited()) {
				io.println(format, args) catch {
					print_either(format);
				};
			} else {
				print_either(format);
			}
		};
	} else {
		io.println(format, args) catch {
			print_either(format);
		};
	}
}

fn print_either(comptime format: []const u8) void {
	if (graphics.has_inited()) {
		fb.puts(format ++ "\n");
	} else if (io.has_inited()) {
		io.puts(format ++ "\n");
	} else {
		for (format ++ "\n") |c| {
			if (c == '\n') {
				_ = uefi.system_table.con_out.?.outputString(&[2:0]u16{ '\r', 0 });
			}

			const c_ = [2]u16{ c, 0 };
			_ = uefi.system_table.con_out.?.outputString(@ptrCast(&c_));
		}
	}
}

pub fn main() void {

	// io.init_io();
	// io.println("KERNEL START", .{}) catch unreachable;
	for ("KERNEL START\r\n") |c| {
		const c_ = [2]u16{ c, 0 };
		_ = uefi.system_table.con_out.?.outputString(@ptrCast(&c_));
	}

	io.init_io() catch |e| {
		print_either("COULD NOT INIT IO");
		@panic(@errorName(e));
	};

	print_either("Reached target entry");
	const req = entry() catch |e| {
		// printf_either("KERNEL PANIC: {any}", .{e});
		// enter_loop();
		kernel_panic("On entry: {any}", .{e});
	};

	if (heap.amount != 0) {
		const msg = if (heap.amount > 1) "Detected memory leaks" else "Detected memory leak";
		kernel_panic_raw(msg);
	}

	switch (req) {
		Request.Exit => {},
		Request.Shutdown => {
			io.puts("Reached target shutdown");
			sleepms(1000) catch {};
			bs.exit_services() catch {
				io.puts("EXIT SERVICES FAILED");
				sleepms(5000) catch {};
			};
			bs.shutdown();
		},
		Request.Reboot => {
			io.puts("Reached target reboot");
			sleepms(1000) catch {};
			bs.exit_services() catch {
				io.puts("EXIT SERVICES FAILED");
				sleepms(5000) catch {};
			};
			bs.hardware_reboot();
		},
		else => {}
	}

	enter_loop();

}


