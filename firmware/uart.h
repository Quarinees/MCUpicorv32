#ifndef UART_H
#define UART_H

#include <stdint.h>

#define UART_BASE   0x02000000u
#define UART_DIV    (*(volatile uint32_t *)(UART_BASE + 0x00))
#define UART_DAT    (*(volatile uint32_t *)(UART_BASE + 0x04))

static inline void uart_init(uint32_t div)
{
    UART_DIV = div;
}

static inline void uart_putc(char c)
{
    UART_DAT = (uint32_t)(uint8_t)c;
}

static inline void uart_puts(const char *s)
{
    while (*s) uart_putc(*s++);
}

static inline void uart_putnl(void)
{
    uart_puts("\r\n");
}

static inline void uart_hex8(uint32_t v)
{
    static const char h[] = "0123456789ABCDEF";
    uart_putc(h[(v >> 4) & 0xF]);
    uart_putc(h[v & 0xF]);
}

static inline void uart_hex32(uint32_t v)
{
    static const char h[] = "0123456789ABCDEF";
    for (int i = 7; i >= 0; i--)
        uart_putc(h[(v >> (i * 4)) & 0xF]);
}

static inline void uart_dec(uint32_t v)
{
    char b[10];
    int n = 0;

    if (!v) {
        uart_putc('0');
        return;
    }

    while (v) {
        b[n++] = (char)('0' + (v % 10));
        v /= 10;
    }

    while (n--)
        uart_putc(b[n]);
}

#endif
