#include <stdint.h>
#include "uart.h"
#include "gpio.h"
#include "i2c.h"
#include "spi.h"
#include "timer.h"

#include "oled.h"
#include "bh1750.h"
#include "dht11.h"
#include "sd.h"      /* Bao gồm cả FAT32 */

// =========================================================
// Cấu hình hệ thống
// =========================================================
#define F_CPU           27000000u
#define UART_BAUD       115200u
#define UART_DIV_VALUE  ((F_CPU / UART_BAUD) - 1u)
#define TIMER_CH_US     0

// =========================================================
// Fix lỗi "undefined reference to memcpy" của GCC
// =========================================================
void *memcpy(void *dest, const void *src, uint32_t n)
{
    uint8_t *d = (uint8_t *)dest;
    const uint8_t *s = (const uint8_t *)src;
    while (n--) *d++ = *s++;
    return dest;
}

// =========================================================
// Timer
// =========================================================
 void timer_init_us(void)
{
    timer_set_psc(26);
    timer_set_top(TIMER_CH_US, 0xFFFFFFFFu);
    timer_set_cmp(TIMER_CH_US, 0);
    timer_clear_istat(0xFFFFFFFFu);
    timer_set_ctrl(TIMER_EN(TIMER_CH_US));
}

/* Dùng bởi oled.h, bh1750.h, dht11.h, sd.h qua extern */
 uint32_t timer_now_us(void)
{
    return timer_get_cnt(TIMER_CH_US);
}

 void delay_us(uint32_t us)
{
    uint32_t start = timer_now_us();
    while ((uint32_t)(timer_now_us() - start) < us) { ; }
}

void delay_ms(uint32_t ms)
{
    while (ms--) delay_us(1000u);
}

// =========================================================
// Helpers dùng cho log (append_str / append_u32)
// str_len dùng bởi oled.h qua extern
// =========================================================
int str_len(const char *s) { int n = 0; while (s[n]) n++; return n; }

 void append_str(char *dst, int *idx, const char *src) {
    while (*src) dst[(*idx)++] = *src++;
}
void append_u32(char *dst, int *idx, uint32_t v) {
    char buf[16]; int n = 0;
    if (v == 0) { dst[(*idx)++] = '0'; return; }
    while (v) { buf[n++] = (char)('0' + (v % 10u)); v /= 10u; }
    while (n--) dst[(*idx)++] = buf[n];
}

// =========================================================
// Ghi log vào LOG.TXT trên thẻ SD
// =========================================================
int fat32_append_log_line(uint32_t sample_id, uint16_t lux,
    int temp_c, int humi, int dht_ok)
{
 const uint8_t candidates[][11] = {
        { 'L','O','G',' ',' ',' ',' ',' ','T','X','T' },
        { 'L','O','G','T','X','T','~','1','T','X','T' }
    };

    uint8_t line[64];
    int idx = 0;

    append_str((char *)line, &idx, "ID=");
    append_u32((char *)line, &idx, sample_id);
    append_str((char *)line, &idx, ",LUX=");
    append_u32((char *)line, &idx, (uint32_t)lux);

    if (dht_ok) {
        append_str((char *)line, &idx, ",TEMP=");
        append_u32((char *)line, &idx, (uint32_t)temp_c);
        append_str((char *)line, &idx, ",HUM=");
        append_u32((char *)line, &idx, (uint32_t)humi);
    } else {
        append_str((char *)line, &idx, ",TEMP=ERR,HUM=ERR");
    }

    line[idx++] = '\r';
    line[idx++] = '\n';

    for (int i = 0; i < 2; i++) {
        if (fat32_append_file_83(candidates[i], line, (uint32_t)idx) == FAT32_OK)
            return FAT32_OK;
    }
    return FAT32_ERR_NOT_FOUND;
}

// =========================================================
// Hiển thị trạng thái lên OLED
// =========================================================
 void app_show_status(uint32_t id, uint16_t lux,
    int temp_c, int humi, int dht_ok, int log_ok)
{
    char line0[24], line1[24], line2[24], line3[24];
    int idx;

    idx = 0;
    append_str(line0, &idx, "ID:"); append_u32(line0, &idx, id);
    append_str(line0, &idx, " SD:"); append_str(line0, &idx, log_ok ? "OK" : "ERR");
    line0[idx] = 0;

    idx = 0;
    if (dht_ok) {
        append_str(line1, &idx, "TEMP: "); append_u32(line1, &idx, (uint32_t)temp_c);
        append_str(line1, &idx, " C");
    } else {
        append_str(line1, &idx, "TEMP: ERR");
    }
    line1[idx] = 0;

    idx = 0;
    if (dht_ok) {
        append_str(line2, &idx, "HUMI: "); append_u32(line2, &idx, (uint32_t)humi);
        append_str(line2, &idx, " %");
    } else {
        append_str(line2, &idx, "HUMI: ERR");
    }
    line2[idx] = 0;

    idx = 0;
    append_str(line3, &idx, "LUX: "); append_u32(line3, &idx, (uint32_t)lux);
    line3[idx] = 0;

    oled_clear();
    oled_puts_at(0, oled_center_col(line0), line0);
    oled_puts_at(2, oled_center_col(line1), line1);
    oled_puts_at(4, oled_center_col(line2), line2);
    oled_puts_at(6, oled_center_col(line3), line3);
}

// =========================================================
// main
// =========================================================
int main(void)
{
    uint32_t sample_id = 0;
    int oled_ok = 0;
    int sd_ok   = 0;
    int fs_ok   = 0;
    int log_ok  = 0;

    uart_init(UART_DIV_VALUE);
    timer_init_us();
    uart_puts("Boot SENSOR LOG\r\n");

    gpio_dir_in(PIN_DHT11);

    /* OLED */
    if (oled_init() == 0) {
        uart_puts("OLED OK\r\n");
        oled_ok = 1;
        oled_clear();
        oled_puts_at(0, oled_center_col("SYSTEM BOOT"), "SYSTEM BOOT");
        oled_puts_at(2, oled_center_col("LOG.TXT"),     "LOG.TXT");
        oled_puts_at(4, oled_center_col("FAT32"),       "FAT32");
        oled_puts_at(6, oled_center_col("WAIT"),        "WAIT");
        delay_ms(700);
    } else {
        uart_puts("OLED FAIL\r\n");
    }

    /* BH1750 */
    if (bh1750_init() == 0) {
        uart_puts("BH1750 OK\r\n");
    } else {
        uart_puts("BH1750 FAIL\r\n");
    }

    /* SD */
    if (sd_init() == SD_OK) {
        uart_puts("SD OK\r\n");
        sd_ok = 1;
    } else {
        uart_puts("SD FAIL\r\n");
    }

    /* FAT32 */
    if (sd_ok) {
        if (fat32_mount() == FAT32_OK) {
            uart_puts("FAT32 MOUNT OK\r\n");
            fs_ok = 1;
            fat32_dump_root_dir();
        } else {
            uart_puts("FAT32 MOUNT FAIL\r\n");
        }
    }

    if (oled_ok) app_show_status(0, 0, 0, 0, 1, 0);
    delay_ms(500);

    while (1) {
        int      temp_c = 0;
        int      humi   = 0;
        uint16_t lux    = 0;

        int dht_ok = (dht11_read(&temp_c, &humi) == DHT11_OK);
        lux = bh1750_read();

        uart_puts("ID="); uart_dec(sample_id);
        uart_puts(" LUX="); uart_dec((uint32_t)lux);
        if (dht_ok) {
            uart_puts(" TEMP="); uart_dec((uint32_t)temp_c);
            uart_puts(" HUM=");  uart_dec((uint32_t)humi);
        } else {
            uart_puts(" DHT11=ERR");
        }

        if (sd_ok && fs_ok) {
            int ret = fat32_append_log_line(sample_id, lux, temp_c, humi, dht_ok);
            uart_puts(" LOG=");
            if (ret == FAT32_OK) {
                uart_puts("OK");
                log_ok = 1;
            } else {
                uart_puts("ERR "); uart_dec((uint32_t)(-ret));
                log_ok = 0;
            }
        } else {
            uart_puts(" LOG=OFF");
            log_ok = 0;
        }
        uart_puts("\r\n");

        if (oled_ok)
            app_show_status(sample_id, lux, temp_c, humi, dht_ok, log_ok);

        sample_id++;
        delay_ms(2000);
    }

    return 0;
}
