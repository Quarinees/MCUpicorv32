#ifndef SPI_H
#define SPI_H

#include <stdint.h>

#define SPI_BASE    0x05000000u

#define SPI_DIV     (*(volatile uint32_t *)(SPI_BASE + 0x00))
#define SPI_CFG     (*(volatile uint32_t *)(SPI_BASE + 0x04))
#define SPI_STAT    (*(volatile uint32_t *)(SPI_BASE + 0x0C))
#define SPI_DAT     (*(volatile uint32_t *)(SPI_BASE + 0x10))

// config bits
#define SPI_MODE(m)         ((m) & 0x3u)
#define SPI_CS_AUTO         (1u << 3)

// status bits
#define SPI_BUSY            (1u << 0)

// data bits
#define SPI_CS_END          (1u << 8)

static inline void spi_init(uint32_t div, uint32_t cfg)
{
    SPI_DIV = div;
    SPI_CFG = cfg;
}

static inline void spi_wait_idle(void)
{
    while (SPI_STAT & SPI_BUSY) ;
}

static inline uint8_t spi_transfer(uint8_t tx, int cs_end)
{
    SPI_DAT = (uint32_t)tx | (cs_end ? SPI_CS_END : 0u);
    while (SPI_STAT & SPI_BUSY) ;
    return (uint8_t)SPI_DAT;
}

static inline uint8_t spi_xfer(uint8_t tx)
{
    return spi_transfer(tx, 0);
}

static inline uint8_t spi_xfer_end(uint8_t tx)
{
    return spi_transfer(tx, 1);
}

static inline void spi_release(void)
{
    spi_xfer_end(0xFF);
}

static inline void spi_transfer_buf(const uint8_t *tx_buf, uint8_t *rx_buf, int len)
{
    for (int i = 0; i < len; i++) {
        uint8_t tx = tx_buf ? tx_buf[i] : 0xFF;
        uint8_t rx = spi_transfer(tx, (i == len - 1));
        if (rx_buf) rx_buf[i] = rx;
    }
}

#endif
