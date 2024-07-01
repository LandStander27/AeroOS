FROM greyltc/archlinux-aur:yay
RUN pacman -Syu --noconfirm
RUN pacman --noconfirm -S make git mtools xorriso dosfstools cdrtools
RUN aur-install zigup-bin
RUN zigup 0.13.0
WORKDIR /mnt
CMD [ "make", "setup", "build", "clean" ]