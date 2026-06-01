OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    ram (rwx) : ORIGIN = 0x00000000, LENGTH = 32K
}

SECTIONS
{
    /* ===== RESET VECTOR (0x0000) ===== */
    .vectors 0x00000000 : {
        KEEP(*(.vectors))
    } > ram

    /* ===== IRQ VECTOR (0x0010) ===== */
    .irq 0x00000010 : {
        KEEP(*(.irq))
    } > ram

    /* ===== CODE (0x0020 trở đi) ===== */
    .text 0x00000020 : {
        *(.text.init)
        *(.text)
        *(.text.*)
    } > ram

    .rodata : {
        *(.rodata)
        *(.rodata.*)
    } > ram

    .data : {
        *(.data)
        *(.data.*)
    } > ram

    .bss : {
        PROVIDE(_bss_start = .);
        *(.bss)
        *(.bss.*)
        *(COMMON)
        PROVIDE(_bss_end = .);
    } > ram

    /* ===== STACK ===== */
    .stack : {
        PROVIDE(_stack_start = .);
        . = . + 4K;
        PROVIDE(_stack_top = .);
    } > ram
}
