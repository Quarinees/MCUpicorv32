#ifndef I2C_H
#define I2C_H

#include <stdint.h>

// ============================================================
//  i2c.h — Driver cho i2c_master peripheral
//  Base address: 0x0600_0000
//
//  Register map:
//    +0x00  CTRL     [6:0]=addr  [7]=rw  [31]=start
//    +0x04  STAT     [0]=busy    [1]=ack_err
//    +0x08  TX_LEN   [3:0]
//    +0x0C  RX_LEN   [3:0]
//    +0x10  TX_BUF0  [7:0]  ...  +0x4C TX_BUF15
//    +0x50  RX_BUF0  [7:0]  ...  +0x8C RX_BUF15
//
//  Với i2c_master.v mới:
//    - rw=0, tx_len>0              -> [START][ADDR+W][TX...][STOP]
//    - rw=1, tx_len=0, rx_len>0    -> [START][ADDR+R][RX...][STOP]
//    - rw=1, tx_len>0, rx_len>0    -> [START][ADDR+W][TX...]
//                                      [REPEATED START][ADDR+R][RX...][STOP]
// ============================================================

#define I2C_BASE       0x06000000u

#define I2C_CTRL       (*(volatile uint32_t *)(I2C_BASE + 0x00))
#define I2C_STAT       (*(volatile uint32_t *)(I2C_BASE + 0x04))
#define I2C_TX_LEN     (*(volatile uint32_t *)(I2C_BASE + 0x08))
#define I2C_RX_LEN     (*(volatile uint32_t *)(I2C_BASE + 0x0C))

#define I2C_TX_BUF(n)  (*(volatile uint32_t *)(I2C_BASE + 0x10 + ((uint32_t)(n) * 4u)))
#define I2C_RX_BUF(n)  (*(volatile uint32_t *)(I2C_BASE + 0x50 + ((uint32_t)(n) * 4u)))

// Bit masks
#define I2C_STAT_BUSY      (1u << 0)
#define I2C_STAT_ACK_ERR   (1u << 1)

#define I2C_CTRL_READ      (1u << 7)
#define I2C_CTRL_START     (1u << 31)

// Limits / timeout
#define I2C_MAX_LEN        16u
#define I2C_TIMEOUT        100000u

// Return codes
#define I2C_OK             0
#define I2C_ERR_NACK      -1
#define I2C_ERR_TIMEOUT   -2
#define I2C_ERR_PARAM     -3

// ============================================================
//  i2c_wait_idle
// ============================================================
static inline int i2c_wait_idle(void)
{
    uint32_t timeout = I2C_TIMEOUT;

    while (I2C_STAT & I2C_STAT_BUSY) {
        if (timeout == 0u)
            return I2C_ERR_TIMEOUT;
        timeout--;
    }

    if (I2C_STAT & I2C_STAT_ACK_ERR)
        return I2C_ERR_NACK;

    return I2C_OK;
}

// Tương thích tên cũ
static inline int i2c_wait(void)
{
    return i2c_wait_idle();
}

// ============================================================
//  i2c_write_raw
//  [START][ADDR+W][TX...][STOP]
// ============================================================
static inline int i2c_write_raw(uint8_t addr, const uint8_t *buf, uint8_t len)
{
    uint8_t i;

    if (buf == (const uint8_t *)0)
        return I2C_ERR_PARAM;
    if (len == 0u || len > I2C_MAX_LEN)
        return I2C_ERR_PARAM;

    for (i = 0; i < len; i++)
        I2C_TX_BUF(i) = (uint32_t)buf[i];

    I2C_TX_LEN = (uint32_t)len;
    I2C_RX_LEN = 0u;
    I2C_CTRL   = ((uint32_t)(addr & 0x7Fu)) | I2C_CTRL_START;

    return i2c_wait_idle();
}

// Giữ tên cũ
static inline int i2c_write_regs(uint8_t addr, const uint8_t *buf, uint8_t len)
{
    return i2c_write_raw(addr, buf, len);
}

// ============================================================
//  i2c_read_raw
//  [START][ADDR+R][RX...][STOP]
// ============================================================
static inline int i2c_read_raw(uint8_t addr, uint8_t *buf, uint8_t len)
{
    uint8_t i;
    int ret;

    if (buf == (uint8_t *)0)
        return I2C_ERR_PARAM;
    if (len == 0u || len > I2C_MAX_LEN)
        return I2C_ERR_PARAM;

    I2C_TX_LEN = 0u;
    I2C_RX_LEN = (uint32_t)len;
    I2C_CTRL   = ((uint32_t)(addr & 0x7Fu)) | I2C_CTRL_READ | I2C_CTRL_START;

    ret = i2c_wait_idle();
    if (ret != I2C_OK)
        return ret;

    for (i = 0; i < len; i++)
        buf[i] = (uint8_t)(I2C_RX_BUF(i) & 0xFFu);

    return I2C_OK;
}

// ============================================================
//  i2c_write_reg
//  [START][ADDR+W][REG][VAL][STOP]
// ============================================================
static inline int i2c_write_reg(uint8_t addr, uint8_t reg, uint8_t val)
{
    uint8_t tmp[2];
    tmp[0] = reg;
    tmp[1] = val;
    return i2c_write_raw(addr, tmp, 2u);
}

// ============================================================
//  i2c_read_regs
//  Combined transaction với repeated-start:
//
//  [START][ADDR+W][REG][REPEATED START][ADDR+R][DATA...][STOP]
//
//  Cách kích hoạt trên core mới:
//    rw     = 1
//    tx_len = số byte sub-address / command
//    rx_len = số byte cần đọc
// ============================================================
static inline int i2c_read_regs(uint8_t addr, uint8_t reg, uint8_t *buf, uint8_t len)
{
    uint8_t i;
    int ret;

    if (buf == (uint8_t *)0)
        return I2C_ERR_PARAM;
    if (len == 0u || len > I2C_MAX_LEN)
        return I2C_ERR_PARAM;

    I2C_TX_BUF(0) = (uint32_t)reg;
    I2C_TX_LEN    = 1u;
    I2C_RX_LEN    = (uint32_t)len;
    I2C_CTRL      = ((uint32_t)(addr & 0x7Fu)) | I2C_CTRL_READ | I2C_CTRL_START;

    ret = i2c_wait_idle();
    if (ret != I2C_OK)
        return ret;

    for (i = 0; i < len; i++)
        buf[i] = (uint8_t)(I2C_RX_BUF(i) & 0xFFu);

    return I2C_OK;
}

// ============================================================
//  i2c_read_reg
// ============================================================
static inline int i2c_read_reg(uint8_t addr, uint8_t reg, uint8_t *val)
{
    return i2c_read_regs(addr, reg, val, 1u);
}

#endif // I2C_H
