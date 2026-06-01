`timescale 1ns/1ps

module tb_i2c_master;

    reg clk = 0;
    always #10 clk = ~clk; // 50MHz

    reg reset;
    reg start;

    reg [6:0] addr = 7'h23;

    // FIX: cùng kích thước với DATA_MAX
    reg [7:0] data [0:15];
    reg [3:0] len;

    wire scl;
    wire sda;

    // Pull-up
    assign (weak1, weak0) sda = 1'b1;

    // Slave giả lập ACK
    reg sda_slave;
    assign sda = sda_slave ? 1'b0 : 1'bz;

    i2c_master #(
        .DATA_MAX(16),
        .CLK_DIV(50)
    ) uut (
        .clk(clk),
        .reset(reset),
        .start(start),
        .addr(addr),
        .data(data),
        .data_len(len),
        .busy(),
        .done(),
        .ack_error(),
        .sda(sda),
        .scl(scl)
    );

    // ACK task
    task ack;
    begin
        @(posedge scl);
        #5 sda_slave = 1;
        @(negedge scl);
        #5 sda_slave = 0;
    end
    endtask

    initial begin
        reset = 0;
        start = 0;
        sda_slave = 0;

        // DATA
        data[0] = 8'h01;
        data[1] = 8'h10;
        data[2] = 8'h20;
        data[3] = 8'h30;

        len = 4;

        #100 reset = 1;

        #100 start = 1;
        #20  start = 0;

        // ACK cho từng byte
        repeat(8) @(posedge scl); ack(); // addr
        repeat(8) @(posedge scl); ack(); // byte0
        repeat(8) @(posedge scl); ack(); // byte1
        repeat(8) @(posedge scl); ack(); // byte2
        repeat(8) @(posedge scl); ack(); // byte3

        #2000 $finish;
    end

endmodule