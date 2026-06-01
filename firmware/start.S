/* ===== RESET VECTOR ===== */
.section .vectors, "ax"
.global _start
.align 2
_start:
    j _reset


/* ===== IRQ VECTOR ===== */
.section .irq, "ax"
.global _irq_handler
.align 2
_irq_handler:
    j irq_entry


/* ===== MAIN CODE ===== */
.section .text, "ax"
.global _reset
.global irq_entry
.align 2

irq_entry:
    addi sp, sp, -16
    sw   t0,  0(sp)
    sw   t1,  4(sp)
    sw   t2,  8(sp)
    sw   ra, 12(sp)

    .word 0x0600006b
    call _irq_dispatch

    lw   ra, 12(sp)
    lw   t2,  8(sp)
    lw   t1,  4(sp)
    lw   t0,  0(sp)
    addi sp, sp, 16

    .word 0x0000000b


_reset:
    li sp, 0x00008000

    la t0, _bss_start
    la t1, _bss_end
1:
    bgeu t0, t1, 2f
    sw zero, 0(t0)
    addi t0, t0, 4
    j 1b
2:

    call main

hang:
    j hang


/**** DEFAULT IRQ DISPATCH ****/
.weak _irq_dispatch
.global _irq_dispatch
_irq_dispatch:
    ret
