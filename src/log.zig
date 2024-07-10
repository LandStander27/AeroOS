const graphics = @import("graphics.zig");
const fb = @import("fb.zig");
const io = @import("io.zig");
const rng = @import("rand.zig");
const sleepms = @import("time.zig").sleepms;

const nums: [2]u64 = .{ 75, 175 };

pub fn new_task(str: []const u8) void {
	if (graphics.has_inited()) {
		fb.set_color(fb.Orange);
		fb.print("{s} ", .{str}) catch {};
		fb.set_color(fb.White);
		fb.print("... ", .{}) catch {};
		fb.set_color(fb.Cyan);
		fb.print("Running", .{}) catch {};
		fb.right(-7);
		fb.set_color(fb.White);
	} else {
		io.puts(str);
		io.puts(" ... Running");
		io.right(-7);
		// io.print("{s} ... Running", .{str}) catch {};
		// io.right(-7);
	}
	var delay: u64 = (nums[0]+nums[1])/2;
	// if (rng.has_inited()) blk: {
	// 	if (rng.random(0, 10) catch break :blk > 8) {
	// 		delay = rng.random(nums[0]*3, nums[1]*3) catch (nums[0]+nums[1])/2;
	// 	} else {
	// 		delay = rng.random(nums[0], nums[1]) catch (nums[0]+nums[1])/2;
	// 	}
	// }
	blk: {
		if (rng.random(0, 10) catch break :blk > 8) {
			delay = rng.random(nums[0]*3, nums[1]*3) catch (nums[0]+nums[1])/2;
		} else {
			delay = rng.random(nums[0], nums[1]) catch (nums[0]+nums[1])/2;
		}
	}
	sleepms(delay) catch {};
}

pub fn finish_task() void {
	if (graphics.has_inited()) {
		fb.set_color(fb.Green);
		fb.println("Success   ", .{}) catch {};
		fb.set_color(fb.White);
	} else {
		// io.println("Success   ", .{}) catch {};
		io.puts("Success   \n");
	}
	// var delay: u64 = (nums[0]+nums[1])/2;
	// if (rng.has_inited()) {
	// 	delay = rng.random(nums[0], nums[1]) catch (nums[0]+nums[1])/2;
	// }
	// sleepms(delay) catch {};
}

pub fn error_task() void {
	if (graphics.has_inited()) {
		fb.set_color(fb.Red);
		fb.println("Failed   ", .{}) catch {};
		fb.set_color(fb.White);
	} else {
		// io.println("Failed   ", .{}) catch {};
		io.puts("Failed   \n");
	}
}

pub fn error_task_msg(comptime format: []const u8, args: anytype) void {
	if (graphics.has_inited()) {
		fb.set_color(fb.Red);
		fb.print("Failed: ", .{}) catch {};
		fb.set_color(fb.White);
		fb.println(format, args) catch {};
	} else {
		io.puts("Failed: ");
		// io.print("Failed: ", .{}) catch {};
		io.println(format, args) catch {
			io.puts(format);
		};
	}
}

