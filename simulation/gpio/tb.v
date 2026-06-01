`timescale 1ns/1ps
`default_nettype none

module tb_simplegpio;

    localparam integer NUM_GPIO = 8;

    reg clk;
    reg resetn;

    tri [NUM_GPIO-1:0] gpio;

    reg         reg_dir_we;
    reg  [31:0] reg_dir_di;
    wire [31:0] reg_dir_do;

    reg         reg_out_we;
    reg  [31:0] reg_out_di;
    wire [31:0] reg_out_do;

    wire [31:0] reg_in_do;

    reg         reg_set_we;
    reg  [31:0] reg_set_di;
    reg         reg_clr_we;
    reg  [31:0] reg_clr_di;
    reg         reg_tog_we;
    reg  [31:0] reg_tog_di;

    reg         reg_ien_we;
    reg  [31:0] reg_ien_di;
    wire [31:0] reg_ien_do;

    reg         reg_istat_we;
    reg  [31:0] reg_istat_di;
    wire [31:0] reg_istat_do;

    reg         reg_icfg_we;
    reg  [31:0] reg_icfg_di;
    wire [31:0] reg_icfg_do;

    wire irq;

    // driver ngoài cho các chân input
    reg  [NUM_GPIO-1:0] gpio_drv;
    reg  [NUM_GPIO-1:0] gpio_drv_en;

    genvar k;
    generate
        for (k = 0; k < NUM_GPIO; k = k + 1) begin : EXT_DRV
            assign gpio[k] = gpio_drv_en[k] ? gpio_drv[k] : 1'bz;
        end
    endgenerate

    simplegpio #(
        .NUM_GPIO(NUM_GPIO)
    ) dut (
        .clk(clk),
        .resetn(resetn),
        .gpio(gpio),

        .reg_dir_we(reg_dir_we),
        .reg_dir_di(reg_dir_di),
        .reg_dir_do(reg_dir_do),

        .reg_out_we(reg_out_we),
        .reg_out_di(reg_out_di),
        .reg_out_do(reg_out_do),

        .reg_in_do(reg_in_do),

        .reg_set_we(reg_set_we),
        .reg_set_di(reg_set_di),
        .reg_clr_we(reg_clr_we),
        .reg_clr_di(reg_clr_di),
        .reg_tog_we(reg_tog_we),
        .reg_tog_di(reg_tog_di),

        .reg_ien_we(reg_ien_we),
        .reg_ien_di(reg_ien_di),
        .reg_ien_do(reg_ien_do),

        .reg_istat_we(reg_istat_we),
        .reg_istat_di(reg_istat_di),
        .reg_istat_do(reg_istat_do),

        .reg_icfg_we(reg_icfg_we),
        .reg_icfg_di(reg_icfg_di),
        .reg_icfg_do(reg_icfg_do),

        .irq(irq)
    );

    // clock 100MHz
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task pulse_dir(input [31:0] v);
    begin
        @(posedge clk);
        reg_dir_di <= v;
        reg_dir_we <= 1'b1;
        @(posedge clk);
        reg_dir_we <= 1'b0;
    end
    endtask

    task pulse_out(input [31:0] v);
    begin
        @(posedge clk);
        reg_out_di <= v;
        reg_out_we <= 1'b1;
        @(posedge clk);
        reg_out_we <= 1'b0;
    end
    endtask

    task pulse_set(input [31:0] v);
    begin
        @(posedge clk);
        reg_set_di <= v;
        reg_set_we <= 1'b1;
        @(posedge clk);
        reg_set_we <= 1'b0;
    end
    endtask

    task pulse_clr(input [31:0] v);
    begin
        @(posedge clk);
        reg_clr_di <= v;
        reg_clr_we <= 1'b1;
        @(posedge clk);
        reg_clr_we <= 1'b0;
    end
    endtask

    task pulse_tog(input [31:0] v);
    begin
        @(posedge clk);
        reg_tog_di <= v;
        reg_tog_we <= 1'b1;
        @(posedge clk);
        reg_tog_we <= 1'b0;
    end
    endtask

    task pulse_ien(input [31:0] v);
    begin
        @(posedge clk);
        reg_ien_di <= v;
        reg_ien_we <= 1'b1;
        @(posedge clk);
        reg_ien_we <= 1'b0;
    end
    endtask

    task pulse_icfg(input [31:0] v);
    begin
        @(posedge clk);
        reg_icfg_di <= v;
        reg_icfg_we <= 1'b1;
        @(posedge clk);
        reg_icfg_we <= 1'b0;
    end
    endtask

    task pulse_istat_clear(input [31:0] v);
    begin
        @(posedge clk);
        reg_istat_di <= v;
        reg_istat_we <= 1'b1;
        @(posedge clk);
        reg_istat_we <= 1'b0;
    end
    endtask

    initial begin
        resetn       = 1'b0;

        reg_dir_we   = 1'b0; reg_dir_di   = 32'd0;
        reg_out_we   = 1'b0; reg_out_di   = 32'd0;
        reg_set_we   = 1'b0; reg_set_di   = 32'd0;
        reg_clr_we   = 1'b0; reg_clr_di   = 32'd0;
        reg_tog_we   = 1'b0; reg_tog_di   = 32'd0;
        reg_ien_we   = 1'b0; reg_ien_di   = 32'd0;
        reg_istat_we = 1'b0; reg_istat_di = 32'd0;
        reg_icfg_we  = 1'b0; reg_icfg_di  = 32'd0;

        gpio_drv     = 8'h00;
        gpio_drv_en  = 8'h00;

        repeat (5) @(posedge clk);
        resetn = 1'b1;
        repeat (2) @(posedge clk);

        $display("After reset: dir=%h out=%h in=%h istat=%h irq=%b",
                 reg_dir_do, reg_out_do, reg_in_do, reg_istat_do, irq);

        // -------------------------------
        // TEST 1: output mode
        // pin[3:0] là output
        // -------------------------------
        pulse_dir(32'h0000_000F);
        pulse_out(32'h0000_0005);   // gpio[0]=1, gpio[2]=1

        @(posedge clk);
        $display("TEST1 dir=%h out=%h gpio=%b", reg_dir_do, reg_out_do, gpio);

        pulse_set(32'h0000_0002);   // set bit1
        @(posedge clk);
        $display("After set  bit1: out=%h gpio=%b", reg_out_do, gpio);

        pulse_clr(32'h0000_0004);   // clear bit2
        @(posedge clk);
        $display("After clr  bit2: out=%h gpio=%b", reg_out_do, gpio);

        pulse_tog(32'h0000_0009);   // toggle bit3,bit0
        @(posedge clk);
        $display("After tog b3,b0: out=%h gpio=%b", reg_out_do, gpio);

        // -------------------------------
        // TEST 2: input mode
        // pin[7:4] là input ngoài
        // -------------------------------
        gpio_drv_en[7:4] = 4'b1111;
        gpio_drv[7:4]    = 4'b1010;

        repeat (3) @(posedge clk); // chờ qua sync 2 tầng
        $display("TEST2 reg_in_do=%h", reg_in_do);

        // -------------------------------
        // TEST 3: interrupt rising edge on gpio[4]
        // icfg[2*4 +: 2] = 2'b00  (rising edge)
        // enable irq cho bit4
        // -------------------------------
        pulse_ien(32'h0000_0010);
        pulse_icfg(32'h0000_0000);  // mặc định rising edge hết

        gpio_drv[4] = 1'b0;
        repeat (3) @(posedge clk);

        gpio_drv[4] = 1'b1;
        repeat (3) @(posedge clk);

        $display("TEST3 istat=%h irq=%b", reg_istat_do, irq);

        // clear interrupt bit4
        pulse_istat_clear(32'h0000_0010);
        @(posedge clk);
        $display("After clear istat=%h irq=%b", reg_istat_do, irq);

        #50;
        $finish;
    end

endmodule

`default_nettype wire