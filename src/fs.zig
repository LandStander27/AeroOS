const std = @import("std");
const uefi = std.os.uefi;

const heap = @import("heap.zig");
const bs = @import("boot_services.zig");

var fs: ?*uefi.protocol.SimpleFileSystem = null;
var loaded_image: ?*uefi.protocol.LoadedImage = null;
var device_path: ?*uefi.protocol.DevicePath = null;

var root: ?*uefi.protocol.File = null;
const max_path = 255;

var alloc: heap.Allocator = undefined;

const fb = @import("fb.zig");
const log = @import("log.zig");

const ArrayList = @import("array.zig").ArrayList;

var current_path: ArrayList(u8) = undefined;

pub fn init(allocator: heap.Allocator) !void {
	alloc = allocator;
	const boot_services = try bs.init();

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

pub fn cwd() []const u8 {
	return current_path.items;
}

pub fn set_cwd(path: []const u8) !void {
	if (std.mem.eql(u8, path, ".")) {
		return;
	}

	if (std.mem.eql(u8, path, "..")) {
		if (current_path.items.len == 1) {
			return error.AlreadyAtRoot;
		}

		while (current_path.last().?.* != '/') {
			current_path.remove(current_path.items.len - 1);
		}

		if (current_path.items.len != 1) {
			current_path.remove(current_path.items.len - 1);
		}
		return;

	}

	const dir = try open_dir(current_path.items);
	defer dir.close() catch {};

	var exists = false;

	while (try dir.next()) |dirent| {
		defer dirent.free();
		if (std.mem.eql(u8, dirent.filename, path) and dirent.filetype == .Directory) {
			exists = true;
			break;
		}
	}

	if (!exists) {
		return error.NotFound;
	}

	if (current_path.last().?.* != '/') {
		try current_path.append('/');
	}

	try current_path.append_slice(path);
}

pub const FileType = enum {
	File,
	Directory,
};

pub const Info = struct {
	size: usize,
	filename: []const u8,
	filetype: FileType,

	pub fn free(self: *const Info) void {
		alloc.free(self.filename);
	}

};

fn get_filename(info: *uefi.FileInfo) ![]const u8 {
	const utf16_name = info.getFileName();

	var len: usize = 0;
	while (utf16_name[len] != 0) : (len += 1) {}

	var name = try alloc.alloc(u8, len);
	errdefer alloc.free(name);

	for (utf16_name[0..len], 0..) |c, i| {
		// try fb.println("{d}", .{c});
		name[i] = @truncate(c);
	}

	return name;
}

pub const File = struct {
	const Self = @This();

	file: *uefi.protocol.File,

	pub fn close(self: *const Self) !void {
		if (self.file.close() != uefi.Status.Success) {
			return error.CouldNotCloseFile;
		}
	}

	pub fn set_position(self: *const Self, pos: usize) !void {
		if (self.file.setPosition(pos) != uefi.Status.Success) {
			return error.CouldNotSetPosition;
		}
	}

	pub fn get_info(self: *const Self) !Info {
		var size: usize = 64;

		var info_buf: []align(8) u8 = @alignCast(try alloc.alloc(u8, size));
		defer alloc.free(info_buf);

		var res = self.file.getInfo(&uefi.FileInfo.guid, &size, info_buf.ptr);
		while (res == uefi.Status.BufferTooSmall) {
			size *= 2;
			alloc.free(info_buf);

			info_buf = @alignCast(try alloc.alloc(u8, size));

			res = self.file.getInfo(&uefi.FileInfo.guid, &size, info_buf.ptr);

			if (res != uefi.Status.Success and res != uefi.Status.BufferTooSmall) {
				try res.err();
				return error.CouldNotGetInfo;
			}

		}

		const info: *uefi.FileInfo = @ptrCast(info_buf);

		return .{
			.size = info.file_size,
			.filename = try get_filename(info),
			.filetype = if (info.attribute & uefi.protocol.File.efi_file_directory != 0) .Directory else .File
		};

	}

	pub fn read(self: *const Self, buf: *[]u8) !usize {

		var buf_size = buf.len;

		const res = self.file.read(&buf_size, buf.ptr);
		if (res != uefi.Status.Success) {
			try res.err();
			return error.CouldNotReadFile;
		}

		return buf_size;

	}

	pub fn read_all_alloc(self: *const Self) ![]u8 {

		const info = try self.get_info();
		defer info.free();

		var buf = try alloc.alloc(u8, info.size);
		errdefer alloc.free(buf);

		_ = try self.read(&buf);

		return buf;

	}

};

pub const Dir = struct {
	const Self = @This();

	file: *uefi.protocol.File,

	pub fn get_info(self: *const Self) !Info {
		var size: usize = 64;

		var info_buf: []align(8) u8 = @alignCast(try alloc.alloc(u8, size));
		defer alloc.free(info_buf);

		var res = self.file.getInfo(&uefi.FileInfo.guid, &size, info_buf.ptr);
		while (res == uefi.Status.BufferTooSmall) {
			size *= 2;
			alloc.free(info_buf);

			info_buf = @alignCast(try alloc.alloc(u8, size));

			res = self.file.getInfo(&uefi.FileInfo.guid, &size, info_buf.ptr);

			if (res != uefi.Status.Success and res != uefi.Status.BufferTooSmall) {
				try res.err();
				return error.CouldNotGetInfo;
			}

		}

		const info: *uefi.FileInfo = @ptrCast(info_buf);

		return .{
			.size = info.file_size,
			.filename = try get_filename(info),
			.filetype = if (info.attribute & uefi.protocol.File.efi_file_directory != 0) .Directory else .File
		};

	}

	pub fn close(self: *const Self) !void {
		if (self.file.close() != uefi.Status.Success) {
			return error.CouldNotCloseDir;
		}
	}

	pub fn restart(self: *const Self) !void {

		const res = self.file.setPosition(0);
		if (res != uefi.Status.Success) {
			try res.err();
			return error.CouldNotRestartDir;
		}

	}

	pub fn next(self: *const Self) !?Info {
		var size: usize = 64;

		var info_buf: []align(8) u8 = @alignCast(try alloc.alloc(u8, size));
		defer alloc.free(info_buf);

		var res = self.file.read(&size, info_buf.ptr);

		if (size == 0) {
			return null;
		}

		if (res != uefi.Status.Success and res != uefi.Status.BufferTooSmall) {
			try res.err();
			return error.CouldNotGetInfo;
		}

		while (res == uefi.Status.BufferTooSmall) {
			size *= 2;
			alloc.free(info_buf);

			info_buf = @alignCast(try alloc.alloc(u8, size));

			res = self.file.read(&size, info_buf.ptr);

			if (size == 0) {
				return null;
			}

			if (res != uefi.Status.Success and res != uefi.Status.BufferTooSmall) {
				try res.err();
				return error.CouldNotGetInfo;
			}

		}

		const info: *uefi.FileInfo = @ptrCast(info_buf);

		return .{
			.size = info.file_size,
			.filename = try get_filename(info),
			.filetype = if (info.attribute & uefi.protocol.File.efi_file_directory != 0) .Directory else .File
		};

	}

};

pub const FileMode = enum(u64) {
	Read = 0x0000000000000001,
	Write = 0x0000000000000002,
	Create = 0x0000000000000000,
};

fn convert(str: []const u8) !struct { buf : []u16, len : usize } {

	var prefix: ?[]u8 = null;
	defer {
		if (prefix) |p| {
			alloc.free(p);
		}
	}

	if (str[0] != '/') {
		const wkdir = cwd();
		prefix = try alloc.alloc(u8, wkdir.len);
		for (wkdir, 0..) |c, i| {
			prefix.?[i] = if (c != '/') c else '\\';
		}
		if (prefix.?[wkdir.len-1] != '\\') {
			prefix = try alloc.realloc(u8, prefix.?, wkdir.len+1);
			prefix.?[wkdir.len] = '\\';
		}
	}
	var buf: []u16 = try alloc.alloc(u16, max_path);

	if (prefix) |p| {
		for (p, 0..) |c, i| {
			buf[i] = @as(u16, c);
		}
	}

	const start = if (prefix) |p| p.len else 0;

	for (str, start..) |c, i| {
		buf[i] = @as(u16, c);
		if (c == '/') {
			buf[i] = @as(u16, '\\');
		}
	}
	buf[str.len+start] = 0;

	return .{
		.buf = buf,
		.len = str.len + start
	};
}

pub fn open_file(str: []const u8, mode: FileMode) !File {

	const tmp = try convert(str);
	const buf = tmp.buf;
	defer alloc.free(buf);

	const file_path: [:0]u16 = buf[0..tmp.len:0];

	// try fb.println("{any}, {any}", .{file_path, buf});
	var file: *uefi.protocol.File = undefined;
	const res = root.?.open(&file, file_path.ptr, @intFromEnum(mode), uefi.protocol.File.efi_file_system);
	if (res != uefi.Status.Success) {
		try res.err();
	}

	return .{
		.file = file,
	};
}

pub fn open_dir(str: []const u8) !Dir {

	const tmp = try convert(str);
	const buf = tmp.buf;
	defer alloc.free(buf);

	const file_path: [:0]u16 = buf[0..tmp.len:0];

	// try fb.println("{any}, {any}", .{file_path, buf});
	var file: *uefi.protocol.File = undefined;
	const res = root.?.open(&file, file_path.ptr, @intFromEnum(FileMode.Read), uefi.protocol.File.efi_file_system | uefi.protocol.File.efi_file_directory | uefi.protocol.File.efi_file_read_only);
	if (res != uefi.Status.Success) {
		try res.err();
	}

	return .{
		.file = file,
	};
}

pub fn deinit() void {
	if (current_path.attached) {
		log.new_task("DeinitFS");
		current_path.deinit();
		log.finish_task();
	}
}

pub fn mount_root() !void {
	log.new_task("MountRootFS");
	errdefer log.error_task();
	if (fs.?.openVolume(@ptrCast(&root)) != uefi.Status.Success) {
		return error.CouldNotMountRoot;
	}
	log.finish_task();

	log.new_task("CurrentDirectory");
	current_path = try ArrayList(u8).init(alloc);
	try current_path.append('/');
	log.finish_task();

}

pub fn umount_root() !void {
	log.new_task("UmountRootFS");
	errdefer log.error_task();
	if (root.?.close() != uefi.Status.Success) {
		return error.CouldNotUnmountRoot;
	}
	log.finish_task();

	deinit();

}
