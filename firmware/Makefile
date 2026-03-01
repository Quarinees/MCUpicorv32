RISCV_PREFIX = riscv32-unknown-elf-

CC = $(RISCV_PREFIX)gcc
OBJCOPY = $(RISCV_PREFIX)objcopy

CFLAGS = -Os -march=rv32im -mabi=ilp32 -nostdlib -nostartfiles -ffreestanding -Wall
LDFLAGS = -T linker.ld

all: firmware.hex

firmware.elf: start.S main.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ start.S main.c

firmware.bin: firmware.elf
	$(OBJCOPY) -O binary $< $@

firmware.hex: firmware.elf
	$(OBJCOPY) -O verilog $< $@

clean:
	rm -f *.elf *.bin *.hex
