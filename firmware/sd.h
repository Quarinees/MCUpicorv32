#ifndef SD_H
#define SD_H

#include <stdint.h>
#include "spi.h"
#include "uart.h"

// =========================================================
// Cấu hình SPI
// =========================================================
#define SPI_DIV_SLOW    33u
#define SPI_DIV_FAST    2u
#define SPI_CFG_SD      (SPI_MODE(0) | SPI_CS_AUTO)

// =========================================================
// Mã lỗi SD
// =========================================================
#define SD_OK                    0
#define SD_ERR_CMD0             -1
#define SD_ERR_CMD8             -2
#define SD_ERR_ACMD41_CMD55     -3
#define SD_ERR_ACMD41_TIMEOUT   -4
#define SD_ERR_CMD58            -5
#define SD_ERR_READ_CMD         -1
#define SD_ERR_READ_TOKEN       -2
#define SD_ERR_WRITE_BUSY       -1
#define SD_ERR_WRITE_CMD        -2
#define SD_ERR_WRITE_RESP       -3
#define SD_ERR_WRITE_TIMEOUT    -4

// =========================================================
// Mã lỗi FAT32
// =========================================================
#define FAT32_OK                0
#define FAT32_ERR_MBR          -1
#define FAT32_ERR_BOOT         -2
#define FAT32_ERR_NOT_FOUND    -3
#define FAT32_ERR_IO           -4
#define FAT32_ERR_FULL         -5
#define FAT32_ERR_BAD_FS       -6

#define FAT32_ATTR_LFN         0x0F
#define FAT32_ATTR_VOLUME      0x08
#define FAT32_ATTR_DIR         0x10

#define FAT32_EOC_MIN          0x0FFFFFF8u
#define FAT32_FREE_CLUSTER     0x00000000u
#define FAT32_EOC_MARK         0x0FFFFFFFu

// =========================================================
// Khai báo hàm phụ trợ (cung cấp bởi main)
// =========================================================
extern void delay_ms(uint32_t ms);

// =========================================================
// FAT32 filesystem struct (global, dùng bởi tất cả hàm fat32_*)
// =========================================================
typedef struct {
    uint32_t part_lba;
    uint32_t fat_start_lba;
    uint32_t data_start_lba;
    uint32_t fat_size_sectors;
    uint32_t total_sectors;
    uint32_t total_data_sectors;
    uint32_t root_cluster;
    uint32_t cluster_count;
    uint16_t bytes_per_sector;
    uint8_t  sectors_per_cluster;
    uint8_t  num_fats;
} fat32_fs_t;

/* Instance duy nhất, định nghĩa tại đây (header-only pattern) */
static fat32_fs_t g_fs;

// =========================================================
// Helpers nội bộ: đọc/ghi little-endian
// =========================================================
static inline uint16_t _rd16(const uint8_t *p)
{
    return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
}
static inline uint32_t _rd32(const uint8_t *p)
{
    return ((uint32_t)p[0])       | ((uint32_t)p[1] << 8)
         | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}
static inline void _wr16(uint8_t *p, uint16_t v)
{
    p[0] = (uint8_t)(v & 0xFFu);
    p[1] = (uint8_t)((v >> 8) & 0xFFu);
}
static inline void _wr32(uint8_t *p, uint32_t v)
{
    p[0] = (uint8_t)(v        & 0xFFu);
    p[1] = (uint8_t)((v >> 8)  & 0xFFu);
    p[2] = (uint8_t)((v >> 16) & 0xFFu);
    p[3] = (uint8_t)((v >> 24) & 0xFFu);
}
static inline void _mem_set(uint8_t *p, uint8_t v, int n) { while (n--) *p++ = v; }
static inline void _mem_cpy(uint8_t *d, const uint8_t *s, int n) { while (n--) *d++ = *s++; }
static inline int  _mem_eq(const uint8_t *a, const uint8_t *b, int n)
{
    for (int i = 0; i < n; i++) { if (a[i] != b[i]) return 0; }
    return 1;
}

// =========================================================
// SD - Low level SPI
// =========================================================
static inline void sd_spi_slow(void) { spi_init(SPI_DIV_SLOW, SPI_CFG_SD); }
static inline void sd_spi_fast(void) { spi_init(SPI_DIV_FAST, SPI_CFG_SD); }

static inline uint8_t sd_cmd(uint8_t cmd, uint32_t arg, uint8_t crc)
{
    uint8_t r = 0xFF;
    spi_xfer(0xFF);
    spi_xfer((uint8_t)(0x40 | cmd));
    spi_xfer((uint8_t)(arg >> 24));
    spi_xfer((uint8_t)(arg >> 16));
    spi_xfer((uint8_t)(arg >>  8));
    spi_xfer((uint8_t)(arg));
    spi_xfer(crc);
    for (int i = 0; i < 64; i++) {
        r = spi_xfer(0xFF);
        if (r != 0xFF) break;
    }
    return r;
}

static inline int sd_wait_not_busy(uint32_t limit)
{
    while (limit--) { if (spi_xfer(0xFF) == 0xFF) return 0; }
    return -1;
}

// =========================================================
// SD - Init / Read / Write
// =========================================================
static inline int sd_init(void)
{
    uint8_t r, ocr[4];
    int timeout;

    sd_spi_slow();
    for (int i = 0; i < 10; i++) spi_xfer_end(0xFF);
    delay_ms(10);

    r = sd_cmd(0, 0x00000000u, 0x95);
    spi_release();
    if (r != 0x01) return SD_ERR_CMD0;

    r = sd_cmd(8, 0x000001AAu, 0x87);
    for (int i = 0; i < 4; i++) ocr[i] = spi_xfer(0xFF);
    spi_release();
    if (r != 0x01) return SD_ERR_CMD8;

    timeout = 50000;
    do {
        r = sd_cmd(55, 0x00000000u, 0x65);
        spi_release();
        if (r > 0x01) return SD_ERR_ACMD41_CMD55;
        r = sd_cmd(41, 0x40000000u, 0x77);
        spi_release();
        if (--timeout == 0) return SD_ERR_ACMD41_TIMEOUT;
    } while (r != 0x00);

    r = sd_cmd(58, 0x00000000u, 0xFD);
    for (int i = 0; i < 4; i++) ocr[i] = spi_xfer(0xFF);
    spi_release();
    if (r != 0x00) return SD_ERR_CMD58;

    sd_spi_fast();
    for (int i = 0; i < 8; i++) spi_xfer(0xFF);
    return SD_OK;
}

static inline int sd_read_sector(uint32_t lba, uint8_t *buf)
{
    uint8_t r, token;
    r = sd_cmd(17, lba, 0xFF);
    if (r != 0x00) { spi_release(); return SD_ERR_READ_CMD; }

    token = 0xFF;
    for (int i = 0; i < 200000; i++) {
        token = spi_xfer(0xFF);
        if (token != 0xFF) break;
    }
    if (token != 0xFE) { spi_release(); return SD_ERR_READ_TOKEN; }

    for (int i = 0; i < 512; i++) buf[i] = spi_xfer(0xFF);
    spi_xfer(0xFF);
    spi_release();
    return SD_OK;
}

static inline int sd_write_sector(uint32_t lba, const uint8_t *buf)
{
    uint8_t r, resp;
    if (sd_wait_not_busy(300000) != 0) { spi_release(); return SD_ERR_WRITE_BUSY; }

    r = sd_cmd(24, lba, 0xFF);
    if (r != 0x00) { spi_release(); return SD_ERR_WRITE_CMD; }

    spi_xfer(0xFF);
    spi_xfer(0xFE);
    for (int i = 0; i < 512; i++) spi_xfer(buf[i]);
    spi_xfer(0xFF);
    spi_xfer(0xFF);

    resp = spi_xfer(0xFF);
    if ((resp & 0x1F) != 0x05) { spi_release(); return SD_ERR_WRITE_RESP; }
    if (sd_wait_not_busy(600000) != 0) { spi_release(); return SD_ERR_WRITE_TIMEOUT; }

    spi_release();
    return SD_OK;
}

// =========================================================
// FAT32 - Helpers nội bộ
// =========================================================
static inline uint32_t fat32_cluster_to_lba(uint32_t cluster)
{
    return g_fs.data_start_lba + (cluster - 2u) * g_fs.sectors_per_cluster;
}

static inline int fat32_is_eoc(uint32_t v) { return v >= FAT32_EOC_MIN; }

static inline int fat32_read_fat_entry(uint32_t cluster, uint32_t *value)
{
    uint8_t sec[512];
    uint32_t fat_offset = cluster * 4u;
    uint32_t lba = g_fs.fat_start_lba + (fat_offset / 512u);
    uint32_t off = fat_offset % 512u;
    if (sd_read_sector(lba, sec) != 0) return FAT32_ERR_IO;
    *value = _rd32(&sec[off]) & 0x0FFFFFFFu;
    return FAT32_OK;
}

static inline int fat32_write_fat_entry(uint32_t cluster, uint32_t value)
{
    uint8_t sec[512];
    uint32_t fat_offset = cluster * 4u;
    uint32_t sec_in_fat = fat_offset / 512u;
    uint32_t off        = fat_offset % 512u;
    value &= 0x0FFFFFFFu;
    for (uint32_t f = 0; f < g_fs.num_fats; f++) {
        uint32_t lba  = g_fs.fat_start_lba + f * g_fs.fat_size_sectors + sec_in_fat;
        uint32_t oldv;
        if (sd_read_sector(lba, sec) != 0) return FAT32_ERR_IO;
        oldv  = _rd32(&sec[off]) & 0xF0000000u;
        oldv |= value;
        _wr32(&sec[off], oldv);
        if (sd_write_sector(lba, sec) != 0) return FAT32_ERR_IO;
    }
    return FAT32_OK;
}

static inline int fat32_zero_cluster(uint32_t cluster)
{
    uint8_t sec[512];
    _mem_set(sec, 0x00, 512);
    for (uint32_t s = 0; s < g_fs.sectors_per_cluster; s++) {
        if (sd_write_sector(fat32_cluster_to_lba(cluster) + s, sec) != 0)
            return FAT32_ERR_IO;
    }
    return FAT32_OK;
}

static inline int fat32_find_free_cluster(uint32_t *cluster_out)
{
    uint32_t v;
    for (uint32_t c = 2; c < g_fs.cluster_count + 2u; c++) {
        if (fat32_read_fat_entry(c, &v) != 0) return FAT32_ERR_IO;
        if (v == FAT32_FREE_CLUSTER) { *cluster_out = c; return FAT32_OK; }
    }
    return FAT32_ERR_FULL;
}

static inline int fat32_alloc_new_cluster(uint32_t prev_cluster, uint32_t *new_cluster)
{
    uint32_t c;
    if (fat32_find_free_cluster(&c) != 0) return FAT32_ERR_FULL;
    if (fat32_write_fat_entry(c, FAT32_EOC_MARK) != 0) return FAT32_ERR_IO;
    if (prev_cluster >= 2u)
        if (fat32_write_fat_entry(prev_cluster, c) != 0) return FAT32_ERR_IO;
    if (fat32_zero_cluster(c) != 0) return FAT32_ERR_IO;
    *new_cluster = c;
    return FAT32_OK;
}

static inline int fat32_update_dir_entry(uint32_t dir_lba, uint32_t dir_off,
    uint32_t first_cluster, uint32_t size)
{
    uint8_t sec[512];
    uint8_t *e;
    if (sd_read_sector(dir_lba, sec) != 0) return FAT32_ERR_IO;
    e = &sec[dir_off];
    _wr16(&e[20], (uint16_t)((first_cluster >> 16) & 0xFFFFu));
    _wr16(&e[26], (uint16_t)(first_cluster & 0xFFFFu));
    _wr32(&e[28], size);
    if (sd_write_sector(dir_lba, sec) != 0) return FAT32_ERR_IO;
    return FAT32_OK;
}

static inline int fat32_ensure_cluster_for_offset(uint32_t *first_cluster_io,
    uint32_t file_offset, uint32_t *cluster_out, int allow_alloc)
{
    uint32_t cluster_bytes = (uint32_t)g_fs.sectors_per_cluster * 512u;
    uint32_t steps = file_offset / cluster_bytes;
    uint32_t first = *first_cluster_io;
    uint32_t cur, next;

    if (first < 2u) {
        if (!allow_alloc) return FAT32_ERR_NOT_FOUND;
        if (fat32_alloc_new_cluster(0, &first) != 0) return FAT32_ERR_FULL;
        *first_cluster_io = first;
    }
    cur = first;
    while (steps--) {
        if (fat32_read_fat_entry(cur, &next) != 0) return FAT32_ERR_IO;
        if (fat32_is_eoc(next)) {
            if (!allow_alloc) return FAT32_ERR_FULL;
            if (fat32_alloc_new_cluster(cur, &next) != 0) return FAT32_ERR_FULL;
        }
        cur = next;
    }
    *cluster_out = cur;
    return FAT32_OK;
}

static inline int fat32_dir_find_file_root(const uint8_t name83[11],
    uint32_t *dir_lba_out, uint32_t *dir_off_out,
    uint32_t *first_cluster_out, uint32_t *size_out)
{
    uint8_t sec[512];
    uint32_t cluster = g_fs.root_cluster;

    while (cluster >= 2u && !fat32_is_eoc(cluster)) {
        uint32_t base = fat32_cluster_to_lba(cluster);
        for (uint32_t s = 0; s < g_fs.sectors_per_cluster; s++) {
            uint32_t lba = base + s;
            if (sd_read_sector(lba, sec) != 0) return FAT32_ERR_IO;
            for (uint32_t off = 0; off < 512u; off += 32u) {
                uint8_t *e    = &sec[off];
                uint8_t  attr = e[11];
                if (e[0] == 0x00) return FAT32_ERR_NOT_FOUND;
                if (e[0] == 0xE5) continue;
                if (attr == FAT32_ATTR_LFN)   continue;
                if (attr &  FAT32_ATTR_VOLUME) continue;
                if (attr &  FAT32_ATTR_DIR)    continue;
                if (_mem_eq(e, name83, 11)) {
                    *dir_lba_out       = lba;
                    *dir_off_out       = off;
                    *first_cluster_out = ((uint32_t)_rd16(&e[20]) << 16) | _rd16(&e[26]);
                    *size_out          = _rd32(&e[28]);
                    return FAT32_OK;
                }
            }
        }
        {
            uint32_t next;
            if (fat32_read_fat_entry(cluster, &next) != 0) return FAT32_ERR_IO;
            if (fat32_is_eoc(next)) break;
            cluster = next;
        }
    }
    return FAT32_ERR_NOT_FOUND;
}

// =========================================================
// FAT32 - Public API
// =========================================================

/*
 * fat32_mount: Đọc MBR + Boot Sector, điền g_fs
 * Trả về: FAT32_OK hoặc FAT32_ERR_*
 */
static inline int fat32_mount(void)
{
    uint8_t sec[512];
    uint32_t part_lba = 0;
    uint32_t reserved, fats_total, data_sectors;

    if (sd_read_sector(0, sec) != 0) return FAT32_ERR_IO;
    if (sec[510] != 0x55 || sec[511] != 0xAA) return FAT32_ERR_MBR;

    {
        const uint8_t *p0 = &sec[0x1BE];
        uint8_t  type = p0[4];
        uint32_t lba  = _rd32(&p0[8]);
        part_lba = ((type == 0x0B || type == 0x0C) && lba != 0) ? lba : 0;
    }

    if (sd_read_sector(part_lba, sec) != 0) return FAT32_ERR_IO;
    if (sec[510] != 0x55 || sec[511] != 0xAA) return FAT32_ERR_BOOT;

    g_fs.part_lba            = part_lba;
    g_fs.bytes_per_sector    = _rd16(&sec[11]);
    g_fs.sectors_per_cluster = sec[13];
    reserved                 = _rd16(&sec[14]);
    g_fs.num_fats            = sec[16];
    g_fs.total_sectors       = _rd32(&sec[32]);
    g_fs.fat_size_sectors    = _rd32(&sec[36]);
    g_fs.root_cluster        = _rd32(&sec[44]);

    if (g_fs.bytes_per_sector   != 512u) return FAT32_ERR_BAD_FS;
    if (g_fs.sectors_per_cluster == 0u)  return FAT32_ERR_BAD_FS;

    g_fs.fat_start_lba  = g_fs.part_lba + reserved;
    fats_total          = (uint32_t)g_fs.num_fats * g_fs.fat_size_sectors;
    g_fs.data_start_lba = g_fs.fat_start_lba + fats_total;

    data_sectors            = g_fs.total_sectors - (reserved + fats_total);
    g_fs.total_data_sectors = data_sectors;
    g_fs.cluster_count      = data_sectors / g_fs.sectors_per_cluster;
    return FAT32_OK;
}

/*
 * fat32_append_file_83: Nối dữ liệu vào file tên 8.3
 * name83 : tên file 11 byte định dạng 8.3 (space-padded)
 * data   : con trỏ dữ liệu cần ghi thêm
 * len    : số byte cần ghi
 * Trả về : FAT32_OK hoặc FAT32_ERR_*
 */
static inline int fat32_append_file_83(const uint8_t name83[11],
    const uint8_t *data, uint32_t len)
{
    uint32_t dir_lba, dir_off, first_cluster, old_size, pos, cluster, cluster_bytes;
    uint8_t sec[512];
    int ret;

    ret = fat32_dir_find_file_root(name83, &dir_lba, &dir_off, &first_cluster, &old_size);
    if (ret != FAT32_OK) return ret;

    cluster_bytes = (uint32_t)g_fs.sectors_per_cluster * 512u;
    pos = old_size;

    ret = fat32_ensure_cluster_for_offset(&first_cluster, pos, &cluster, 1);
    if (ret != FAT32_OK) return ret;

    while (len > 0) {
        uint32_t off_in_cluster    = pos % cluster_bytes;
        uint32_t sector_in_cluster = off_in_cluster / 512u;
        uint32_t off_in_sector     = off_in_cluster % 512u;
        uint32_t lba   = fat32_cluster_to_lba(cluster) + sector_in_cluster;
        uint32_t chunk = 512u - off_in_sector;
        uint32_t next;

        if (chunk > len) chunk = len;
        if (sd_read_sector(lba, sec) != 0) return FAT32_ERR_IO;
        _mem_cpy(&sec[off_in_sector], data, (int)chunk);
        if (sd_write_sector(lba, sec) != 0) return FAT32_ERR_IO;

        data += chunk; len -= chunk; pos += chunk;

        if ((pos % cluster_bytes) == 0u && len > 0u) {
            if (fat32_read_fat_entry(cluster, &next) != 0) return FAT32_ERR_IO;
            if (fat32_is_eoc(next)) {
                ret = fat32_alloc_new_cluster(cluster, &next);
                if (ret != FAT32_OK) return ret;
            }
            cluster = next;
        }
    }
    return fat32_update_dir_entry(dir_lba, dir_off, first_cluster, pos);
}

/*
 * fat32_dump_root_dir: In toàn bộ thư mục gốc ra UART (debug)
 */
static inline void fat32_dump_root_dir(void)
{
    uint8_t sec[512];
    uint32_t cluster = g_fs.root_cluster;

    uart_puts("=== ROOT DIR DUMP ===\r\n");
    while (cluster >= 2u && !fat32_is_eoc(cluster)) {
        uint32_t base = fat32_cluster_to_lba(cluster);
        for (uint32_t s = 0; s < g_fs.sectors_per_cluster; s++) {
            uint32_t lba = base + s;
            if (sd_read_sector(lba, sec) != 0) { uart_puts("ROOT READ FAIL\r\n"); return; }
            for (uint32_t off = 0; off < 512u; off += 32u) {
                uint8_t *e    = &sec[off];
                uint8_t  attr = e[11];
                if (e[0] == 0x00) { uart_puts("=== END ROOT DIR ===\r\n"); return; }
                if (e[0] == 0xE5) continue;

                uart_puts("NAME=");
                for (int i = 0; i < 8; i++) {
                    char c = (char)e[i]; if (c == ' ') break; uart_putc(c);
                }
                if (e[8] != ' ' || e[9] != ' ' || e[10] != ' ') {
                    uart_putc('.');
                    for (int i = 8; i < 11; i++) {
                        char c = (char)e[i]; if (c == ' ') break; uart_putc(c);
                    }
                }
                uart_puts(" ATTR="); uart_hex8(attr);
                uart_puts(" CL=");
                {
                    uint32_t cl = ((uint32_t)_rd16(&e[20]) << 16) | _rd16(&e[26]);
                    uart_dec(cl);
                }
                uart_puts(" SIZE="); uart_dec(_rd32(&e[28]));
                uart_puts("\r\n");
            }
        }
        {
            uint32_t next;
            if (fat32_read_fat_entry(cluster, &next) != 0) { uart_puts("FAT READ FAIL\r\n"); return; }
            if (fat32_is_eoc(next)) break;
            cluster = next;
        }
    }
    uart_puts("=== END ROOT DIR ===\r\n");
}

#endif /* SD_H */
