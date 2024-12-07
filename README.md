# AeroOS
- OS made from scratch in Zig with EFI support.

#### Note
- The library I created in order to make this has been turned into an actual library, located here: https://github.com/LandStander27/zig-efi-lib

## Usage
### Downloading
1. Go to latest build action at `https://git.kage.sj.strangled.net/Land/AeroOS/actions`.
2. Download the `iso.zip` artifact.
3. The ISO is contained in the downloaded zip.
#### Running with QEMU
1. Install QEMU/KVM and edk2-ovmf.
	* Arch Linux: `pacman -S qemu-desktop edk2-ovmf`.
2. `SIZE=4G`. Replace 4G with how much memory you want to give the Virtual Machine. 4GB is way more than enough.
3. `qemu-system-x86_64 -bios /usr/share/ovmf/x64/OVMF.fd -cdrom AeroOS.iso -device virtio-rng-pci -m $SIZE`.
### Building
#### Native
1. Install deps
	* Arch Linux:
		* `pacman -S make git mtools xorriso dosfstools cdrtools`.
		* `yay -S zigup-bin` (or any other AUR manager)
		* `zigup --path-link ~/.local/bin/zig 0.13.0`
	* Debian: `apt install make git mtools xorriso dosfstools`.
		* Note: Zig must be [installed manually](https://ziglang.org/download/) (there is no debian package).
2. `git clone https://git.kage.sj.strangled.net/Land/AeroOS && cd AeroOS`.
3. Building
	* Arch Linux: `make all`.
	* Debian: `make all prog="xorriso -as mkisofs"`.
4. ISO is built to `./AeroOS.iso`.

#### Docker
1. Install docker and GNU make.
2. `git clone https://git.kage.sj.strangled.net/Land/AeroOS && cd AeroOS`.
3. `make docker`.
4. ISO is built to `./AeroOS.iso`.

#### Running with QEMU
1. Install QEMU/KVM and edk2-ovmf.
	* Arch Linux: `pacman -S qemu-desktop edk2-ovmf`.
2. `make run`.
