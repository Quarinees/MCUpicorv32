#ifndef GPIO_H
#define GPIO_H

#include <stdint.h>

#define GPIO_BASE   0x03000000u

#define GPIO_DIR    (*(volatile uint32_t *)(GPIO_BASE + 0x00))
#define GPIO_OUT    (*(volatile uint32_t *)(GPIO_BASE + 0x04))
#define GPIO_IN     (*(volatile uint32_t *)(GPIO_BASE + 0x08))
#define GPIO_SET    (*(volatile uint32_t *)(GPIO_BASE + 0x0C))
#define GPIO_CLR    (*(volatile uint32_t *)(GPIO_BASE + 0x10))
#define GPIO_TOG    (*(volatile uint32_t *)(GPIO_BASE + 0x14))
#define GPIO_IEN    (*(volatile uint32_t *)(GPIO_BASE + 0x18))
#define GPIO_ISTAT  (*(volatile uint32_t *)(GPIO_BASE + 0x1C))
#define GPIO_ICFG   (*(volatile uint32_t *)(GPIO_BASE + 0x20))

#define GPIO_BIT(n)           (1u << (n))
#define GPIO_IRQ_RISING       0u
#define GPIO_IRQ_FALLING      1u
#define GPIO_IRQ_ANYEDGE      2u
#define GPIO_IRQ_HIGHLEVEL    3u

#define GPIO_ICFG_SHIFT(n)    ((n) * 2u)
#define GPIO_ICFG_MASK(n)     (0x3u << GPIO_ICFG_SHIFT(n))

static inline void gpio_set_dir(uint32_t mask) { GPIO_DIR = mask; }
static inline uint32_t gpio_get_dir(void) { return GPIO_DIR; }

static inline void gpio_write(uint32_t v) { GPIO_OUT = v; }
static inline uint32_t gpio_read_out(void) { return GPIO_OUT; }
static inline uint32_t gpio_read_in(void) { return GPIO_IN; }

static inline void gpio_set(uint32_t mask) { GPIO_SET = mask; }
static inline void gpio_clr(uint32_t mask) { GPIO_CLR = mask; }
static inline void gpio_tog(uint32_t mask) { GPIO_TOG = mask; }

static inline void gpio_dir_out(int pin) { GPIO_DIR |= GPIO_BIT(pin); }
static inline void gpio_dir_in(int pin)  { GPIO_DIR &= ~GPIO_BIT(pin); }

static inline void gpio_write_pin(int pin, int v)
{
    if (v) GPIO_SET = GPIO_BIT(pin);
    else   GPIO_CLR = GPIO_BIT(pin);
}

static inline int gpio_read_pin(int pin)
{
    return (GPIO_IN & GPIO_BIT(pin)) ? 1 : 0;
}

static inline void gpio_irq_enable(uint32_t mask) { GPIO_IEN = mask; }
static inline uint32_t gpio_irq_enable_get(void) { return GPIO_IEN; }

static inline uint32_t gpio_irq_status(void) { return GPIO_ISTAT; }
static inline void gpio_irq_clear(uint32_t mask) { GPIO_ISTAT = mask; }

static inline void gpio_irq_cfg_raw(uint32_t v) { GPIO_ICFG = v; }
static inline uint32_t gpio_irq_cfg_get(void) { return GPIO_ICFG; }

static inline void gpio_irq_cfg_pin(int pin, uint32_t mode)
{
    uint32_t v = GPIO_ICFG;
    v &= ~GPIO_ICFG_MASK(pin);
    v |= (mode & 0x3u) << GPIO_ICFG_SHIFT(pin);
    GPIO_ICFG = v;
}

#endif
