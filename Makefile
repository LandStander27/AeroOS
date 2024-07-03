prog = "mkisofs"
dockerflags =

all:
	make setup
	make build
	make clean

setup:
	mkdir -p bin/EFI/BOOT
	dd if=/dev/zero of=bin/EFI/BOOT/boot.img bs=1M count=12
	mkfs.msdos -F 12 -n 'BOOT' bin/EFI/BOOT/boot.img
	mmd -i bin/EFI/BOOT/boot.img ::EFI
	mmd -i bin/EFI/BOOT/boot.img ::EFI/BOOT

docker:
	docker build -t aerobuilder .
	docker run -h aerobuilder --name aerobuilder $(dockerflags) --rm -v .:/mnt aerobuilder
	docker image rm aerobuilder

build:
	zig build -Doptimize=ReleaseSafe --verbose
	rm bin/EFI/BOOT/bootx64.pdb
	-mdel -i bin/EFI/BOOT/boot.img ::EFI/BOOT/bootx64.efi
	mcopy -i bin/EFI/BOOT/boot.img bin/EFI/BOOT/bootx64.efi ::EFI/BOOT
	$(prog) -o AeroOS.iso -R -J -v -d -N -no-emul-boot -eltorito-platform efi -eltorito-boot EFI/BOOT/boot.img -V "BOOT" -A "Boot" bin

run:
	qemu-system-x86_64 -bios /usr/share/ovmf/x64/OVMF.fd -cdrom AeroOS.iso -m 4G -device virtio-rng-pci

clean:
	rm -rf bin .zig-cache zig-out
