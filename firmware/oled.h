#ifndef OLED_H
#define OLED_H

#include <stdint.h>
#include "i2c.h"

// =========================================================
// Cấu hình OLED
// =========================================================
#define OLED_ADDR   0x3C
#define OLED_W      128

// =========================================================
// Khai báo hàm phụ trợ (được cung cấp bởi main hoặc utils)
// =========================================================
extern void delay_ms(uint32_t ms);
extern int  str_len(const char *s);

// =========================================================
// Font Data
// =========================================================
static const uint8_t font_space[5]   = {0x00, 0x00, 0x00, 0x00, 0x00};
static const uint8_t font_colon[5]   = {0x00, 0x36, 0x36, 0x00, 0x00};
static const uint8_t font_equal[5]   = {0x14, 0x14, 0x14, 0x14, 0x14};
static const uint8_t font_percent[5] = {0x23, 0x13, 0x08, 0x64, 0x62};
static const uint8_t font_dot[5]     = {0x00, 0x60, 0x60, 0x00, 0x00};
static const uint8_t font_minus[5]   = {0x08, 0x08, 0x08, 0x08, 0x08};

static const uint8_t font_digit[10][5] = {
    {0x3E, 0x51, 0x49, 0x45, 0x3E}, /* 0 */
    {0x00, 0x42, 0x7F, 0x40, 0x00}, /* 1 */
    {0x42, 0x61, 0x51, 0x49, 0x46}, /* 2 */
    {0x21, 0x41, 0x45, 0x4B, 0x31}, /* 3 */
    {0x18, 0x14, 0x12, 0x7F, 0x10}, /* 4 */
    {0x27, 0x45, 0x45, 0x45, 0x39}, /* 5 */
    {0x3C, 0x4A, 0x49, 0x49, 0x30}, /* 6 */
    {0x01, 0x71, 0x09, 0x05, 0x03}, /* 7 */
    {0x36, 0x49, 0x49, 0x49, 0x36}, /* 8 */
    {0x06, 0x49, 0x49, 0x29, 0x1E}, /* 9 */
};

static const uint8_t font_A[5] = {0x7E, 0x11, 0x11, 0x11, 0x7E};
static const uint8_t font_B[5] = {0x7F, 0x49, 0x49, 0x49, 0x36};
static const uint8_t font_C[5] = {0x3E, 0x41, 0x41, 0x41, 0x22};
static const uint8_t font_D[5] = {0x7F, 0x41, 0x41, 0x22, 0x1C};
static const uint8_t font_E[5] = {0x7F, 0x49, 0x49, 0x49, 0x41};
static const uint8_t font_F[5] = {0x7F, 0x09, 0x09, 0x09, 0x01};
static const uint8_t font_G[5] = {0x3E, 0x41, 0x49, 0x49, 0x7A};
static const uint8_t font_H[5] = {0x7F, 0x08, 0x08, 0x08, 0x7F};
static const uint8_t font_I[5] = {0x00, 0x41, 0x7F, 0x41, 0x00};
static const uint8_t font_J[5] = {0x20, 0x40, 0x41, 0x3F, 0x01};
static const uint8_t font_K[5] = {0x7F, 0x08, 0x14, 0x22, 0x41};
static const uint8_t font_L[5] = {0x7F, 0x40, 0x40, 0x40, 0x40};
static const uint8_t font_M[5] = {0x7F, 0x02, 0x0C, 0x02, 0x7F};
static const uint8_t font_N[5] = {0x7F, 0x04, 0x08, 0x10, 0x7F};
static const uint8_t font_O[5] = {0x3E, 0x41, 0x41, 0x41, 0x3E};
static const uint8_t font_P[5] = {0x7F, 0x09, 0x09, 0x09, 0x06};
static const uint8_t font_Q[5] = {0x3E, 0x41, 0x51, 0x21, 0x5E};
static const uint8_t font_R[5] = {0x7F, 0x09, 0x19, 0x29, 0x46};
static const uint8_t font_S[5] = {0x46, 0x49, 0x49, 0x49, 0x31};
static const uint8_t font_T[5] = {0x01, 0x01, 0x7F, 0x01, 0x01};
static const uint8_t font_U[5] = {0x3F, 0x40, 0x40, 0x40, 0x3F};
static const uint8_t font_V[5] = {0x1F, 0x20, 0x40, 0x20, 0x1F};
static const uint8_t font_W[5] = {0x7F, 0x20, 0x18, 0x20, 0x7F};
static const uint8_t font_X[5] = {0x63, 0x14, 0x08, 0x14, 0x63};
static const uint8_t font_Y[5] = {0x07, 0x08, 0x70, 0x08, 0x07};
static const uint8_t font_Z[5] = {0x61, 0x51, 0x49, 0x45, 0x43};

// =========================================================
// Lấy con trỏ font theo ký tự
// =========================================================
static inline const uint8_t *oled_font_get(char c)
{
    if (c >= '0' && c <= '9') return font_digit[c - '0'];

    if (c >= 'A' && c <= 'Z') {
        static const uint8_t *const alpha_fonts[26] = {
            font_A, font_B, font_C, font_D, font_E, font_F, font_G,
            font_H, font_I, font_J, font_K, font_L, font_M, font_N,
            font_O, font_P, font_Q, font_R, font_S, font_T, font_U,
            font_V, font_W, font_X, font_Y, font_Z
        };
        return alpha_fonts[c - 'A'];
    }

    switch (c) {
        case ' ':  return font_space;
        case ':':  return font_colon;
        case '=':  return font_equal;
        case '%':  return font_percent;
        case '.':  return font_dot;
        case '-':  return font_minus;
        default:   return font_space;
    }
}

// =========================================================
// Các hàm giao tiếp I2C cấp thấp
// =========================================================
static inline int oled_write2(uint8_t ctrl, uint8_t data)
{
    uint8_t buf[2];
    buf[0] = ctrl;
    buf[1] = data;
    return i2c_write_raw(OLED_ADDR, buf, 2);
}

static inline int oled_cmd(uint8_t cmd)  { return oled_write2(0x00, cmd); }
static inline int oled_data(uint8_t d)   { return oled_write2(0x40, d);  }

// =========================================================
// Đặt vị trí con trỏ (page: 0-7, col: 0-127)
// =========================================================
static inline void oled_set_pos(int page, int col)
{
    oled_cmd((uint8_t)(0xB0 + page));
    oled_cmd((uint8_t)(col & 0x0F));
    oled_cmd((uint8_t)(0x10 | ((col >> 4) & 0x0F)));
}

// =========================================================
// Khởi tạo OLED SSD1306
// =========================================================
static inline int oled_init(void)
{
    delay_ms(100);
    if (oled_cmd(0xAE)) return -1;  /* Display OFF */

    oled_cmd(0x20); oled_cmd(0x00); /* Memory addressing mode: Horizontal */
    oled_cmd(0xB0);                 /* Page start address */
    oled_cmd(0xC8);                 /* COM scan direction: remapped */
    oled_cmd(0x00);                 /* Low column start */
    oled_cmd(0x10);                 /* High column start */
    oled_cmd(0x40);                 /* Display start line: 0 */
    oled_cmd(0x81); oled_cmd(0x7F); /* Contrast */
    oled_cmd(0xA1);                 /* Segment re-map */
    oled_cmd(0xA6);                 /* Normal display (not inverted) */
    oled_cmd(0xA8); oled_cmd(0x3F); /* Multiplex ratio: 64 */
    oled_cmd(0xD3); oled_cmd(0x00); /* Display offset: 0 */
    oled_cmd(0xD5); oled_cmd(0x80); /* Display clock divide ratio */
    oled_cmd(0xD9); oled_cmd(0xF1); /* Pre-charge period */
    oled_cmd(0xDA); oled_cmd(0x12); /* COM pins hardware configuration */
    oled_cmd(0xDB); oled_cmd(0x40); /* VCOMH deselect level */
    oled_cmd(0x8D); oled_cmd(0x14); /* Charge pump: enable */
    oled_cmd(0xAF);                 /* Display ON */
    return 0;
}

// =========================================================
// Xóa toàn bộ màn hình
// =========================================================
static inline void oled_clear(void)
{
    for (int page = 0; page < 8; page++) {
        oled_set_pos(page, 0);
        for (int i = 0; i < 128; i++) oled_data(0x00);
    }
}

// =========================================================
// In một ký tự tại vị trí con trỏ hiện tại
// =========================================================
static inline void oled_putc(char c)
{
    const uint8_t *g = oled_font_get(c);
    for (int i = 0; i < 5; i++) oled_data(g[i]);
    oled_data(0x00); /* Khoảng cách giữa các ký tự */
}

// =========================================================
// In chuỗi tại page và cột chỉ định
// =========================================================
static inline void oled_puts_at(int page, int col, const char *s)
{
    oled_set_pos(page, col);
    while (*s) oled_putc(*s++);
}

// =========================================================
// Tính cột để căn giữa chuỗi trên màn hình 128px
// =========================================================
static inline int oled_center_col(const char *s)
{
    int w = str_len(s) * 6;
    int col = (OLED_W - w) / 2;
    return (col < 0) ? 0 : col;
}

#endif /* OLED_H */
