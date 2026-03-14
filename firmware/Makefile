# =============================================================
#  Makefile – PicoRV32 firmware builder
# =============================================================

# -------------------------------------------------------------
# Toolchain
# -------------------------------------------------------------
CROSS ?= riscv32-unknown-elf

CC      = $(CROSS)-gcc
OBJCOPY = $(CROSS)-objcopy
OBJDUMP = $(CROSS)-objdump
SIZE    = $(CROSS)-size

# -------------------------------------------------------------
# ISA / ABI
# -------------------------------------------------------------
ARCH ?= rv32i
ABI  ?= ilp32

# -------------------------------------------------------------
# Target
# -------------------------------------------------------------
TARGET ?= firmware
SRCS   ?= start.S main.c
LDS    ?= sections.lds

# -------------------------------------------------------------
# RAM depth (match picorv32_ram.v)
# -------------------------------------------------------------
MEM_WORDS ?= 8192

# -------------------------------------------------------------
# Compiler flags
# -------------------------------------------------------------
CFLAGS = -march=$(ARCH) -mabi=$(ABI) \
         -Os \
         -ffreestanding -nostdlib \
         -fno-builtin -fno-stack-protector \
         -ffunction-sections -fdata-sections \
         -Wall -Wextra \
         -I.

LDFLAGS = -T $(LDS) \
          -nostdlib \
          -Wl,--gc-sections \
          -Wl,--no-relax \
          -Wl,-Map=$(TARGET).map \
          -lgcc

# =============================================================
# Rules
# =============================================================

.PHONY: all clean cleanall disasm size help

all: $(TARGET).elf $(TARGET).bin $(TARGET).hex
	@echo ""
	@echo "========================================="
	@$(SIZE) $(TARGET).elf
	@echo "-----------------------------------------"
	@echo "$(TARGET).hex -> $$(wc -l < $(TARGET).hex) / $(MEM_WORDS) words"
	@echo "Use in Verilog:"
	@echo "  \$\$readmemh(\"$(TARGET).hex\", memory);"
	@echo "========================================="

# -------------------------------------------------------------
# ELF
# -------------------------------------------------------------
$(TARGET).elf: $(SRCS) $(LDS)
	$(CC) $(CFLAGS) $(SRCS) $(LDFLAGS) -o $@

# -------------------------------------------------------------
# BIN
# -------------------------------------------------------------
$(TARGET).bin: $(TARGET).elf
	$(OBJCOPY) -O binary $< $@

# -------------------------------------------------------------
# HEX for $readmemh
# -------------------------------------------------------------
$(TARGET).hex: $(TARGET).bin
	python3 -c 'import struct;mem=$(MEM_WORDS);d=open("$(TARGET).bin","rb").read();w=[struct.unpack("<I",d[i:i+4].ljust(4,b"\0"))[0] for i in range(0,len(d),4)];w+=[0]*(mem-len(w));open("$(TARGET).hex","w").write("\n".join(f"{x:08x}" for x in w))'
	@echo "[HEX] generated $(MEM_WORDS) words"

# -------------------------------------------------------------
# Disassembly
# -------------------------------------------------------------
disasm: $(TARGET).elf
	$(OBJDUMP) -d -M no-aliases -S $<

# -------------------------------------------------------------
# Size
# -------------------------------------------------------------
size: $(TARGET).elf
	$(SIZE) -A $<

# -------------------------------------------------------------
# Clean
# -------------------------------------------------------------
clean:
	rm -f $(TARGET).elf $(TARGET).bin $(TARGET).hex $(TARGET).map

cleanall:
	rm -f *.elf *.bin *.hex *.map

# -------------------------------------------------------------
# Help
# -------------------------------------------------------------
help:
	@echo "make            build firmware"
	@echo "make disasm     show assembly"
	@echo "make size       section sizes"
	@echo "make clean      remove build files"
