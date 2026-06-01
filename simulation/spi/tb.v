`timescale 1ns/1ps
`default_nettype none

module tb_simplespi;

    // =========================
    // DUT signals
    // =========================
    reg         clk;
    reg         resetn;

    wire        spi_sck;
    wire        spi_mosi;
    reg         spi_miso;
    wire [0:0]  spi_cs_n;

    reg  [3:0]  reg_div_we;
    reg  [31:0] reg_div_di;
    wire [31:0] reg_div_do;

    reg         reg_cfg_we;
    reg  [31:0] reg_cfg_di;
    wire [31:0] reg_cfg_do;

    reg         reg_cs_we;
    reg  [31:0] reg_cs_di;
    wire [31:0] reg_cs_do;

    wire [31:0] reg_stat_do;

    reg         reg_dat_we;
    reg         reg_dat_re;
    reg  [31:0] reg_dat_di;
    wire [31:0] reg_dat_do;
    wire        reg_dat_wait;

    // =========================
    // Instantiate DUT
    // =========================
    simplespi #(
        .DEFAULT_DIV(3),     // cho mô phỏng nhanh
        .NUM_CS(1),
        .CS_HOLD_BITS(4)
    ) dut (
        .clk(clk),
        .resetn(resetn),

        .spi_sck(spi_sck),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        .spi_cs_n(spi_cs_n),

        .reg_div_we(reg_div_we),
        .reg_div_di(reg_div_di),
        .reg_div_do(reg_div_do),

        .reg_cfg_we(reg_cfg_we),
        .reg_cfg_di(reg_cfg_di),
        .reg_cfg_do(reg_cfg_do),

        .reg_cs_we(reg_cs_we),
        .reg_cs_di(reg_cs_di),
        .reg_cs_do(reg_cs_do),

        .reg_stat_do(reg_stat_do),

        .reg_dat_we(reg_dat_we),
        .reg_dat_re(reg_dat_re),
        .reg_dat_di(reg_dat_di),
        .reg_dat_do(reg_dat_do),
        .reg_dat_wait(reg_dat_wait)
    );

    // =========================
    // Clock 100 MHz
    // =========================
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // =========================
    // MISO test pattern
    // Ví dụ trả về 8'b1010_0101 = 8'hA5
    // Đổi bit ở cạnh xuống của SCK để DUT sample ổn định
    // =========================
    reg [7:0] miso_pattern;
    integer   miso_idx;

    initial begin
        spi_miso     = 1'b0;
        miso_pattern = 8'hA5;
        miso_idx     = 7;
    end

    always @(negedge spi_sck or posedge spi_cs_n[0]) begin
        if (spi_cs_n[0]) begin
            miso_idx  <= 7;
            spi_miso  <= miso_pattern[7];
        end else begin
            spi_miso <= miso_pattern[miso_idx];
            if (miso_idx > 0)
                miso_idx <= miso_idx - 1;
            else
                miso_idx <= 7;
        end
    end

    // =========================
    // Tasks
    // =========================
    task write_div(input [31:0] v);
    begin
        @(posedge clk);
        reg_div_di <= v;
        reg_div_we <= 4'b1111;
        @(posedge clk);
        reg_div_we <= 4'b0000;
    end
    endtask

    task write_cfg(input [31:0] v);
    begin
        @(posedge clk);
        reg_cfg_di <= v;
        reg_cfg_we <= 1'b1;
        @(posedge clk);
        reg_cfg_we <= 1'b0;
    end
    endtask

    task write_dat(input [7:0] data, input cs_end);
    begin
        @(posedge clk);
        reg_dat_di <= {23'd0, cs_end, data}; // bit[8]=cs_end, bit[7:0]=data
        reg_dat_we <= 1'b1;
        @(posedge clk);
        reg_dat_we <= 1'b0;
    end
    endtask

    task read_dat_clear_valid;
    begin
        @(posedge clk);
        reg_dat_re <= 1'b1;
        @(posedge clk);
        reg_dat_re <= 1'b0;
    end
    endtask

    // =========================
    // Monitor
    // =========================
    initial begin
        $display("time   rst cs sck mosi miso busy valid dat_do");
        $monitor("%0t  %b   %b  %b   %b    %b    %b    %b    0x%08X",
                 $time, resetn, spi_cs_n[0], spi_sck, spi_mosi, spi_miso,
                 reg_stat_do[0], reg_stat_do[1], reg_dat_do);
    end

    // =========================
    // Test sequence
    // =========================
    initial begin
        // init
        resetn     = 1'b0;
        spi_miso   = 1'b0;

        reg_div_we = 4'd0;
        reg_div_di = 32'd0;

        reg_cfg_we = 1'b0;
        reg_cfg_di = 32'd0;

        reg_cs_we  = 1'b0;
        reg_cs_di  = 32'd0;

        reg_dat_we = 1'b0;
        reg_dat_re = 1'b0;
        reg_dat_di = 32'd0;

        // reset
        repeat (5) @(posedge clk);
        resetn = 1'b1;
        repeat (2) @(posedge clk);

        // cấu hình mode 0, MSB first, auto CS = 1
        // reg_cfg_di[1:0]=mode, [2]=lsb_first, [3]=cs_auto
        write_cfg(32'h0000_0008); // 1000b => cs_auto=1, lsb_first=0, mode=0

        // divider nhỏ để chạy nhanh
        write_div(32'd3);

        $display("\n--- START SPI TRANSFER ---");
        write_dat(8'h3C, 1'b1); // gửi 0x3C, kết thúc thì nhả CS

        // chờ transfer xong
        wait (reg_stat_do[0] == 1'b1); // busy=1
        wait (reg_stat_do[0] == 1'b0); // busy=0

        $display("\n--- TRANSFER DONE ---");
        $display("STAT = 0x%08X", reg_stat_do);
        $display("DAT  = 0x%08X", reg_dat_do);

        if (reg_dat_do[31] !== 1'b1)
            $display("ERROR: recv_valid not set");
        else
            $display("RX byte = 0x%02X", reg_dat_do[7:0]);

        // đọc DAT để clear valid
        read_dat_clear_valid();
        @(posedge clk);
        $display("After reg_dat_re, DAT = 0x%08X", reg_dat_do);

        #100;
        $finish;
    end

endmodule

`default_nettype wire