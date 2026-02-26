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
    output wire sd_cs
);

// dây kết nối
wire mem_valid;
wire mem_ready;
wire [31:0] mem_addr;
wire [31:0] mem_wdata;
wire [3:0]  mem_wstrb;
wire [31:0] mem_rdata;
wire ram_sel = mem_valid && (mem_addr < 32'h00008000);
wire uart_sel = mem_valid && (mem_addr[31:24] == 8'h10);
wire sd_sel   = mem_valid && (mem_addr[31:24] == 8'h20);
wire ram_ready;
wire [31:0] ram_rdata;

// CPU
picorv32 cpu (
    .clk(clk),
    .resetn(resetn),
    .mem_valid(mem_valid),
    .mem_ready(mem_ready),
    .mem_addr(mem_addr),
    .mem_wdata(mem_wdata),
    .mem_wstrb(mem_wstrb),
    .mem_rdata(mem_rdata)
);

// RAM


picorv32_ram ram (
    .clk(clk),
    .mem_valid(ram_sel),
    .mem_ready(ram_ready),
    .mem_addr(mem_addr),
    .mem_wdata(mem_wdata),
    .mem_wstrb(mem_wstrb),
    .mem_rdata(ram_rdata)
);

wire uart_ready;
wire [31:0] uart_rdata;
wire uart_wait;

wire mem_write = (mem_wstrb != 4'b0000);
wire mem_read  = (mem_wstrb == 4'b0000);

wire uart_reg_div_we = uart_sel && mem_write && mem_addr[2];
wire uart_reg_dat_we = uart_sel && mem_write && !mem_addr[2];
wire uart_reg_dat_re = uart_sel && mem_read  && !mem_addr[2];

simpleuart #(
    .DEFAULT_DIV(234)  // 27MHz / 115200
) uart (
    .clk(clk),
    .resetn(resetn),

    .ser_tx(uart_tx),
    .ser_rx(uart_rx),

    .reg_div_we(uart_reg_div_we ? mem_wstrb : 4'b0),
    .reg_div_di(mem_wdata),
    .reg_div_do(),

    .reg_dat_we(uart_reg_dat_we),
    .reg_dat_re(uart_reg_dat_re),
    .reg_dat_di(mem_wdata),
    .reg_dat_do(uart_rdata),
    .reg_dat_wait(uart_wait)
);

assign uart_ready = uart_sel && !uart_wait;

wire sd_ready;
wire [31:0] sd_rdata;

sd_spi_helper #(
    .CLK_FREQ(27000000)
) sdspi (
    .clk(clk),
    .reset_n(resetn),
    .sd_spi_sel(sd_sel),
    .sd_spi_data_i(mem_wdata[7:0]),
    .we(|mem_wstrb),
    .addr(mem_addr[3:2]),
    .sd_miso(sd_miso),

    .sd_spi_ready(sd_ready),
    .sd_spi_data_o(sd_rdata),
    .sd_mosi(sd_mosi),
    .sd_clk(sd_clk),
    .sd_cs(sd_cs)
);

assign mem_ready =
    (ram_sel  && ram_ready)  |
    (uart_sel && uart_ready) |
    (sd_sel   && sd_ready);
assign mem_rdata = ram_sel  ? ram_rdata  : uart_sel ? uart_rdata : sd_sel   ? sd_rdata   : 32'h00000000;

endmodule