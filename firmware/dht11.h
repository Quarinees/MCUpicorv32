#ifndef DHT11_H
#define DHT11_H

#include <stdint.h>
#include "gpio.h"
#include "timer.h"

// =========================================================
// Cấu hình chân GPIO
// Thay đổi PIN_DHT11 cho phù hợp với phần cứng của bạn
// =========================================================
#define PIN_DHT11       2

// =========================================================
// Mã lỗi trả về
// =========================================================
#define DHT11_OK                 0
#define DHT11_ERR_NO_RESPONSE   -1  /* Không có tín hiệu response LOW */
#define DHT11_ERR_NO_READY      -2  /* Không có tín hiệu ready HIGH */
#define DHT11_ERR_NO_START      -3  /* Không có tín hiệu start LOW */
#define DHT11_ERR_BIT_TIMEOUT   -4  /* Timeout khi đọc bit dữ liệu */
#define DHT11_ERR_CHECKSUM      -5  /* Checksum không khớp */

// =========================================================
// Khai báo hàm phụ trợ (được cung cấp bởi main)
// =========================================================
extern void     delay_us(uint32_t us);
extern void     delay_ms(uint32_t ms);
extern uint32_t timer_now_us(void);

// =========================================================
// Hàm nội bộ: Chờ chân GPIO đạt mức level
// Trả về: 0 = OK, -1 = timeout
// =========================================================
static inline int dht11_wait_level(int level, uint32_t timeout_us)
{
    uint32_t start = timer_now_us();
    while ((uint32_t)(timer_now_us() - start) < timeout_us) {
        if (gpio_read_pin(PIN_DHT11) == level) return 0;
    }
    return -1;
}

// =========================================================
// Hàm nội bộ: Chờ chân GPIO thoát khỏi mức level
// elapsed_us: thời gian đã ở mức level (có thể NULL)
// Trả về: 0 = OK, -1 = timeout
// =========================================================
static inline int dht11_wait_while_level(int level, uint32_t timeout_us, uint32_t *elapsed_us)
{
    uint32_t start = timer_now_us();
    while ((uint32_t)(timer_now_us() - start) < timeout_us) {
        if (gpio_read_pin(PIN_DHT11) != level) {
            if (elapsed_us) *elapsed_us = (uint32_t)(timer_now_us() - start);
            return 0;
        }
    }
    if (elapsed_us) *elapsed_us = (uint32_t)(timer_now_us() - start);
    return -1;
}

// =========================================================
// Hàm nội bộ: Đọc 1 byte (8 bit) từ DHT11
// Phân biệt bit 0/1 dựa vào thời gian xung HIGH:
//   < 50us → bit 0
//   > 50us → bit 1
// Trả về: 0 = OK, khác 0 = lỗi
// =========================================================
static inline int dht11_read_byte(uint8_t *out)
{
    uint8_t v = 0;
    for (int i = 0; i < 8; i++) {
        uint32_t t_high = 0;
        /* Chờ cạnh lên (LOW → HIGH) báo hiệu bắt đầu bit */
        if (dht11_wait_level(1, 100) != 0) return -1;
        /* Đo độ rộng xung HIGH */
        if (dht11_wait_while_level(1, 120, &t_high) != 0) return -2;
        v <<= 1;
        if (t_high > 50) v |= 1u;
    }
    *out = v;
    return 0;
}

// =========================================================
// Đọc DHT11 một lần (không retry)
// temp_c : nhiệt độ nguyên (°C)
// humi   : độ ẩm nguyên (%)
// Trả về : DHT11_OK hoặc mã lỗi DHT11_ERR_*
// =========================================================
static inline int dht11_read_once(int *temp_c, int *humi)
{
    uint8_t data[5];

    /* --- Gửi tín hiệu Start --- */
    gpio_dir_out(PIN_DHT11);
    gpio_write_pin(PIN_DHT11, 1);
    delay_ms(2);                    /* Giữ HIGH ổn định */
    gpio_write_pin(PIN_DHT11, 0);
    delay_ms(20);                   /* Kéo LOW ≥ 18ms để đánh thức DHT11 */
    gpio_write_pin(PIN_DHT11, 1);
    delay_us(30);                   /* Thả HIGH, chờ DHT11 phản hồi */
    gpio_dir_in(PIN_DHT11);

    /* --- Nhận tín hiệu Response từ DHT11 --- */
    if (dht11_wait_level(0, 120) != 0) return DHT11_ERR_NO_RESPONSE; /* DHT kéo LOW ~80us */
    if (dht11_wait_level(1, 120) != 0) return DHT11_ERR_NO_READY;    /* DHT kéo HIGH ~80us */
    if (dht11_wait_level(0, 120) != 0) return DHT11_ERR_NO_START;    /* DHT kéo LOW bắt đầu truyền */

    /* --- Đọc 5 byte dữ liệu --- */
    for (int i = 0; i < 5; i++) {
        if (dht11_read_byte(&data[i]) != 0) return DHT11_ERR_BIT_TIMEOUT;
    }

    /* --- Kiểm tra Checksum --- */
    /* Byte[4] = (Byte[0] + Byte[1] + Byte[2] + Byte[3]) & 0xFF */
    if (((uint8_t)(data[0] + data[1] + data[2] + data[3])) != data[4])
        return DHT11_ERR_CHECKSUM;

    /* --- Xuất kết quả --- */
    /* DHT11 chỉ cho giá trị nguyên, data[1] và data[3] luôn = 0 */
    *humi   = (int)data[0];
    *temp_c = (int)data[2];
    return DHT11_OK;
}

// =========================================================
// Đọc DHT11 với tối đa 3 lần thử
// Khuyến nghị: gọi hàm này thay vì dht11_read_once()
// Trả về: DHT11_OK = thành công, -1 = thất bại sau 3 lần
// =========================================================
static inline int dht11_read(int *temp_c, int *humi)
{
    for (int retry = 0; retry < 3; retry++) {
        if (dht11_read_once(temp_c, humi) == DHT11_OK) return DHT11_OK;
        delay_ms(50); /* Chờ trước khi thử lại */
    }
    return -1;
}

#endif /* DHT11_H */
