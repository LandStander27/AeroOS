### Zig OS
- OS made from scratch in Zig with EFI support.

#### Building
1. Install deps
	* Arch Linux: `pacman -S zig make git mtools xorriso dosfstools cdrtools`
	* Debian: `apt install make git mtools xorriso dosfstools`
		* Note: Zig must be [installed manually](https://ziglang.org/download/) (there is no debian package)
2. `git clone https://github.com/LandStander27/zig-os && cd zig-os`
3. Building
	* Arch Linux: `make all`
	* Debian: `make all prog="xorriso -as mkisofs"`
4. ISO is built to `./boot.iso`.

##### Running
1. Install QEMU/KVM
2. `make run`