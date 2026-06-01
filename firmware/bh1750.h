#ifndef BH1750_H
#define BH1750_H

#include <stdint.h>
#include "i2c.h"

// =========================================================
// Địa chỉ I2C
// ADDR pin = GND → 0x23 (mặc định)
// ADDR pin = VCC → 0x5C
// =========================================================
#define BH1750_ADDR     0x23

// =========================================================
// Lệnh đo (Operation Codes)
// =========================================================
#define BH1750_POWER_DOWN           0x00  /* Tắt nguồn */
#define BH1750_POWER_ON             0x01  /* Bật nguồn */
#define BH1750_RESET                0x07  /* Reset thanh ghi dữ liệu */

/* Chế độ đo liên tục (Continuously) */
#define BH1750_CONT_H_RES_MODE      0x10  /* 1 lx resolution, 120ms */
#define BH1750_CONT_H_RES_MODE2     0x11  /* 0.5 lx resolution, 120ms */
#define BH1750_CONT_L_RES_MODE      0x13  /* 4 lx resolution, 16ms */

/* Chế độ đo một lần (One Time) */
#define BH1750_ONETIME_H_RES_MODE   0x20  /* 1 lx resolution, 120ms, tự sleep sau đo */
#define BH1750_ONETIME_H_RES_MODE2  0x21  /* 0.5 lx resolution, 120ms */
#define BH1750_ONETIME_L_RES_MODE   0x23  /* 4 lx resolution, 16ms */

// =========================================================
// Khai báo hàm phụ trợ (được cung cấp bởi main)
// =========================================================
extern void delay_ms(uint32_t ms);

// =========================================================
// Khởi tạo BH1750
// Mặc định: Continuous High-Resolution Mode (0x10)
// Trả về  : 0 = OK, khác 0 = lỗi I2C
// =========================================================
static inline int bh1750_init(void)
{
    uint8_t cmd = BH1750_CONT_H_RES_MODE;
    return i2c_write_raw(BH1750_ADDR, &cmd, 1);
}

// =========================================================
// Khởi tạo với chế độ tùy chọn
// =========================================================
static inline int bh1750_init_mode(uint8_t mode)
{
    return i2c_write_raw(BH1750_ADDR, &mode, 1);
}

// =========================================================
// Reset thanh ghi dữ liệu (chỉ dùng khi đang Power On)
// =========================================================
static inline int bh1750_reset(void)
{
    uint8_t cmd = BH1750_RESET;
    return i2c_write_raw(BH1750_ADDR, &cmd, 1);
}

// =========================================================
// Đọc giá trị ánh sáng (lux)
// Trả về: giá trị lux (0 nếu lỗi I2C)
// Công thức: raw / 1.2 (theo datasheet BH1750)
// =========================================================
static inline uint16_t bh1750_read(void)
{
    uint8_t data[2] = {0, 0};
    if (i2c_read_raw(BH1750_ADDR, data, 2) == 0) {
        uint16_t raw = (uint16_t)((data[0] << 8) | data[1]);
        return (uint16_t)(raw / 1.2f);
    }
    return 0;
}

// =========================================================
// Đo một lần và trả kết quả (One-Shot, tự động sleep sau đo)
// Thời gian chờ: 180ms (đủ cho cả H_RES_MODE2)
// =========================================================
static inline uint16_t bh1750_read_oneshot(void)
{
    uint8_t cmd = BH1750_ONETIME_H_RES_MODE;
    uint8_t data[2] = {0, 0};

    if (i2c_write_raw(BH1750_ADDR, &cmd, 1) != 0) return 0;
    delay_ms(180);
    if (i2c_read_raw(BH1750_ADDR, data, 2) != 0) return 0;

    uint16_t raw = (uint16_t)((data[0] << 8) | data[1]);
    return (uint16_t)(raw / 1.2f);
}

#endif /* BH1750_H */
