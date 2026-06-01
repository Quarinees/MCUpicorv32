`default_nettype none
// ============================================================
//  top.v — PicoRV32 SoC, Tang Nano 9K (27 MHz)
//
//  I2C register map (base 0x0600_0000):
//    +0x00  CTRL     [6:0]=addr  [7]=rw  [31]=start
//    +0x04  STAT     [0]=busy    [1]=ack_err
//    +0x08  TX_LEN   [3:0] số byte TX (1..16)
//    +0x0C  RX_LEN   [3:0] số byte RX (1..16)
//    +0x10  TX_BUF0  [7:0]   (RW)
//    +0x14  TX_BUF1  [7:0]
//    ...
//    +0x4C  TX_BUF15 [7:0]
//    +0x50  RX_BUF0  [7:0]   (R)
//    +0x54  RX_BUF1  [7:0]
//    ...
//    +0x8C  RX_BUF15 [7:0]
// ============================================================
module top #(
    parameter integer NUM_GPIO      = 8,
    parameter integer NUM_TIMER_CH  = 4,
    parameter integer NUM_SPI_CS    = 1
) (
    input  wire clk,
    input  wire resetn,
    output wire ser_tx,
    input  wire ser_rx,
    inout  wire [NUM_GPIO-1:0]     gpio,
    output wire [NUM_TIMER_CH-1:0] pwm_out,
    output wire                    spi_sck,
    output wire                    spi_mosi,
    input  wire                    spi_miso,
    output wire [NUM_SPI_CS-1:0]   spi_cs_n,
    inout  wire                    i2c_scl,
    inout  wire                    i2c_sda
);

// ── PicoRV32 memory bus ──────────────────────────────────────
wire        mem_valid, mem_instr;
wire [31:0] mem_addr, mem_wdata, mem_rdata;
wire [3:0]  mem_wstrb;
wire        mem_ready;
wire        mem_la_read, mem_la_write;
wire [31:0] mem_la_addr, mem_la_wdata;
wire [3:0]  mem_la_wstrb;
wire        pcpi_valid;
wire [31:0] pcpi_insn, pcpi_rs1, pcpi_rs2;
wire [31:0] irq_cpu, eoi;
wire        trace_valid;
wire [35:0] trace_data;

// ── Address decode ───────────────────────────────────────────
wire ram_sel   = (mem_addr[31:15] == 17'b0);
wire uart_sel  = (mem_addr[31:20] == 12'h020);
wire gpio_sel  = (mem_addr[31:20] == 12'h030);
wire timer_sel = (mem_addr[31:20] == 12'h040);
wire spi_sel   = (mem_addr[31:20] == 12'h050);
wire i2c_sel   = (mem_addr[31:20] == 12'h060);

wire uart_div_sel = uart_sel && (mem_addr[3:2] == 2'b00);
wire uart_dat_sel = uart_sel && (mem_addr[3:2] == 2'b01);

wire gpio_dir_sel   = gpio_sel && (mem_addr[5:2] == 4'h0);
wire gpio_out_sel   = gpio_sel && (mem_addr[5:2] == 4'h1);
wire gpio_in_sel    = gpio_sel && (mem_addr[5:2] == 4'h2);
wire gpio_set_sel   = gpio_sel && (mem_addr[5:2] == 4'h3);
wire gpio_clr_sel   = gpio_sel && (mem_addr[5:2] == 4'h4);
wire gpio_tog_sel   = gpio_sel && (mem_addr[5:2] == 4'h5);
wire gpio_ien_sel   = gpio_sel && (mem_addr[5:2] == 4'h6);
wire gpio_istat_sel = gpio_sel && (mem_addr[5:2] == 4'h7);
wire gpio_icfg_sel  = gpio_sel && (mem_addr[5:2] == 4'h8);

wire timer_ctrl_sel  = timer_sel && (mem_addr[5:2] == 4'h0);
wire timer_psc_sel   = timer_sel && (mem_addr[5:2] == 4'h1);
wire timer_cnt_sel   = timer_sel && (mem_addr[5:2] == 4'h2);
wire timer_top_sel   = timer_sel && (mem_addr[5:2] == 4'h3);
wire timer_cmp_sel   = timer_sel && (mem_addr[5:2] == 4'h4);
wire timer_istat_sel = timer_sel && (mem_addr[5:2] == 4'h5);
wire [1:0] timer_ch_sel = mem_addr[9:8];

wire spi_div_sel  = spi_sel && (mem_addr[5:2] == 4'h0);
wire spi_cfg_sel  = spi_sel && (mem_addr[5:2] == 4'h1);
wire spi_cs_sel   = spi_sel && (mem_addr[5:2] == 4'h2);
wire spi_stat_sel = spi_sel && (mem_addr[5:2] == 4'h3);
wire spi_dat_sel  = spi_sel && (mem_addr[5:2] == 4'h4);

// I2C decode — dùng mem_addr[7:2] làm offset word
wire [5:0] i2c_off      = mem_addr[7:2];
wire i2c_ctrl_sel  = i2c_sel && (i2c_off == 6'h00);   // +0x00
wire i2c_stat_sel  = i2c_sel && (i2c_off == 6'h01);   // +0x04
wire i2c_txlen_sel = i2c_sel && (i2c_off == 6'h02);   // +0x08
wire i2c_rxlen_sel = i2c_sel && (i2c_off == 6'h03);   // +0x0C
wire i2c_txbuf_sel = i2c_sel && (i2c_off >= 6'h04) && (i2c_off <= 6'h13); // +0x10..+0x4C
wire i2c_rxbuf_sel = i2c_sel && (i2c_off >= 6'h14) && (i2c_off <= 6'h23); // +0x50..+0x8C

// Index byte trong buffer (0..15)
wire [3:0] i2c_txbuf_idx = i2c_off[3:0] - 4'h4;
wire [3:0] i2c_rxbuf_idx = i2c_off[3:0] - 4'h4;

// ════════════════════════════════════════════════════════════
//  RAM
// ════════════════════════════════════════════════════════════
wire [31:0] ram_rdata;
wire        ram_ready;

simpleram #(.MEM_WORDS(8192)) ram_inst (
    .clk      (clk),
    .mem_valid(ram_sel && mem_valid),
    .mem_ready(ram_ready),
    .mem_addr (mem_addr),
    .mem_wdata(mem_wdata),
    .mem_wstrb(mem_wstrb),
    .mem_rdata(ram_rdata)
);

// ════════════════════════════════════════════════════════════
//  UART
// ════════════════════════════════════════════════════════════
wire [31:0] uart_div_do, uart_dat_do;
wire        uart_dat_wait;

simpleuart #(.DEFAULT_DIV(1)) uart_inst (
    .clk         (clk),   .resetn      (resetn),
    .ser_tx      (ser_tx),.ser_rx      (ser_rx),
    .reg_div_we  ((uart_div_sel && mem_valid) ? mem_wstrb : 4'b0),
    .reg_div_di  (mem_wdata),   .reg_div_do  (uart_div_do),
    .reg_dat_we  (uart_dat_sel && mem_valid && (|mem_wstrb)),
    .reg_dat_re  (uart_dat_sel && mem_valid && (mem_wstrb == 4'b0)),
    .reg_dat_di  (mem_wdata),   .reg_dat_do  (uart_dat_do),
    .reg_dat_wait(uart_dat_wait)
);

wire uart_ready =
    (uart_div_sel && mem_valid) ||
    (uart_dat_sel && mem_valid && (mem_wstrb == 4'b0)) ||
    (uart_dat_sel && mem_valid && (|mem_wstrb) && !uart_dat_wait);

// ════════════════════════════════════════════════════════════
//  GPIO
// ════════════════════════════════════════════════════════════
wire [31:0] gpio_dir_do, gpio_out_do, gpio_in_do;
wire [31:0] gpio_ien_do, gpio_istat_do, gpio_icfg_do;
wire        gpio_irq;

simplegpio #(.NUM_GPIO(NUM_GPIO)) gpio_inst (
    .clk         (clk),   .resetn      (resetn),  .gpio  (gpio),
    .reg_dir_we  (gpio_dir_sel   && mem_valid && (|mem_wstrb)),
    .reg_dir_di  (mem_wdata),   .reg_dir_do  (gpio_dir_do),
    .reg_out_we  (gpio_out_sel   && mem_valid && (|mem_wstrb)),
    .reg_out_di  (mem_wdata),   .reg_out_do  (gpio_out_do),
    .reg_in_do   (gpio_in_do),
    .reg_set_we  (gpio_set_sel   && mem_valid && (|mem_wstrb)),
    .reg_set_di  (mem_wdata),
    .reg_clr_we  (gpio_clr_sel   && mem_valid && (|mem_wstrb)),
    .reg_clr_di  (mem_wdata),
    .reg_tog_we  (gpio_tog_sel   && mem_valid && (|mem_wstrb)),
    .reg_tog_di  (mem_wdata),
    .reg_ien_we  (gpio_ien_sel   && mem_valid && (|mem_wstrb)),
    .reg_ien_di  (mem_wdata),   .reg_ien_do  (gpio_ien_do),
    .reg_istat_we(gpio_istat_sel && mem_valid && (|mem_wstrb)),
    .reg_istat_di(mem_wdata),   .reg_istat_do(gpio_istat_do),
    .reg_icfg_we (gpio_icfg_sel  && mem_valid && (|mem_wstrb)),
    .reg_icfg_di (mem_wdata),   .reg_icfg_do (gpio_icfg_do),
    .irq         (gpio_irq)
);

wire        gpio_ready = gpio_sel && mem_valid;
wire [31:0] gpio_rdata =
    gpio_dir_sel   ? gpio_dir_do   :
    gpio_out_sel   ? gpio_out_do   :
    gpio_in_sel    ? gpio_in_do    :
    gpio_ien_sel   ? gpio_ien_do   :
    gpio_istat_sel ? gpio_istat_do :
    gpio_icfg_sel  ? gpio_icfg_do  :
    32'b0;

// ════════════════════════════════════════════════════════════
//  TIMER
// ════════════════════════════════════════════════════════════
wire [31:0] timer_ctrl_do, timer_psc_do;
wire [31:0] timer_cnt_do, timer_top_do, timer_cmp_do, timer_istat_do;
wire        timer_irq;

simpletimer #(.NUM_CH(NUM_TIMER_CH)) timer_inst (
    .clk         (clk),    .resetn      (resetn),   .pwm_out(pwm_out),
    .reg_ctrl_we (timer_ctrl_sel  && mem_valid && (|mem_wstrb)),
    .reg_ctrl_di (mem_wdata),   .reg_ctrl_do (timer_ctrl_do),
    .reg_psc_we  ((timer_psc_sel && mem_valid) ? mem_wstrb : 4'b0),
    .reg_psc_di  (mem_wdata),   .reg_psc_do  (timer_psc_do),
    .reg_cnt_sel (timer_ch_sel), .reg_cnt_do  (timer_cnt_do),
    .reg_top_sel (timer_ch_sel),
    .reg_top_we  (timer_top_sel  && mem_valid && (|mem_wstrb)),
    .reg_top_di  (mem_wdata),   .reg_top_do  (timer_top_do),
    .reg_cmp_sel (timer_ch_sel),
    .reg_cmp_we  (timer_cmp_sel  && mem_valid && (|mem_wstrb)),
    .reg_cmp_di  (mem_wdata),   .reg_cmp_do  (timer_cmp_do),
    .reg_istat_we(timer_istat_sel && mem_valid && (|mem_wstrb)),
    .reg_istat_di(mem_wdata),   .reg_istat_do(timer_istat_do),
    .irq         (timer_irq)
);

wire        timer_ready = timer_sel && mem_valid;
wire [31:0] timer_rdata =
    timer_ctrl_sel  ? timer_ctrl_do  :
    timer_psc_sel   ? timer_psc_do   :
    timer_cnt_sel   ? timer_cnt_do   :
    timer_top_sel   ? timer_top_do   :
    timer_cmp_sel   ? timer_cmp_do   :
    timer_istat_sel ? timer_istat_do :
    32'b0;

// ════════════════════════════════════════════════════════════
//  SPI
// ════════════════════════════════════════════════════════════
wire [31:0] spi_div_do, spi_cfg_do, spi_cs_do, spi_stat_do, spi_dat_do;
wire        spi_dat_wait;

simplespi #(
    .DEFAULT_DIV(62),
    .NUM_CS     (NUM_SPI_CS),
    .CS_HOLD_BITS(8)
) spi_inst (
    .clk         (clk),    .resetn      (resetn),
    .spi_sck     (spi_sck),.spi_mosi    (spi_mosi),
    .spi_miso    (spi_miso),.spi_cs_n   (spi_cs_n),
    .reg_div_we  ((spi_div_sel  && mem_valid) ? mem_wstrb : 4'b0),
    .reg_div_di  (mem_wdata),   .reg_div_do  (spi_div_do),
    .reg_cfg_we  (spi_cfg_sel  && mem_valid && (|mem_wstrb)),
    .reg_cfg_di  (mem_wdata),   .reg_cfg_do  (spi_cfg_do),
    .reg_cs_we   (spi_cs_sel   && mem_valid && (|mem_wstrb)),
    .reg_cs_di   (mem_wdata),   .reg_cs_do   (spi_cs_do),
    .reg_stat_do (spi_stat_do),
    .reg_dat_we  (spi_dat_sel  && mem_valid && (|mem_wstrb)),
    .reg_dat_re  (spi_dat_sel  && mem_valid && (mem_wstrb == 4'b0)),
    .reg_dat_di  (mem_wdata),
    .reg_dat_do  (spi_dat_do),
    .reg_dat_wait(spi_dat_wait)
);

wire spi_ready =
    (spi_sel && mem_valid && !spi_dat_sel) ||
    (spi_dat_sel && mem_valid && (mem_wstrb == 4'b0)) ||
    (spi_dat_sel && mem_valid && (|mem_wstrb) && !spi_dat_wait);

wire [31:0] spi_rdata =
    spi_div_sel  ? spi_div_do  :
    spi_cfg_sel  ? spi_cfg_do  :
    spi_cs_sel   ? spi_cs_do   :
    spi_stat_sel ? spi_stat_do :
    spi_dat_sel  ? spi_dat_do  :
    32'b0;

// ════════════════════════════════════════════════════════════
//  I2C
// ════════════════════════════════════════════════════════════

// CPU-writable registers
reg [6:0]   i2c_addr_r;
reg         i2c_rw_r;
reg [3:0]   i2c_txlen_r;
reg [3:0]   i2c_rxlen_r;
reg [127:0] i2c_txbuf_r;   // flat: byte0=bits[127:120]
reg         i2c_start_r;

wire [127:0] i2c_rxbuf_w;
wire         i2c_busy_w;
wire         i2c_ack_err_w;
wire         i2c_scl_oe, i2c_sda_oe, i2c_sda_in;

// Open-drain
assign i2c_scl    = i2c_scl_oe ? 1'b0 : 1'bz;
assign i2c_sda    = i2c_sda_oe ? 1'b0 : 1'bz;
assign i2c_sda_in = i2c_sda;

// Helper: lấy byte idx từ flat bus (dùng trong read-back)
// byte0 = bits[127:120], byte1 = bits[119:112], ...
function [7:0] flat_get;
    input [127:0] bus;
    input [3:0]   idx;
    flat_get = bus[127 - (idx << 3) -: 8];
endfunction

// Helper: ghi byte idx vào flat bus
// Trả về bus mới với byte tại idx được thay bằng val
function [127:0] flat_set;
    input [127:0] bus;
    input [3:0]   idx;
    input [7:0]   val;
    reg [127:0]   tmp;
    reg [6:0]     hi;
    begin
        tmp    = bus;
        hi     = 7'd127 - {idx, 3'b000};
        tmp[hi -: 8] = val;
        flat_set = tmp;
    end
endfunction

// CPU write handler
always @(posedge clk or negedge resetn) begin
    if (!resetn) begin
        i2c_addr_r  <= 7'd0;
        i2c_rw_r    <= 1'b0;
        i2c_txlen_r <= 4'd1;
        i2c_rxlen_r <= 4'd1;
        i2c_txbuf_r <= 128'd0;
        i2c_start_r <= 1'b0;
    end else begin
        i2c_start_r <= 1'b0;

        if (i2c_sel && mem_valid && (|mem_wstrb)) begin
            if (i2c_ctrl_sel) begin
                if (mem_wstrb[0]) begin
                    i2c_addr_r <= mem_wdata[6:0];
                    i2c_rw_r   <= mem_wdata[7];
                end
                if (mem_wstrb[3] && mem_wdata[31] && !i2c_busy_w)
                    i2c_start_r <= 1'b1;
            end
            if (i2c_txlen_sel && mem_wstrb[0])
                i2c_txlen_r <= mem_wdata[3:0];
            if (i2c_rxlen_sel && mem_wstrb[0])
                i2c_rxlen_r <= mem_wdata[3:0];
            if (i2c_txbuf_sel && mem_wstrb[0])
                i2c_txbuf_r <= flat_set(i2c_txbuf_r, i2c_txbuf_idx, mem_wdata[7:0]);
        end
    end
end

i2c_master #(.CLK_DIV(67)) u_i2c (
    .clk    (clk),
    .resetn (resetn),
    .start  (i2c_start_r),
    .rw     (i2c_rw_r),
    .addr   (i2c_addr_r),
    .tx_len (i2c_txlen_r),
    .rx_len (i2c_rxlen_r),
    .tx_buf (i2c_txbuf_r),
    .rx_buf (i2c_rxbuf_w),
    .busy   (i2c_busy_w),
    .ack_err(i2c_ack_err_w),
    .scl_oe (i2c_scl_oe),
    .sda_oe (i2c_sda_oe),
    .sda_in (i2c_sda_in)
);

wire        i2c_ready = i2c_sel && mem_valid;

wire [31:0] i2c_rdata =
    i2c_ctrl_sel  ? {24'b0, i2c_rw_r,      i2c_addr_r}              :
    i2c_stat_sel  ? {30'b0, i2c_ack_err_w, i2c_busy_w}              :
    i2c_txlen_sel ? {28'b0, i2c_txlen_r}                             :
    i2c_rxlen_sel ? {28'b0, i2c_rxlen_r}                             :
    i2c_txbuf_sel ? {24'b0, flat_get(i2c_txbuf_r, i2c_txbuf_idx)}   :
    i2c_rxbuf_sel ? {24'b0, flat_get(i2c_rxbuf_w, i2c_rxbuf_idx)}   :
    32'h0;

// ════════════════════════════════════════════════════════════
//  IRQ / memory bus fabric
// ════════════════════════════════════════════════════════════
assign irq_cpu = {{30{1'b0}}, timer_irq, gpio_irq};

wire periph_sel  = uart_sel || gpio_sel || timer_sel || spi_sel || i2c_sel;
wire default_sel = !ram_sel && !periph_sel;

assign mem_ready =
    (ram_sel   && ram_ready)   ||
    (uart_sel  && uart_ready)  ||
    (gpio_sel  && gpio_ready)  ||
    (timer_sel && timer_ready) ||
    (spi_sel   && spi_ready)   ||
    (i2c_sel   && i2c_ready)   ||
    (default_sel && mem_valid);

assign mem_rdata =
    ram_sel   ? ram_rdata   :
    uart_sel  ? (uart_div_sel ? uart_div_do : uart_dat_do) :
    gpio_sel  ? gpio_rdata  :
    timer_sel ? timer_rdata :
    spi_sel   ? spi_rdata   :
    i2c_sel   ? i2c_rdata   :
    32'b0;

// ════════════════════════════════════════════════════════════
//  PicoRV32
// ════════════════════════════════════════════════════════════
picorv32 #(
    .ENABLE_COUNTERS     (1),  .ENABLE_COUNTERS64   (0),
    .ENABLE_REGS_16_31   (1),  .ENABLE_REGS_DUALPORT(1),
    .LATCHED_MEM_RDATA   (0),  .TWO_STAGE_SHIFT     (1),
    .BARREL_SHIFTER      (1),  .TWO_CYCLE_COMPARE   (0),
    .TWO_CYCLE_ALU       (0),  .COMPRESSED_ISA      (0),
    .CATCH_MISALIGN      (1),  .CATCH_ILLINSN       (1),
    .ENABLE_PCPI         (0),  .ENABLE_MUL          (1),
    .ENABLE_FAST_MUL     (0),  .ENABLE_DIV          (1),
    .ENABLE_IRQ          (1),  .ENABLE_IRQ_QREGS    (1),
    .ENABLE_IRQ_TIMER    (1),  .ENABLE_TRACE        (0),
    .REGS_INIT_ZERO      (1),
    .MASKED_IRQ          (32'b0),
    .LATCHED_IRQ         (32'hffff_ffff),
    .PROGADDR_RESET      (32'h0000_0000),
    .PROGADDR_IRQ        (32'h0000_0010),
    .STACKADDR           (32'h0000_7FFF)
) cpu (
    .clk      (clk),      .resetn   (resetn),   .trap     (),
    .mem_valid(mem_valid), .mem_instr(mem_instr),
    .mem_addr (mem_addr),  .mem_wdata(mem_wdata),
    .mem_wstrb(mem_wstrb), .mem_rdata(mem_rdata),
    .mem_ready(mem_ready),
    .mem_la_read (mem_la_read),  .mem_la_write(mem_la_write),
    .mem_la_addr (mem_la_addr),  .mem_la_wdata(mem_la_wdata),
    .mem_la_wstrb(mem_la_wstrb),
    .pcpi_valid(pcpi_valid), .pcpi_insn(pcpi_insn),
    .pcpi_rs1(pcpi_rs1),   .pcpi_rs2(pcpi_rs2),
    .pcpi_wr(1'b0),  .pcpi_rd(32'b0),
    .pcpi_wait(1'b0), .pcpi_ready(1'b0),
    .irq(irq_cpu),   .eoi(eoi),
    .trace_valid(trace_valid), .trace_data(trace_data)
);

endmodule
`default_nettype wire