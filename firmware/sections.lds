OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 32K
}

SECTIONS {

    . = ORIGIN(RAM);

    /* code + rodata */
    .text : {
        KEEP(*(.text.start))
        *(.text*)
        *(.rodata*)
        . = ALIGN(4);
    } > RAM

    /* initialized data */
    .data : {
        __data_start = .;
        *(.data*)
        __data_end = .;
        . = ALIGN(4);
    } > RAM

    /* zero-initialized data */
    .bss : {
        . = ALIGN(4);
        __bss_start = .;
        *(.bss*)
        *(COMMON)
        __bss_end = .;
        . = ALIGN(4);
    } > RAM

    _end = .;

    /* stack pointer */
    __stack_top = ORIGIN(RAM) + LENGTH(RAM);
}
