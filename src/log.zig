const graphics = @import("graphics.zig");
const fb = @import("fb.zig");
const io = @import("io.zig");

pub fn new_task(str: []const u8) void {
	if (graphics.has_inited()) {
		fb.set_color(fb.Orange);
		fb.print("{s} ", .{str}) catch {};
		fb.set_color(fb.White);
		fb.print("... ", .{}) catch {};
	} else {
		io.print("{s} ... ", .{str}) catch {};
	}
}

pub fn finish_task() void {
	if (graphics.has_inited()) {
		fb.set_color(fb.Green);
		fb.println("Success", .{}) catch {};
		fb.set_color(fb.White);
	} else {
		io.println("Success", .{}) catch {};
	}
}

pub fn error_task() void {
	if (graphics.has_inited()) {
		fb.set_color(fb.Red);
		fb.println("Failed", .{}) catch {};
		fb.set_color(fb.White);
	} else {
		io.println("Failed", .{}) catch {};
	}
}
