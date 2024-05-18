const std = @import("std");
const uefi = std.os.uefi;

var fs: ?*uefi.protocol.SimpleFileSystem = null;
var loaded_image: ?*uefi.protocol.LoadedImage = null;
var device_path: ?*uefi.protocol.DevicePath = null;

var root: ?*uefi.protocol.File = null;

const fb = @import("fb.zig");

const log = @import("log.zig");

pub fn init() !void {
	const boot_services = uefi.system_table.boot_services.?;

	errdefer log.error_task();

	log.new_task("LoadedImage");
	if (boot_services.handleProtocol(uefi.handle, &uefi.protocol.LoadedImage.guid, @ptrCast(&loaded_image)) != uefi.Status.Success) {
		return error.NoLoadedImage;
	}
	log.finish_task();

	log.new_task("DevicePath");
	if (boot_services.handleProtocol(loaded_image.?.device_handle.?, &uefi.protocol.DevicePath.guid, @ptrCast(&device_path)) != uefi.Status.Success) {
		return error.NoDevicePath;
	}
	log.finish_task();

	log.new_task("Filesystem");
	if (boot_services.handleProtocol(loaded_image.?.device_handle.?, &uefi.protocol.SimpleFileSystem.guid, @ptrCast(&fs)) != uefi.Status.Success) {
		return error.NoFilesystem;
	}
	log.finish_task();

}

pub const File = struct {
	const Self = @This();

	file: *uefi.protocol.File,

	fn close(self: *const Self) !void {
		if (self.file.close() != uefi.Status.Success) {
			return error.CouldNotCloseFile;
		}
	}
};

pub const Dir = struct {
	const Self = @This();

	file: *uefi.protocol.File,

	pub fn close(self: *const Self) !void {
		if (self.file.close() != uefi.Status.Success) {
			return error.CouldNotCloseFile;
		}
	}
};

pub const FileMode = enum(u64) {
	Read = 0x0000000000000001,
	Write = 0x0000000000000002,
	Create = 0x0000000000000000,
};

fn convert(str: []const u8) ![:0]u16 {
	var buf: [255]u16 = undefined;

	const amount = try std.unicode.utf8ToUtf16LeImpl(buf[0..], str, .cannot_encode_surrogate_half);
	buf[amount] = 0;

	var buf2: [255]u16 = undefined;
	_ = std.mem.replace(u16, buf[0..amount], std.unicode.utf8ToUtf16LeStringLiteral("/"), std.unicode.utf8ToUtf16LeStringLiteral("\\"), &buf2);
	buf2[amount] = 0;
	return buf2[0 .. amount:0];
}

pub fn open_file(str: []const u8, mode: FileMode) !File {
	const buf = try convert(str);
	var file: *uefi.protocol.File = undefined;
	if (root.?.open(&file, buf.ptr, @intFromEnum(mode), 0) != uefi.Status.Success) {
		return error.CouldNotOpenFile;
	}
	return .{
		.file = file,
	};
}

pub fn open_dir(str: []const u8) !Dir {
	const buf = try convert(str);
	var file: *uefi.protocol.File = undefined;
	if (root.?.open(&file, buf.ptr, @intFromEnum(FileMode.Read), 0x0000000000000010) != uefi.Status.Success) {
		return error.CouldNotOpenFile;
	}
	var size: u64 = 10;
	var a: [10]u8 = undefined;
	if (file.read(&size, @ptrCast(&a)) != uefi.Status.Success) {
		return error.CouldNotReadFile;
	}
	try fb.println("a: {s}", .{a});
	return .{
		.file = file,
	};
}

pub fn mount_root() !void {
	log.new_task("MountRootFS");
	if (fs.?.openVolume(@ptrCast(&root)) != uefi.Status.Success) {
		return error.CouldNotMountRoot;
	}
	log.finish_task();
}

pub fn umount_root() !void {
	log.new_task("UmountRootFS");
	if (root.?.close() != uefi.Status.Success) {
		return error.CouldNotUnmountRoot;
	}
	log.finish_task();
}
