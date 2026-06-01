`default_nettype none

module simplespi #(
    parameter integer DEFAULT_DIV  = 49,   // 50 MHz → ~500 kHz init clock
    parameter integer NUM_CS       = 1,
    parameter integer CS_HOLD_BITS = 8     // half-period giữ CS sau byte cuối
) (
    input  wire clk,
    input  wire resetn,

    output wire               spi_sck,
    output wire               spi_mosi,
    input  wire               spi_miso,
    output wire [NUM_CS-1:0]  spi_cs_n,

    // register interface
    input  wire [3:0]  reg_div_we,
    input  wire [31:0] reg_div_di,
    output wire [31:0] reg_div_do,

    input  wire        reg_cfg_we,
    input  wire [31:0] reg_cfg_di,
    output wire [31:0] reg_cfg_do,

    input  wire        reg_cs_we,
    input  wire [31:0] reg_cs_di,
    output wire [31:0] reg_cs_do,

    output wire [31:0] reg_stat_do,

    input  wire        reg_dat_we,
    input  wire        reg_dat_re,
    input  wire [31:0] reg_dat_di,
    output wire [31:0] reg_dat_do,
    output wire        reg_dat_wait
);

    // ===================== CONFIG =====================
    reg [31:0]       cfg_divider;
    reg [1:0]        cfg_mode;
    reg              cfg_lsb_first;
    reg              cfg_cs_auto;
    reg [NUM_CS-1:0] cs_reg;

    wire cpol = cfg_mode[1];
    wire cpha = cfg_mode[0];

    assign reg_div_do  = cfg_divider;
    assign reg_cfg_do  = {28'b0, cfg_cs_auto, cfg_lsb_first, cfg_mode};
    assign reg_cs_do   = {{(32-NUM_CS){1'b1}}, cs_reg};

    always @(posedge clk) begin
        if (!resetn) begin
            cfg_divider   <= DEFAULT_DIV;
            cfg_mode      <= 2'b00;   // Mode 0
            cfg_lsb_first <= 1'b0;
            cfg_cs_auto   <= 1'b1;
            cs_reg        <= {NUM_CS{1'b1}};
        end else begin
            if (reg_div_we[0]) cfg_divider[7:0]   <= reg_div_di[7:0];
            if (reg_div_we[1]) cfg_divider[15:8]  <= reg_div_di[15:8];
            if (reg_div_we[2]) cfg_divider[23:16] <= reg_div_di[23:16];
            if (reg_div_we[3]) cfg_divider[31:24] <= reg_div_di[31:24];

            if (reg_cfg_we) begin
                cfg_mode      <= reg_cfg_di[1:0];
                cfg_lsb_first <= reg_cfg_di[2];
                cfg_cs_auto   <= reg_cfg_di[3];
            end

            if (reg_cs_we)
                cs_reg <= reg_cs_di[NUM_CS-1:0];
        end
    end

    // ===================== DIVIDER =====================
    reg [31:0] div_cnt;
    wire tick = (div_cnt == 0);
    reg div_reload;

    always @(posedge clk) begin
        if (!resetn) begin
            div_cnt <= DEFAULT_DIV;
        end else if (div_reload) begin
            div_cnt <= cfg_divider;
        end else if (tick) begin
            div_cnt <= cfg_divider;
        end else begin
            div_cnt <= div_cnt - 1;
        end
    end

    // ===================== SPI FSM =====================
    // state encoding
    localparam ST_IDLE    = 2'd0;
    localparam ST_SHIFT   = 2'd1;
    localparam ST_HOLD    = 2'd2;   // CS hold sau byte cuối

    reg [1:0]  state;
    reg        sck_r;
    reg [7:0]  shift_tx;
    reg [7:0]  shift_rx;
    reg [2:0]  bit_cnt;
    reg        phase;
    reg        cs_end_r;
    reg [7:0]  recv_data;
    reg        recv_valid;
    reg        auto_cs_n;
    reg [3:0]  hold_cnt;   // CS hold counter (đơn vị: tick)

    wire busy = (state != ST_IDLE);

    assign spi_sck    = busy ? (sck_r ^ cpol) : cpol;
    assign spi_mosi   = cfg_lsb_first ? shift_tx[0] : shift_tx[7];
    assign spi_cs_n   = cfg_cs_auto ? {NUM_CS{auto_cs_n}} : cs_reg;

    assign reg_dat_wait = busy;
    assign reg_dat_do   = recv_valid ? {1'b1, 23'b0, recv_data} : 32'hFFFF_FFFF;
    assign reg_stat_do  = {30'b0, recv_valid, busy};

    always @(posedge clk) begin
        if (!resetn) begin
            state      <= ST_IDLE;
            sck_r      <= 0;
            shift_tx   <= 8'hFF;
            shift_rx   <= 0;
            bit_cnt    <= 7;
            phase      <= 0;
            cs_end_r   <= 0;
            recv_data  <= 0;
            recv_valid <= 0;
            auto_cs_n  <= 1;
            div_reload <= 0;
            hold_cnt   <= 0;
        end else begin

            div_reload <= 0;

            if (reg_dat_re)
                recv_valid <= 0;

            case (state)

            // ----- IDLE: chờ ghi DAT -----
            ST_IDLE: begin
                if (reg_dat_we) begin
                    shift_tx   <= reg_dat_di[7:0];
                    cs_end_r   <= reg_dat_di[8];
                    bit_cnt    <= 7;
                    phase      <= 0;
                    recv_valid <= 0;
                    auto_cs_n  <= 0;     // CS assert (active-low)
                    sck_r      <= 0;
                    div_reload <= 1;
                    state      <= ST_SHIFT;
                end
            end

            // ----- SHIFT: truyền 8 bit -----
            ST_SHIFT: begin
                if (tick) begin
                    phase <= ~phase;

                    if (!cpha) begin
                        // Mode 0 / Mode 2 (CPHA=0): sample on rising, shift on falling
                        if (!phase) begin
                            // rising edge
                            sck_r <= 1;
                        end else begin
                            // falling edge: capture MISO, shift TX
                            sck_r <= 0;
                            if (cfg_lsb_first)
                                shift_rx <= {spi_miso, shift_rx[7:1]};
                            else
                                shift_rx <= {shift_rx[6:0], spi_miso};

                            if (bit_cnt == 0) begin
                                // byte done
                                recv_data  <= cfg_lsb_first ?
                                              {spi_miso, shift_rx[7:1]} :
                                              {shift_rx[6:0], spi_miso};
                                recv_valid <= 1;

                                if (cs_end_r) begin
                                    // cần deassert CS — vào hold state
                                    hold_cnt  <= CS_HOLD_BITS[3:0];
                                    state     <= ST_HOLD;
                                end else begin
                                    state <= ST_IDLE;
                                end
                            end else begin
                                if (cfg_lsb_first)
                                    shift_tx <= {1'b1, shift_tx[7:1]};
                                else
                                    shift_tx <= {shift_tx[6:0], 1'b1};
                                bit_cnt <= bit_cnt - 1;
                            end
                        end

                    end else begin
                        // Mode 1 / Mode 3 (CPHA=1): shift on rising, sample on falling
                        if (!phase) begin
                            sck_r <= 1;
                            if (cfg_lsb_first)
                                shift_tx <= {1'b1, shift_tx[7:1]};
                            else
                                shift_tx <= {shift_tx[6:0], 1'b1};
                        end else begin
                            sck_r <= 0;
                            if (cfg_lsb_first)
                                shift_rx <= {spi_miso, shift_rx[7:1]};
                            else
                                shift_rx <= {shift_rx[6:0], spi_miso};

                            if (bit_cnt == 0) begin
                                recv_data  <= cfg_lsb_first ?
                                              {spi_miso, shift_rx[7:1]} :
                                              {shift_rx[6:0], spi_miso};
                                recv_valid <= 1;

                                if (cs_end_r) begin
                                    hold_cnt  <= CS_HOLD_BITS[3:0];
                                    state     <= ST_HOLD;
                                end else begin
                                    state <= ST_IDLE;
                                end
                            end else begin
                                bit_cnt <= bit_cnt - 1;
                            end
                        end
                    end
                end
            end

            // ----- HOLD: giữ CS thấp thêm vài tick -----
            ST_HOLD: begin
                if (tick) begin
                    if (hold_cnt == 0) begin
                        auto_cs_n <= 1;   // deassert CS
                        state     <= ST_IDLE;
                    end else begin
                        hold_cnt <= hold_cnt - 1;
                    end
                end
            end

            endcase
        end
    end

endmodule

`default_nettype wire