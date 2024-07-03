### AeroOS
- OS made from scratch in Zig with EFI support.

#### Building
##### Native
1. Install deps
	* Arch Linux: `pacman -S zig make git mtools xorriso dosfstools cdrtools`
	* Debian: `apt install make git mtools xorriso dosfstools`
		* Note: Zig must be [installed manually](https://ziglang.org/download/) (there is no debian package)
2. `git clone https://github.com/LandStander27/AeroOS && cd AeroOS`
3. Building
	* Arch Linux: `make all`
	* Debian: `make all prog="xorriso -as mkisofs"`
4. ISO is built to `./AeroOS.iso`.

##### Docker
1. Install docker and GNU make
2. `git clone https://github.com/LandStander27/AeroOS && cd AeroOS`
3. `make docker`
4. ISO is built to `./AeroOS.iso`.

##### Running
1. Install QEMU/KVM
2. `make run`