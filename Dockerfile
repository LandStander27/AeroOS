FROM archlinux:latest
# RUN pacman -Syu --noconfirm
RUN pacman --noconfirm -Sy make git mtools xorriso dosfstools cdrtools wget
RUN wget http://land-sj.ddns.net/zigup-bin.pkg.tar.zst
RUN pacman --noconfirm -U zigup-bin.pkg.tar.zst
RUN zigup 0.13.0
WORKDIR /mnt
# CMD [ "make", "all", ";", "chmod", "333", "./AeroOS.iso" ]
# RUN umask 444
CMD [ "make", "all" ]