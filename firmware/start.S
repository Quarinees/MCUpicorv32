.section .text.start
.global _start

_start:

    # stack pointer
    lui  sp, %hi(__stack_top)
    addi sp, sp, %lo(__stack_top)

    # clear .bss
    lui  a0, %hi(__bss_start)
    addi a0, a0, %lo(__bss_start)
    lui  a1, %hi(__bss_end)
    addi a1, a1, %lo(__bss_end)

1:
    bge  a0, a1, 2f
    sw   zero, 0(a0)
    addi a0, a0, 4
    j    1b

2:
    # call main
    jal  ra, main

3:
    j 3b
