#ifndef TIMER_H
#define TIMER_H

#include <stdint.h>

#define TIMER_BASE  0x04000000u

#define TIMER_CTRL               (*(volatile uint32_t *)(TIMER_BASE + 0x00))
#define TIMER_PSC                (*(volatile uint32_t *)(TIMER_BASE + 0x04))
#define TIMER_CNT(ch)   (*(volatile uint32_t *)(TIMER_BASE + 0x08 + ((ch) << 8)))
#define TIMER_TOP(ch)   (*(volatile uint32_t *)(TIMER_BASE + 0x0C + ((ch) << 8)))
#define TIMER_CMP(ch)   (*(volatile uint32_t *)(TIMER_BASE + 0x10 + ((ch) << 8)))
#define TIMER_ISTAT              (*(volatile uint32_t *)(TIMER_BASE + 0x14))

#define TIMER_EN(ch)    (1u << (ch))
#define TIMER_MODE(ch)  (1u << ((ch) + 4))
#define TIMER_IEN(ch)   (1u << ((ch) + 8))
#define TIMER_PWMEN(ch) (1u << ((ch) + 12))
#define TIMER_CMPEN(ch) (1u << ((ch) + 16))

static inline void timer_set_psc(uint32_t v) { TIMER_PSC = v; }
static inline uint32_t timer_get_psc(void) { return TIMER_PSC; }

static inline void timer_set_ctrl(uint32_t v) { TIMER_CTRL = v; }
static inline uint32_t timer_get_ctrl(void) { return TIMER_CTRL; }

static inline uint32_t timer_get_cnt(int ch) { return TIMER_CNT(ch); }
static inline void timer_set_top(int ch, uint32_t v) { TIMER_TOP(ch) = v; }
static inline uint32_t timer_get_top(int ch) { return TIMER_TOP(ch); }

static inline void timer_set_cmp(int ch, uint32_t v) { TIMER_CMP(ch) = v; }
static inline uint32_t timer_get_cmp(int ch) { return TIMER_CMP(ch); }

static inline uint32_t timer_get_istat(void) { return TIMER_ISTAT; }
static inline void timer_clear_istat(uint32_t mask) { TIMER_ISTAT = mask; }

#endif
