const std = @import("std");
const fs = @import("fs.zig");
const fb = @import("fb.zig");
const heap = @import("heap.zig");
const log = @import("log.zig");

const Elf64Addr = u64;
const Elf64Half = u16;
const Elf64Off = u64;
const Elf64Word = u32;
const Elf64XWord = u64;

const EI_MAG0: usize = 0;
const EI_MAG1: usize = 1;
const EI_MAG2: usize = 2;
const EI_MAG3: usize = 3;
const EI_CLASS: usize = 4;
const EI_DATA: usize = 5;
const EI_VERSION: usize = 6;
const EI_NIDENT: usize = 16;

const ELFMAG0: u8 = 0x7F;
const ELFMAG1: u8 = 'E';
const ELFMAG2: u8 = 'L';
const ELFMAG3: u8 = 'F';

const ELFCLASS64: u8 = 2;
const ELFDATA2LSB: u8 = 1;
const EV_CURRENT: u8 = 1;
const ET_EXEC: Elf64Half = 2;
const EM_AMD64: Elf64Half = 62;
const PT_LOAD: Elf64Word = 1;

const Elf64Ehdr = extern struct {
    e_ident: [16]u8,
    e_type: Elf64Half,
    e_machine: Elf64Half,
    e_version: Elf64Word,
    e_entry: Elf64Addr,
    e_phoff: Elf64Off,
    e_shoff: Elf64Off,
    e_flags: Elf64Word,
    e_ehsize: Elf64Half,
    e_phentsize: Elf64Half,
    e_phnum: Elf64Half,
    e_shentsize: Elf64Half,
    e_shnum: Elf64Half,
    e_shstrndx: Elf64Half,
};

const Elf64Phdr = extern struct {
    p_type: Elf64Word,
    p_flags: Elf64Word,
    p_offset: Elf64Off,
    p_vaddr: Elf64Addr,
    p_paddr: Elf64Addr,
    p_filesz: Elf64XWord,
    p_memsz: Elf64XWord,
    p_align: Elf64XWord,
};

// pub fn free_hdr(hdr: *const Elf64Ehdr) void {

// 	// const data: [*]u8 = @ptrCast(@constCast(@alignCast(hdr)));
// 	// const a = heap.Allocator.init();
// 	// a.free(data[0..@sizeOf(@TypeOf(hdr.*))]);

// }

pub fn load_exe(alloc: heap.Allocator) !*const Elf64Ehdr {

	const exe = try fs.open_file("/files/exe/zig/main", .Read);
	defer exe.close() catch |e| {
		fb.println("Error: {s}", .{@errorName(e)}) catch {};
	};

	const data = try exe.read_all_alloc();
	errdefer alloc.free(data);

	const hdr: *const Elf64Ehdr = @ptrCast(@alignCast(data.ptr));

	log.new_task("VerifyELF");
	errdefer log.error_task();

	if (hdr.e_ident[EI_MAG0] != ELFMAG0 or hdr.e_ident[EI_MAG1] != ELFMAG1 or hdr.e_ident[EI_MAG2] != ELFMAG2 or hdr.e_ident[EI_MAG3] != ELFMAG3) {
		return error.InvalidELFMag;
	}

	if (hdr.e_ident[EI_CLASS] != ELFCLASS64) {
		return error.InvalidClass;
	}

	if (hdr.e_ident[EI_DATA] != ELFDATA2LSB) {
		return error.InvalidDataOrder;
	}

    if (hdr.e_ident[EI_VERSION] != EV_CURRENT or hdr.e_version != EV_CURRENT) {
        return error.InvalidVersion;
    }

	if (hdr.e_type != ET_EXEC) {
		return error.InvalidType;
	}

	if (hdr.e_machine != EM_AMD64) {
		return error.InvalidMachine;
	}
	log.finish_task();

	var phdrs = try alloc.alloc(Elf64Phdr, hdr.e_phnum);
	defer alloc.free(phdrs);

	try exe.set_position(hdr.e_phoff);
	_ = try exe.read(@as(*[]u8, @ptrCast(&phdrs)));

	log.new_task("LoadELF");

	var phdr = &phdrs[0];
	while (true) {
		phdr = @ptrFromInt(@intFromPtr(phdr) + hdr.e_phentsize);
		if (phdr.p_type == PT_LOAD) {
			var segment: Elf64Addr = phdr.p_paddr;
			const ptr: [*]u8 = @ptrCast(&segment);
			const buf = ptr[0..1];
			try alloc.create_addr(Elf64Addr, @intFromPtr(&segment));

			// try exe.set_position(999999);
			// var a: [8]u8 = undefined;
			// _ = exe.read(a) catch {
			// 	return error.CantRead;
			// };

			try exe.set_position(phdr.p_offset);
			_ = try exe.read(&buf);

		}
	}

	log.finish_task();

	return hdr;

    // var phdr_ptr = data.ptr + hdr.e_phoff;
    // var phdr: *const Elf64Phdr = @ptrCast(@alignCast(phdr_ptr));
    // var i: usize = 0;
    // while (i < hdr.e_phnum) {
    //     if (phdr.p_type == PT_LOAD) {
	// 		const buf: [*]u8 = @ptrFromInt(phdr.p_paddr);
	// 		var buf2 = buf[0..phdr.p_memsz];
    //         buf2 = try alloc.alloc(u8, phdr.p_memsz);
	// 		defer alloc.free(buf2);

    //         if (phdr.p_filesz > 0) {
    //             // uefi::memory::copy_mem(
    //             //     phdr.p_paddr as *mut c_void,
    //             //     unsafe { file.as_ptr().offset(phdr.p_offset as isize) as *const c_void },
    //             //     phdr.p_filesz as usize,
    //             // );
	// 			// std.mem.copyForwards(u8, buf.*, data.ptr + phdr.p_offset);
	// 			for (0..phdr.p_filesz) |j| {
	// 				buf[j] = data[phdr.p_offset + j];
	// 			}
    //         }

    //         const diff = phdr.p_memsz - phdr.p_filesz;
    //         const start: *u8 = @ptrFromInt(phdr.p_paddr + phdr.p_filesz);
    //         var j: usize = 0;
    //         while (j < diff) {
	// 			@as(*u8, @ptrFromInt(@intFromPtr(start) + j)).* = 0;
    //             j += 1;
    //         }
    //     }

    //     i += 1;
    //     phdr_ptr = phdr_ptr + hdr.e_phentsize; // unsafe { phdr_ptr.offset( as isize) };
    //     phdr = @ptrCast(@alignCast(phdr_ptr));
    // }

	// return hdr;

}
