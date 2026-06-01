module i2c_master #(
    parameter DATA_MAX = 16,
    parameter CLK_DIV  = 250
)(
    input wire clk,
    input wire reset,

    input wire start,
    input wire [6:0] addr,
    input wire [7:0] data [0:DATA_MAX-1],
    input wire [3:0] data_len,

    output reg busy,
    output reg done,
    output reg ack_error,

    inout wire sda,
    output reg scl
);

    // clock divider
    reg [15:0] clk_cnt;
    reg tick;

    always @(posedge clk) begin
        if (clk_cnt == CLK_DIV) begin
            clk_cnt <= 0;
            tick <= 1;
        end else begin
            clk_cnt <= clk_cnt + 1;
            tick <= 0;
        end
    end

    // SDA
    reg sda_out, sda_oe;
    assign sda = sda_oe ? sda_out : 1'bz;
    wire sda_in = sda;

    // FSM
    reg [4:0] state;
    reg phase; // 🔥 QUAN TRỌNG: 0=low, 1=high
    reg [3:0] bit_cnt;
    reg [3:0] byte_cnt;
    reg [7:0] shift_reg;

    localparam IDLE  = 0;
    localparam START = 1;
    localparam ADDR  = 2;
    localparam ACK1  = 3;
    localparam DATA  = 4;
    localparam ACK2  = 5;
    localparam STOP  = 6;

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            state <= IDLE;
            scl <= 1;
            sda_out <= 1;
            sda_oe <= 1;
            busy <= 0;
            done <= 0;
            ack_error <= 0;
            phase <= 0;
        end 
        else if (tick) begin

            case (state)

            IDLE: begin
                done <= 0;
                scl <= 1;
                sda_out <= 1;
                if (start) begin
                    busy <= 1;
                    sda_out <= 0; // START
                    state <= START;
                end
            end

            START: begin
                scl <= 0;
                shift_reg <= {addr,1'b0};
                bit_cnt <= 7;
                phase <= 0;
                state <= ADDR;
            end

            ADDR: begin
                if (phase == 0) begin
                    scl <= 0;
                    sda_out <= shift_reg[bit_cnt];
                    phase <= 1;
                end else begin
                    scl <= 1;
                    phase <= 0;

                    if (bit_cnt == 0)
                        state <= ACK1;
                    else
                        bit_cnt <= bit_cnt - 1;
                end
            end

            ACK1: begin
                if (phase == 0) begin
                    scl <= 0;
                    sda_oe <= 0;
                    phase <= 1;
                end else begin
                    scl <= 1;
                    ack_error <= sda_in;
                    sda_oe <= 1;
                    shift_reg <= data[0];
                    bit_cnt <= 7;
                    byte_cnt <= 0;
                    phase <= 0;
                    state <= DATA;
                end
            end

            DATA: begin
                if (phase == 0) begin
                    scl <= 0;
                    sda_out <= shift_reg[bit_cnt];
                    phase <= 1;
                end else begin
                    scl <= 1;
                    phase <= 0;

                    if (bit_cnt == 0)
                        state <= ACK2;
                    else
                        bit_cnt <= bit_cnt - 1;
                end
            end

            ACK2: begin
                if (phase == 0) begin
                    scl <= 0;
                    sda_oe <= 0;
                    phase <= 1;
                end else begin
                    scl <= 1;
                    if (sda_in) ack_error <= 1;
                    sda_oe <= 1;

                    if (byte_cnt == data_len-1)
                        state <= STOP;
                    else begin
                        byte_cnt <= byte_cnt + 1;
                        shift_reg <= data[byte_cnt+1];
                        bit_cnt <= 7;
                        state <= DATA;
                    end
                    phase <= 0;
                end
            end

            STOP: begin
                scl <= 1;
                sda_out <= 0;
                sda_out <= 1;
                busy <= 0;
                done <= 1;
                state <= IDLE;
            end

            endcase
        end
    end

endmodule