#!/bin/sh

buffer:
	nasm subst.asm -o ./bin/SUBST.COM -f bin -l ./lst/subst.lst -O0v
