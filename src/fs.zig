const std = @import("std");
const uefi = std.os.uefi;

const heap = @import("heap.zig");

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
	if (root.?.open(&file, buf.ptr, uefi.protocol.File.efi_file_mode_read, uefi.protocol.File.efi_file_directory) != uefi.Status.Success) {
		return error.CouldNotOpenFile;
	}

	// NOTHING WORKSSSSSSSSS!!!!

	// // const size: u64 = 2;
	// // var alloc = @import("heap.zig").Allocator.init();
	// // const a: []u8 = try alloc.alloc(u8, size);
	// // defer alloc.free(a);
	// // // if (file.read(&size, &a) != uefi.Status.Success) {
	// // // 	return error.CouldNotReadFile;
	// // // }
	// // const reader = file.reader();
	// // for (0..size) |i| {
	// // 	a[i] = try reader.readByte();
	// // }
	// // try fb.println("a: {s}", .{a});
	// for (0..10) |_| {
	// 	var size: usize = 1;
	// 	var a: [1]u8 = [_]u8{0};
	// 	a[0] = 64;
	// 	const stat = file._read(file, &size, &a);
	// 	try fb.println("a: {any}, {c}", .{ stat, a[0] });
	// }

	// var size: usize = 0;
	// if (file.getInfo(&uefi.FileInfo.guid, &size, &[0]u8{}) != uefi.Status.BufferTooSmall) {
	// 	return error.FileInfoSize;
	// }

	// var alloc = heap.Allocator.init();
	// const buffer = try alloc.alloc(u8, size);
	// defer alloc.free(buffer);
	// if (file.getInfo(&uefi.FileInfo.guid, &size, buffer.ptr) != uefi.Status.Success) {
	// 	return error.FileInfo;
	// }

	// const info: *align(8) const uefi.FileInfo = @alignCast(@as(*align(1) const uefi.FileInfo, @ptrCast(buffer)));
	// try fb.println("a: {s}", .{info.getFileName()});

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
