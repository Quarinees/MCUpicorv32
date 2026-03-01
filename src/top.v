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

// ============================
// Memory wires
// ============================
wire mem_valid;
wire mem_ready;
wire [31:0] mem_addr;
wire [31:0] mem_wdata;
wire [3:0]  mem_wstrb;
wire [31:0] mem_rdata;

wire mem_write = |mem_wstrb;
wire mem_read  = ~|mem_wstrb;

// ============================
// Address decode
// ============================
wire ram_sel  = mem_valid && (mem_addr < 32'h00008000);
wire uart_sel = mem_valid && (mem_addr[31:24] == 8'h10);
wire sd_sel   = mem_valid && (mem_addr[31:24] == 8'h20);
wire i2c_sel  = mem_valid && (mem_addr[31:24] == 8'h30);

// ============================
// CPU
// ============================
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

// ============================
// RAM (32KB)
// ============================
wire ram_ready;
wire [31:0] ram_rdata;

picorv32_ram ram (
    .clk(clk),
    .mem_valid(ram_sel),
    .mem_ready(ram_ready),
    .mem_addr(mem_addr),
    .mem_wdata(mem_wdata),
    .mem_wstrb(mem_wstrb),
    .mem_rdata(ram_rdata)
);

// ============================
// UART
// ============================
wire uart_ready;
wire [31:0] uart_rdata;
wire uart_wait;

wire uart_reg_div_we = uart_sel && mem_write && mem_addr[2];
wire uart_reg_dat_we = uart_sel && mem_write && !mem_addr[2];
wire uart_reg_dat_re = uart_sel && mem_read  && !mem_addr[2];

simpleuart #(
    .DEFAULT_DIV(234)
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

// ============================
// SD SPI
// ============================
wire sd_ready;
wire [31:0] sd_rdata;

sd_spi_helper #(
    .CLK_FREQ(27000000)
) sdspi (
    .clk(clk),
    .reset_n(resetn),

    .sd_spi_sel(sd_sel),
    .sd_spi_data_i(mem_wdata[7:0]),
    .we(mem_write),
    .addr(mem_addr[3:2]),

    .sd_miso(sd_miso),
    .sd_spi_ready(sd_ready),
    .sd_spi_data_o(sd_rdata),

    .sd_mosi(sd_mosi),
    .sd_clk(sd_clk),
    .sd_cs(sd_cs)
);

// ============================
// I2C
// ============================
// ============================
// I2C (SSD1306 style controller)
// ============================

wire i2c_start;
wire i2c_busy;
wire [7:0] i2c_data;
wire i2c_dcn;

reg i2c_start_r = 0;
reg [7:0] i2c_data_r;
reg i2c_dcn_r;

// decode write
wire i2c_write = i2c_sel && mem_write;

// tạo xung start 1 clock
always @(posedge clk) begin
    i2c_start_r <= 0;

    if (i2c_write) begin
        i2c_data_r  <= mem_wdata[7:0];
        i2c_dcn_r   <= mem_wdata[8];
        i2c_start_r <= 1;
    end
end

assign i2c_start = i2c_start_r;
assign i2c_data  = i2c_data_r;
assign i2c_dcn   = i2c_dcn_r;

I2C i2c (
    .clk(clk),
    .start(i2c_start),
    .DCn(i2c_dcn),
    .Data(i2c_data),
    .busy(i2c_busy),
    .scl(i2c_scl),
    .sda(i2c_sda)
);

// ready khi không busy
wire i2c_ready = i2c_sel && !i2c_busy;

// read trả về busy ở bit0
wire [31:0] i2c_rdata = {31'b0, i2c_busy};

// ============================
// Bus MUX
// ============================
assign mem_ready =
    (ram_sel  && ram_ready)  |
    (uart_sel && uart_ready) |
    (sd_sel   && sd_ready)   |
    (i2c_sel  && i2c_ready);

assign mem_rdata =
    ram_sel  ? ram_rdata  :
    uart_sel ? uart_rdata :
    sd_sel   ? sd_rdata   :
    i2c_sel  ? i2c_rdata  :
    32'h00000000;

endmodule