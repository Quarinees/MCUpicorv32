`timescale 1ns/1ps
`default_nettype none

module tb_simpletimer;

    localparam integer NUM_CH = 4;

    reg                  clk;
    reg                  resetn;
    wire [NUM_CH-1:0]    pwm_out;

    reg                  reg_ctrl_we;
    reg  [31:0]          reg_ctrl_di;
    wire [31:0]          reg_ctrl_do;

    reg  [3:0]           reg_psc_we;
    reg  [31:0]          reg_psc_di;
    wire [31:0]          reg_psc_do;

    reg  [1:0]           reg_cnt_sel;
    wire [31:0]          reg_cnt_do;

    reg  [1:0]           reg_top_sel;
    reg                  reg_top_we;
    reg  [31:0]          reg_top_di;
    wire [31:0]          reg_top_do;

    reg  [1:0]           reg_cmp_sel;
    reg                  reg_cmp_we;
    reg  [31:0]          reg_cmp_di;
    wire [31:0]          reg_cmp_do;

    reg                  reg_istat_we;
    reg  [31:0]          reg_istat_di;
    wire [31:0]          reg_istat_do;

    wire                 irq;

    simpletimer #(
        .NUM_CH(NUM_CH)
    ) dut (
        .clk(clk),
        .resetn(resetn),
        .pwm_out(pwm_out),

        .reg_ctrl_we(reg_ctrl_we),
        .reg_ctrl_di(reg_ctrl_di),
        .reg_ctrl_do(reg_ctrl_do),

        .reg_psc_we(reg_psc_we),
        .reg_psc_di(reg_psc_di),
        .reg_psc_do(reg_psc_do),

        .reg_cnt_sel(reg_cnt_sel),
        .reg_cnt_do(reg_cnt_do),

        .reg_top_sel(reg_top_sel),
        .reg_top_we(reg_top_we),
        .reg_top_di(reg_top_di),
        .reg_top_do(reg_top_do),

        .reg_cmp_sel(reg_cmp_sel),
        .reg_cmp_we(reg_cmp_we),
        .reg_cmp_di(reg_cmp_di),
        .reg_cmp_do(reg_cmp_do),

        .reg_istat_we(reg_istat_we),
        .reg_istat_di(reg_istat_di),
        .reg_istat_do(reg_istat_do),

        .irq(irq)
    );

    // clock 100MHz
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task write_psc(input [31:0] v);
    begin
        @(posedge clk);
        reg_psc_di <= v;
        reg_psc_we <= 4'b1111;
        @(posedge clk);
        reg_psc_we <= 4'b0000;
    end
    endtask

    task write_top(input [1:0] ch, input [31:0] v);
    begin
        @(posedge clk);
        reg_top_sel <= ch;
        reg_top_di  <= v;
        reg_top_we  <= 1'b1;
        @(posedge clk);
        reg_top_we  <= 1'b0;
    end
    endtask

    task write_cmp(input [1:0] ch, input [31:0] v);
    begin
        @(posedge clk);
        reg_cmp_sel <= ch;
        reg_cmp_di  <= v;
        reg_cmp_we  <= 1'b1;
        @(posedge clk);
        reg_cmp_we  <= 1'b0;
    end
    endtask

    task write_ctrl(input [31:0] v);
    begin
        @(posedge clk);
        reg_ctrl_di <= v;
        reg_ctrl_we <= 1'b1;
        @(posedge clk);
        reg_ctrl_we <= 1'b0;
    end
    endtask

    task clear_istat(input [31:0] v);
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
        reg_ctrl_we  = 1'b0;
        reg_ctrl_di  = 32'd0;
        reg_psc_we   = 4'd0;
        reg_psc_di   = 32'd0;
        reg_cnt_sel  = 2'd0;
        reg_top_sel  = 2'd0;
        reg_top_we   = 1'b0;
        reg_top_di   = 32'd0;
        reg_cmp_sel  = 2'd0;
        reg_cmp_we   = 1'b0;
        reg_cmp_di   = 32'd0;
        reg_istat_we = 1'b0;
        reg_istat_di = 32'd0;

        repeat (5) @(posedge clk);
        resetn = 1'b1;
        repeat (2) @(posedge clk);

        $display("After reset:");
        $display("CTRL  = %h", reg_ctrl_do);
        $display("PSC   = %h", reg_psc_do);
        $display("ISTAT = %h IRQ=%b", reg_istat_do, irq);

        // prescaler = 1 => tick mỗi 2 clock
        write_psc(32'd1);

        // channel 0: TOP = 5, CMP = 2
        write_top(2'd0, 32'd5);
        write_cmp(2'd0, 32'd2);

        // ctrl layout:
        // [3:0]   en
        // [7:4]   mode
        // [11:8]  ien
        // [15:12] pwmen
        // [19:16] cmpen
        //
        // enable ch0, ien ch0, pwmen ch0
        write_ctrl(32'h0000_1101);

        $display("\nStart timer ch0...");
        repeat (20) begin
            @(posedge clk);
            reg_cnt_sel <= 2'd0;
            $display("t=%0t cnt0=%0d pwm0=%b istat=%b irq=%b",
                     $time, reg_cnt_do, pwm_out[0], reg_istat_do[0], irq);
        end

        $display("\nClear interrupt bit0");
        clear_istat(32'h0000_0001);
        @(posedge clk);
        $display("After clear: ISTAT=%h IRQ=%b", reg_istat_do, irq);

        // test one-shot mode channel 1
        write_top(2'd1, 32'd3);
        write_cmp(2'd1, 32'd1);

        // en1=1, mode1=1, ien1=1, pwmen1=1
        // bit1 ở các field tương ứng
        write_ctrl(32'h0000_2202);

        $display("\nStart one-shot timer ch1...");
        repeat (16) begin
            @(posedge clk);
            reg_cnt_sel <= 2'd1;
            $display("t=%0t cnt1=%0d pwm1=%b ctrl=%h istat=%h irq=%b",
                     $time, reg_cnt_do, pwm_out[1], reg_ctrl_do, reg_istat_do, irq);
        end

        #50;
        $finish;
    end

endmodule

`default_nettype wire