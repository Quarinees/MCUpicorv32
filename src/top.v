// =============================================================
//  top.v  –  PicoRV32 SoC
//  RAM + UART + SD-SPI + I2C peripheral (dùng I2C_Master riêng)
//
//  Memory map:
//    0x0000_0000 – 0x0000_7FFF   RAM  (32 KB)
//    0x1000_0000                 UART
//    0x2000_0000                 SD SPI
//    0x3000_0000 – 0x3000_0017   I2C
//
//  I2C register map (offset từ 0x3000_0000):
//    +0x00  CTRL      W   [6:0]=slave_addr  [7]=rw
//                         [15:8]=ctrl_byte  [16]=en_ctrl_byte
//                         [19:17]=byte_count-1 (0-based)
//                         [31]=START  ← write 1 triggers transfer
//                                       CPU stalls until I2C done
//    +0x04  STATUS    R   [0]=busy  [1]=nack_err
//    +0x08  TX_DATA0  W   payload byte[3:0]
//    +0x0C  TX_DATA1  W   payload byte[7:4]
//    +0x10  RX_DATA0  R   received byte[3:0]
//    +0x14  RX_DATA1  R   received byte[7:4]
// =============================================================

module top (
    input  wire clk,
    input  wire resetn,
    // UART
    output wire uart_tx,
    input  wire uart_rx,
    // SD card SPI
    input  wire sd_miso,
    output wire sd_mosi,
    output wire sd_clk,
    output wire sd_cs,
    // I2C
    inout  wire i2c_sda,
    output wire i2c_scl
);

// ============================================================
// Memory wires
// ============================================================
wire        mem_valid;
wire        mem_ready;
wire [31:0] mem_addr;
wire [31:0] mem_wdata;
wire [ 3:0] mem_wstrb;
wire [31:0] mem_rdata;
wire mem_write = |mem_wstrb;
wire mem_read  = ~|mem_wstrb;

// ============================================================
// Address decode
// ============================================================
wire ram_sel  = mem_valid && (mem_addr < 32'h0000_8000);
wire uart_sel = mem_valid && (mem_addr[31:24] == 8'h10);
wire sd_sel   = mem_valid && (mem_addr[31:24] == 8'h20);
wire i2c_sel  = mem_valid && (mem_addr[31:24] == 8'h30);

// ============================================================
// CPU
// ============================================================
picorv32 cpu (
    .clk      (clk),
    .resetn   (resetn),
    .mem_valid(mem_valid),
    .mem_ready(mem_ready),
    .mem_addr (mem_addr),
    .mem_wdata(mem_wdata),
    .mem_wstrb(mem_wstrb),
    .mem_rdata(mem_rdata)
);

// ============================================================
// RAM (32 KB)
// ============================================================
wire        ram_ready;
wire [31:0] ram_rdata;

picorv32_ram ram (
    .clk      (clk),
    .mem_valid(ram_sel),
    .mem_ready(ram_ready),
    .mem_addr (mem_addr),
    .mem_wdata(mem_wdata),
    .mem_wstrb(mem_wstrb),
    .mem_rdata(ram_rdata)
);

// ============================================================
// UART
// ============================================================
wire        uart_ready;
wire [31:0] uart_rdata;
wire        uart_wait;

wire uart_reg_div_we = uart_sel && mem_write &&  mem_addr[2];
wire uart_reg_dat_we = uart_sel && mem_write && !mem_addr[2];
wire uart_reg_dat_re = uart_sel && mem_read  && !mem_addr[2];

simpleuart #(.DEFAULT_DIV(234)) uart (
    .clk         (clk),
    .resetn      (resetn),
    .ser_tx      (uart_tx),
    .ser_rx      (uart_rx),
    .reg_div_we  (uart_reg_div_we ? mem_wstrb : 4'b0),
    .reg_div_di  (mem_wdata),
    .reg_div_do  (),
    .reg_dat_we  (uart_reg_dat_we),
    .reg_dat_re  (uart_reg_dat_re),
    .reg_dat_di  (mem_wdata),
    .reg_dat_do  (uart_rdata),
    .reg_dat_wait(uart_wait)
);

assign uart_ready = uart_sel && !uart_wait;

// ============================================================
// SD SPI
// ============================================================
wire        sd_ready;
wire [31:0] sd_rdata;

sd_spi_helper #(.CLK_FREQ(27000000)) sdspi (
    .clk          (clk),
    .reset_n      (resetn),
    .sd_spi_sel   (sd_sel),
    .sd_spi_data_i(mem_wdata[7:0]),
    .we           (mem_write),
    .addr         (mem_addr[3:2]),
    .sd_miso      (sd_miso),
    .sd_spi_ready (sd_ready),
    .sd_spi_data_o(sd_rdata),
    .sd_mosi      (sd_mosi),
    .sd_clk       (sd_clk),
    .sd_cs        (sd_cs)
);

// ============================================================
// I2C peripheral – fixed v3
// ============================================================
localparam I2C_CLK_DIV   = 135;
localparam I2C_MAX_BYTES = 8;

reg        i2c_rw       = 0;
reg [ 6:0] i2c_addr     = 0;
reg [ 7:0] i2c_ctrlbyte = 0;
reg        i2c_en_ctrl  = 0;
reg [ 3:0] i2c_bcnt     = 1;
reg [63:0] i2c_txpay    = 0;

reg        i2c_start     = 0;
wire       i2c_busy;
wire       i2c_nack;
wire[63:0] i2c_rxdata;
wire       i2c_rxvalid;

reg [63:0] i2c_rx_latch = 0;
always @(posedge clk)
    if (i2c_rxvalid) i2c_rx_latch <= i2c_rxdata;

reg i2c_stall     = 0;
reg i2c_busy_seen = 0;

wire i2c_done = i2c_stall && i2c_busy_seen && !i2c_busy;

always @(posedge clk) begin
    if (!resetn) begin
        i2c_stall     <= 0;
        i2c_start     <= 0;
        i2c_busy_seen <= 0;
        i2c_rw        <= 0;
        i2c_addr      <= 0;
        i2c_ctrlbyte  <= 0;
        i2c_en_ctrl   <= 0;
        i2c_bcnt      <= 1;
        i2c_txpay     <= 0;

    end else begin

        // Clear start khi FSM latch
        if (i2c_busy) begin
            i2c_start     <= 0;
            i2c_busy_seen <= 1;
        end

        // Nhả stall khi I2C xong
        if (i2c_done)
            i2c_stall <= 0;

        // CPU write – chỉ khi không stall
        if (i2c_sel && mem_write && !i2c_stall) begin
            case (mem_addr[5:2])

            4'd0: begin  // CTRL
                if (mem_wstrb[0]) begin
                    i2c_addr <= mem_wdata[6:0];
                    i2c_rw   <= mem_wdata[7];
                end
                if (mem_wstrb[1])
                    i2c_ctrlbyte <= mem_wdata[15:8];
                if (mem_wstrb[2]) begin
                    i2c_en_ctrl <= mem_wdata[16];
                    i2c_bcnt    <= {1'b0, mem_wdata[19:17]} + 1;
                end
                if (mem_wstrb[3] && mem_wdata[31]) begin
                    i2c_start     <= 1;
                    i2c_stall     <= 1;
                    i2c_busy_seen <= 0;
                end
            end

            4'd2: begin  // TX_DATA0
                if (mem_wstrb[0]) i2c_txpay[ 0+:8] <= mem_wdata[ 0+:8];
                if (mem_wstrb[1]) i2c_txpay[ 8+:8] <= mem_wdata[ 8+:8];
                if (mem_wstrb[2]) i2c_txpay[16+:8] <= mem_wdata[16+:8];
                if (mem_wstrb[3]) i2c_txpay[24+:8] <= mem_wdata[24+:8];
            end

            4'd3: begin  // TX_DATA1
                if (mem_wstrb[0]) i2c_txpay[32+:8] <= mem_wdata[ 0+:8];
                if (mem_wstrb[1]) i2c_txpay[40+:8] <= mem_wdata[ 8+:8];
                if (mem_wstrb[2]) i2c_txpay[48+:8] <= mem_wdata[16+:8];
                if (mem_wstrb[3]) i2c_txpay[56+:8] <= mem_wdata[24+:8];
            end

            default: ;
            endcase
        end
    end
end

wire i2c_ready = i2c_sel && (!i2c_stall || i2c_done);

wire [31:0] i2c_rdata =
    (mem_addr[5:2] == 4'd0) ? {12'b0,
                                i2c_bcnt[2:0] - 3'd1,
                                i2c_en_ctrl,
                                i2c_ctrlbyte,
                                i2c_rw,
                                i2c_addr}                  :
    (mem_addr[5:2] == 4'd1) ? {30'b0, i2c_nack, i2c_busy} :
    (mem_addr[5:2] == 4'd4) ? i2c_rx_latch[31: 0]         :
    (mem_addr[5:2] == 4'd5) ? i2c_rx_latch[63:32]         :
    32'h0000_0000;

I2C_Master #(
    .CLK_DIV  (I2C_CLK_DIV),
    .MAX_BYTES(I2C_MAX_BYTES)
) u_i2c (
    .clk         (clk),
    .rst         (~resetn),
    .start       (i2c_start),
    .rw          (i2c_rw),
    .slave_addr  (i2c_addr),
    .ctrl_byte   (i2c_ctrlbyte),
    .en_ctrl_byte(i2c_en_ctrl),
    .tx_payload  (i2c_txpay),
    .byte_count  (i2c_bcnt),
    .busy        (i2c_busy),
    .nack_err    (i2c_nack),
    .rx_data     (i2c_rxdata),
    .rx_valid    (i2c_rxvalid),
    .scl         (i2c_scl),
    .sda         (i2c_sda)
);

// ============================================================
// Bus MUX
// ============================================================
assign mem_ready =
    (ram_sel  && ram_ready)  |
    (uart_sel && uart_ready) |
    (sd_sel   && sd_ready)   |
    (i2c_sel  && i2c_ready)  ;

assign mem_rdata =
    ram_sel  ? ram_rdata  :
    uart_sel ? uart_rdata :
    sd_sel   ? sd_rdata   :
    i2c_sel  ? i2c_rdata  :
    32'h0000_0000;

endmodule
/*
```

---

## Cấu trúc project
```
project/
├── top.v           ← file này (SoC + I2C peripheral wrapper)
├── i2c_master.v    ← I2C_Master module (file riêng, không đổi)
├── picorv32.v      ← từ YosysHQ
├── picorv32_ram.v
├── simpleuart.v 
└── sd_spi_helper.v */