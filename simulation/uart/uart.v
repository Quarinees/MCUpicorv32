// simpleuart.v
module simpleuart #(
    parameter integer DEFAULT_DIV = 1
) (
    input  wire        clk,
    input  wire        resetn,

    output wire        ser_tx,
    input  wire        ser_rx,

    input  wire [3:0]  reg_div_we,
    input  wire [31:0] reg_div_di,
    output wire [31:0] reg_div_do,

    input  wire        reg_dat_we,
    input  wire        reg_dat_re,
    input  wire [31:0] reg_dat_di,
    output wire [31:0] reg_dat_do,
    output wire        reg_dat_wait
);

    // =========================================================
    // BAUD DIVIDER REGISTER
    // =========================================================
    reg [31:0] cfg_divider;

    assign reg_div_do = cfg_divider;

    always @(posedge clk) begin
        if (!resetn) begin
            cfg_divider <= DEFAULT_DIV;
        end else begin
            if (reg_div_we[0]) cfg_divider[ 7: 0] <= reg_div_di[ 7: 0];
            if (reg_div_we[1]) cfg_divider[15: 8] <= reg_div_di[15: 8];
            if (reg_div_we[2]) cfg_divider[23:16] <= reg_div_di[23:16];
            if (reg_div_we[3]) cfg_divider[31:24] <= reg_div_di[31:24];
        end
    end

    // =========================================================
    // TX — counter riêng: tx_div_cnt
    // =========================================================
    reg [31:0] tx_div_cnt;
    reg [9:0]  tx_shift;
    reg [3:0]  tx_bitcnt;
    reg        tx_busy;

    wire tx_tick = (tx_div_cnt == 0);

    assign ser_tx       = tx_busy ? tx_shift[0] : 1'b1;
    assign reg_dat_wait = tx_busy;

    always @(posedge clk) begin
        if (!resetn) begin
            tx_div_cnt <= DEFAULT_DIV;
            tx_shift   <= 10'h3FF;
            tx_bitcnt  <= 0;
            tx_busy    <= 0;
        end else begin
            if (reg_dat_we && !tx_busy) begin
                // Reset counter khi load byte mới
                // → baud_tick đầu tiên xảy ra đúng 1 period sau
                tx_div_cnt <= cfg_divider;
                tx_shift   <= {1'b1, reg_dat_di[7:0], 1'b0};
                tx_bitcnt  <= 10;
                tx_busy    <= 1;
            end else if (tx_tick && tx_busy) begin
                tx_div_cnt <= cfg_divider;
                tx_shift   <= {1'b1, tx_shift[9:1]};
                tx_bitcnt  <= tx_bitcnt - 1;
                if (tx_bitcnt == 1)
                    tx_busy <= 0;
            end else if (tx_busy) begin
                tx_div_cnt <= tx_div_cnt - 1;
            end else begin
                tx_div_cnt <= DEFAULT_DIV;
            end
        end
    end

    // =========================================================
    // RX — counter riêng: rx_div_cnt
    // Sample giữa bit để tránh edge uncertainty
    // =========================================================
    reg [31:0] rx_div_cnt;
    reg [3:0]  rx_state;
    reg [7:0]  rx_shift;
    reg [7:0]  rx_data;
    reg        rx_valid;

    wire rx_tick = (rx_div_cnt == 0);

    assign reg_dat_do = rx_valid ? {24'h0, rx_data} : 32'hFFFF_FFFF;

    always @(posedge clk) begin
        if (!resetn) begin
            rx_div_cnt <= DEFAULT_DIV;
            rx_state   <= 0;
            rx_valid   <= 0;
            rx_shift   <= 0;
            rx_data    <= 0;
        end else begin
            if (reg_dat_re)
                rx_valid <= 0;

            case (rx_state)
                0: begin
                    if (!ser_rx) begin
                        // Detect start bit: set counter = divider/2
                        // để sample ở giữa start bit
                        rx_div_cnt <= cfg_divider >> 1;
                        rx_state   <= 1;
                    end
                end

                1: begin
                    if (rx_tick) begin
                        rx_div_cnt <= cfg_divider;
                        if (!ser_rx)
                            rx_state <= 2;
                        else
                            rx_state <= 0; // glitch
                    end else begin
                        rx_div_cnt <= rx_div_cnt - 1;
                    end
                end

                2,3,4,5,6,7,8,9: begin
                    if (rx_tick) begin
                        rx_div_cnt <= cfg_divider;
                        rx_shift   <= {ser_rx, rx_shift[7:1]};
                        rx_state   <= rx_state + 1;
                    end else begin
                        rx_div_cnt <= rx_div_cnt - 1;
                    end
                end

                10: begin
                    if (rx_tick) begin
                        rx_div_cnt <= cfg_divider;
                        if (ser_rx) begin
                            rx_data  <= rx_shift;
                            rx_valid <= 1;
                        end
                        rx_state <= 0;
                    end else begin
                        rx_div_cnt <= rx_div_cnt - 1;
                    end
                end

                default: begin
                    rx_state   <= 0;
                    rx_div_cnt <= DEFAULT_DIV;
                end
            endcase
        end
    end

endmodule