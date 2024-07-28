#!/bin/sh

gcc -Wall -Werror -m64 -mabi=ms -Wl,--oformat=binary -e main -c main.c -o main.bin