#include <stdint.h>
#include <stddef.h>
void oled_hexbyte(uint8_t b);
void oled_hex(uint8_t v);
// ------------------------------------------------
// memcpy (bare-metal cần)
// ------------------------------------------------

void *memcpy(void *dest, const void *src, size_t n)
{
    unsigned char *d = dest;
    const unsigned char *s = src;

    while (n--)
        *d++ = *s++;

    return dest;
}

// ------------------------------------------------
// UART debug
// ------------------------------------------------

#define UART_DATA (*(volatile uint32_t*)0x10000000)

void putc(char c)
{
    UART_DATA = c;
}

void print(const char *s)
{
    while(*s) putc(*s++);
}

// ------------------------------------------------
// delay
// ------------------------------------------------

void delay()
{
    for(volatile int i=0;i<200000;i++);
}

// ------------------------------------------------
// I2C registers
// ------------------------------------------------

#define I2C_CTRL (*(volatile uint32_t*)0x30000000)
#define I2C_STAT (*(volatile uint32_t*)0x30000004)
#define I2C_TX0  (*(volatile uint32_t*)0x30000008)
#define I2C_RX0 (*(volatile uint32_t*)0x30000010)
#define I2C_BUSY 1
#define OLED_ADDR 0x3C
const uint8_t font_hex[16][5]={
{0x3E,0x51,0x49,0x45,0x3E},
{0x00,0x42,0x7F,0x40,0x00},
{0x42,0x61,0x51,0x49,0x46},
{0x21,0x41,0x45,0x4B,0x31},
{0x18,0x14,0x12,0x7F,0x10},
{0x27,0x45,0x45,0x45,0x39},
{0x3C,0x4A,0x49,0x49,0x30},
{0x01,0x71,0x09,0x05,0x03},
{0x36,0x49,0x49,0x49,0x36},
{0x06,0x49,0x49,0x29,0x1E},
{0x7E,0x11,0x11,0x11,0x7E},
{0x7F,0x49,0x49,0x49,0x36},
{0x3E,0x41,0x41,0x41,0x22},
{0x7F,0x41,0x41,0x22,0x1C},
{0x7F,0x49,0x49,0x49,0x41},
{0x7F,0x09,0x09,0x09,0x01}
};
// ------------------------------------------------
// I2C write 2 byte
// ------------------------------------------------
void i2c_wait()
{
    while(I2C_STAT & I2C_BUSY);
}
void oled_write(uint8_t ctrl, uint8_t data)
{
    i2c_wait();

    I2C_TX0 = ctrl | (data<<8);

    I2C_CTRL =
        OLED_ADDR |
        (0<<7) |
        (0<<8) |
        (0<<16) |
        (1<<17) |   // 2 byte
        (1u<<31);

    i2c_wait();
}
void esp32_write(uint8_t b0,uint8_t b1,uint8_t b2,uint8_t b3)
{
    i2c_wait();

    I2C_TX0 =
        (b0) |
        (b1<<8) |
        (b2<<16) |
        (b3<<24);

    I2C_CTRL =
        (0x42) |
        (0<<7) |
        (0<<8) |
        (0<<16) |
        (3<<17) |
        (1u<<31);

    i2c_wait();
}	

// ------------------------------------------------
// OLED helpers
// ------------------------------------------------

void oled_cmd(uint8_t cmd)
{
    oled_write(0x00,cmd);
}

void oled_data(uint8_t d)
{
    oled_write(0x40,d);
}

// ------------------------------------------------
// OLED init sequence
// ------------------------------------------------

void oled_init()
{
    delay();

    oled_cmd(0xAE); // display off
    oled_cmd(0x20);
    oled_cmd(0x00);

    oled_cmd(0xB0);
    oled_cmd(0xC8);
    oled_cmd(0x00);
    oled_cmd(0x10);

    oled_cmd(0x40);

    oled_cmd(0x81);
    oled_cmd(0x7F);

    oled_cmd(0xA1);
    oled_cmd(0xA6);

    oled_cmd(0xA8);
    oled_cmd(0x3F);

    oled_cmd(0xD3);
    oled_cmd(0x00);

    oled_cmd(0xD5);
    oled_cmd(0x80);

    oled_cmd(0xD9);
    oled_cmd(0xF1);

    oled_cmd(0xDA);
    oled_cmd(0x12);

    oled_cmd(0xDB);
    oled_cmd(0x40);

    oled_cmd(0x8D);
    oled_cmd(0x14);

    oled_cmd(0xAF); // display ON
}
void oled_hex(uint8_t v)
{
    for(int i=0;i<5;i++)
        oled_data(font_hex[v][i]);

    oled_data(0x00);
}
void oled_clear()
{
    for(int page=0;page<8;page++)
    {
        oled_cmd(0xB0+page);
        oled_cmd(0x00);
        oled_cmd(0x10);

        for(int i=0;i<128;i++)
            oled_data(0x00);
    }
}

// ------------------------------------------------
// Fill screen
// ------------------------------------------------
void oled_show_line(uint8_t page,
                    uint8_t b0,uint8_t b1,
                    uint8_t b2,uint8_t b3)
{
    oled_cmd(0xB0 + page);
    oled_cmd(0x00);
    oled_cmd(0x10);

    oled_hexbyte(b0); oled_data(0x00);
    oled_hexbyte(b1); oled_data(0x00);
    oled_hexbyte(b2); oled_data(0x00);
    oled_hexbyte(b3);
}
void oled_hexbyte(uint8_t b)
{
    oled_hex(b>>4);
    oled_hex(b&0xF);
}
uint32_t esp32_read()
{
    i2c_wait();

    I2C_CTRL =
        (0x42) |
        (1<<7) |
        (0<<8) |
        (0<<16) |
        (3<<17) |
        (1u<<31);

    i2c_wait();

    return I2C_RX0;
}
// ------------------------------------------------
// main
// ------------------------------------------------

int main()
{
    oled_init();
    oled_clear();

    while(1)
    {
        uint8_t w0=0x11;
        uint8_t w1=0x22;
        uint8_t w2=0x33;
        uint8_t w3=0x44;

        esp32_write(w0,w1,w2,w3);

        uint32_t r = esp32_read();

        uint8_t r0 = r & 0xFF;
        uint8_t r1 = (r>>8)&0xFF;
        uint8_t r2 = (r>>16)&0xFF;
        uint8_t r3 = (r>>24)&0xFF;

        oled_show_line(2,w0,w1,w2,w3);   // dòng write
        oled_show_line(4,r0,r1,r2,r3);   // dòng read

        delay();
    }
}
