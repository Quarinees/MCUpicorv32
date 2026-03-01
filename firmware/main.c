#include <stdint.h>

// ===============================
// Memory map
// ===============================
#define UART_BASE 0x10000000
#define I2C_BASE  0x30000000

// ===============================
// MMIO
// ===============================
static inline void mmio_write(uint32_t addr, uint32_t value)
{
    *(volatile uint32_t *)addr = value;
}

static inline uint32_t mmio_read(uint32_t addr)
{
    return *(volatile uint32_t *)addr;
}

// ===============================
// UART
// ===============================
void uart_putc(char c)
{
    mmio_write(UART_BASE, c);
}

void uart_print(const char *s)
{
    while (*s)
        uart_putc(*s++);
}

// ===============================
// I2C bridge
// bit8 = DCn
// bit7:0 = data
// ===============================
void i2c_wait()
{
    while (mmio_read(I2C_BASE) & 1);
}

void i2c_send(uint8_t dcn, uint8_t data)
{
    i2c_wait();
    mmio_write(I2C_BASE, (dcn << 8) | data);
}

// ===============================
// OLED low level
// ===============================
void oled_cmd(uint8_t cmd)
{
    i2c_send(0, cmd);
}

void oled_data(uint8_t data)
{
    i2c_send(1, data);
}

void oled_init()
{
    oled_cmd(0xAE);
    oled_cmd(0xD5);
    oled_cmd(0x80);
    oled_cmd(0xA8);
    oled_cmd(0x3F);
    oled_cmd(0xD3);
    oled_cmd(0x00);
    oled_cmd(0x40);
    oled_cmd(0x8D);
    oled_cmd(0x14);
    oled_cmd(0x20);
    oled_cmd(0x00);
    oled_cmd(0xA1);
    oled_cmd(0xC8);
    oled_cmd(0xDA);
    oled_cmd(0x12);
    oled_cmd(0x81);
    oled_cmd(0x7F);
    oled_cmd(0xD9);
    oled_cmd(0xF1);
    oled_cmd(0xDB);
    oled_cmd(0x40);
    oled_cmd(0xA4);
    oled_cmd(0xA6);
    oled_cmd(0xAF);
}

// ===============================
// Framebuffer
// ===============================
#define WIDTH  128
#define HEIGHT 64

uint8_t framebuffer[WIDTH * 8];

void fb_clear()
{
    for (int i = 0; i < WIDTH * 8; i++)
        framebuffer[i] = 0;
}

void fb_set_pixel(int x, int y)
{
    if (x < 0 || x >= WIDTH) return;
    if (y < 0 || y >= HEIGHT) return;

    int page = y >> 3;
    int bit  = y & 7;

    framebuffer[page * WIDTH + x] |= (1 << bit);
}

void oled_flush()
{
    for (int page = 0; page < 8; page++)
    {
        oled_cmd(0xB0 | page);
        oled_cmd(0x00);
        oled_cmd(0x10);

        for (int col = 0; col < WIDTH; col++)
            oled_data(framebuffer[page * WIDTH + col]);
    }
}

// ===============================
// RNG
// ===============================
static uint32_t rng = 1;

uint32_t rand32()
{
    rng ^= rng << 13;
    rng ^= rng >> 17;
    rng ^= rng << 5;
    return rng;
}

// ===============================
// Matrix demo
// ===============================
int drops[WIDTH];

void matrix_init()
{
    for (int i = 0; i < WIDTH; i++)
        drops[i] = rand32() % HEIGHT;
}

void matrix_step()
{
    fb_clear();

    for (int x = 0; x < WIDTH; x++)
    {
        drops[x]++;

        if (drops[x] >= HEIGHT)
            drops[x] = rand32() % 16;

        fb_set_pixel(x, drops[x]);

        for (int t = 1; t < 5; t++)
            fb_set_pixel(x, drops[x] - t);
    }

    oled_flush();
}

// ===============================
// MAIN
// ===============================
int main()
{
    for (volatile int i = 0; i < 1000000; i++);

    oled_init();
    matrix_init();

    uart_print("Matrix demo start\n");

    while (1)
    {
        matrix_step();
        for (volatile int i = 0; i < 20000; i++);
    }

    return 0;
}
