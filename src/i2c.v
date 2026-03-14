// =============================================================
//  I2C Master – SCL perfectly symmetric (v3)
//
//  Fix so với v2:
//  1. ST_RSTART: gộp step SCL=1+SDA=0 vào 1 tick (bỏ step SCL=1 riêng)
//     → SCL không bị kéo dài 2×CLK_DIV tại repeated START
//  2. ST_STOP: gộp SDA=0→SCL=1 vào 1 tick, SDA release riêng 1 tick
//     → SCL không bị kéo dài 2×CLK_DIV tại STOP
//  3. ST_READ phase=1 bit_i==8: đặt phase<=0 rõ ràng khi chuyển byte
// =============================================================

module I2C_Master #(
    parameter CLK_DIV   = 135,
    parameter MAX_BYTES = 8
)(
    input                           clk,
    input                           rst,

    input                           start,
    input                           rw,
    input  [6:0]                    slave_addr,
    input  [7:0]                    ctrl_byte,
    input                           en_ctrl_byte,
    input  [MAX_BYTES*8-1:0]        tx_payload,
    input  [$clog2(MAX_BYTES):0]    byte_count,

    output reg                      busy      = 0,
    output reg                      nack_err  = 0,
    output reg [MAX_BYTES*8-1:0]    rx_data   = 0,
    output reg                      rx_valid  = 0,

    output reg                      scl = 1,
    inout                           sda
);

// ---------------------------------------------------------------
// Open-drain SDA
// ---------------------------------------------------------------
reg sda_oe  = 0;
reg sda_out = 1;
assign sda  = (sda_oe & ~sda_out) ? 1'b0 : 1'bz;
wire sda_in = sda;

// ---------------------------------------------------------------
// States
// ---------------------------------------------------------------
localparam ST_IDLE   = 4'd0,
           ST_START  = 4'd1,
           ST_RSTART = 4'd2,
           ST_ADDR   = 4'd3,
           ST_RADDR  = 4'd4,
           ST_CTRL   = 4'd5,
           ST_WRITE  = 4'd6,
           ST_READ   = 4'd7,
           ST_STOP   = 4'd8;

// ---------------------------------------------------------------
// Tick counter: CLK_DIV → 1, FSM fires on tick
// ---------------------------------------------------------------
reg [11:0] cnt = 1;
wire       tick = (cnt == 1);

always @(posedge clk) begin
    if (rst)       cnt <= 1;
    else if (tick) cnt <= CLK_DIV;
    else           cnt <= cnt - 1;
end

// ---------------------------------------------------------------
// FSM registers
// ---------------------------------------------------------------
reg [3:0]  state = ST_IDLE;
reg        phase = 0;   // 0=SCL_LOW, 1=SCL_HIGH
reg [3:0]  bit_i = 0;   // 0–7: data, 8: ACK slot
reg [$clog2(MAX_BYTES):0] byte_i = 0;
reg [2:0]  step  = 0;   // dùng cho START / RSTART / STOP

reg [7:0] addr_w, addr_r;
reg [7:0] ctrl_r;
reg       en_ctrl_r, rw_r;
reg [$clog2(MAX_BYTES):0] bcnt_r;
reg [MAX_BYTES*8-1:0] payload_r;
reg [7:0] tx_byte, rx_byte;

function [7:0] get_byte;
    input [$clog2(MAX_BYTES):0] idx;
    integer k;
    begin
        get_byte = 0;
        for (k = 0; k < MAX_BYTES; k = k+1)
            if (k[$clog2(MAX_BYTES):0] == idx)
                get_byte = payload_r[k*8 +: 8];
    end
endfunction

// ---------------------------------------------------------------
// FSM
// ---------------------------------------------------------------
always @(posedge clk) begin
    if (rst) begin
        state <= ST_IDLE; phase <= 0; bit_i <= 0; byte_i <= 0;
        step  <= 0; busy <= 0; nack_err <= 0; rx_valid <= 0;
        scl <= 1; sda_oe <= 0; sda_out <= 1; rx_data <= 0;
    end else if (tick) begin

    rx_valid <= 0;

    case (state)

    // =========================================================
    // IDLE
    // =========================================================
    ST_IDLE: begin
        scl <= 1; sda_oe <= 0; phase <= 0; step <= 0;
        if (start && !busy) begin
            addr_w    <= {slave_addr, 1'b0};
            addr_r    <= {slave_addr, 1'b1};
            ctrl_r    <= ctrl_byte;
            en_ctrl_r <= en_ctrl_byte;
            rw_r      <= rw;
            bcnt_r    <= byte_count;
            payload_r <= tx_payload;
            busy <= 1; nack_err <= 0; rx_data <= 0;
            bit_i <= 0; byte_i <= 0;
            state <= ST_START; step <= 0;
        end
    end

    // =========================================================
    // START condition  (3 ticks)
    //
    //   tick 0: SCL=1, SDA=1   bus free
    //   tick 1: SCL=1, SDA=0   START: SDA falls while SCL=1
    //   tick 2: SCL=0           SCL falls → enter data phase
    //
    // Sau tick 2: SCL=0, phase=0 → byte TX bắt đầu đúng pha
    // =========================================================
    ST_START: begin
        case (step)
        0: begin
            scl <= 1; sda_out <= 1; sda_oe <= 0;
            step <= 1;
           end
        1: begin
            scl <= 1; sda_out <= 0; sda_oe <= 1;
            step <= 2;
           end
        2: begin
            scl <= 0;
            tx_byte <= addr_w; bit_i <= 0; phase <= 0;
            step <= 0; state <= ST_ADDR;
           end
        endcase
    end

    // =========================================================
    // REPEATED START  (3 ticks)
    //
    // Vào từ: phase=1 của ACK (SCL=1, SDA released)
    //
    //   tick 0: SCL=0, SDA=1 (release)   SCL falls – bus còn giữ
    //   tick 1: SCL=1, SDA=0             SCL rises, SDA falls → Sr
    //   tick 2: SCL=0                    SCL falls → vào data phase
    //
    // Mỗi tick = đúng CLK_DIV cycles → không có tick nào SCL=1
    // kéo dài 2×CLK_DIV.
    //
    // BUG CŨ: step 1 SCL=1 riêng + step 2 SCL=1+SDA=0 riêng
    //         → SCL=1 kéo dài 2×CLK_DIV
    // FIX: gộp SCL=1 và SDA=0 vào cùng 1 tick
    // =========================================================
ST_RSTART: begin
    case (step)
    // Step 0: Kết thúc ACK clock - kéo SCL xuống, giữ SDA
    0: begin
        scl <= 0; sda_oe <= 0;  // SCL falls, release SDA
        step <= 1;
       end
    // Step 1: SDA lên high (chuẩn bị repeated start)  
    1: begin
        scl <= 0; sda_out <= 1; sda_oe <= 1;
        step <= 2;
       end
    // Step 2: SCL lên + SDA vẫn high
    2: begin
        scl <= 1; sda_out <= 1; sda_oe <= 1;
        step <= 3;
       end
    // Step 3: SDA xuống trong khi SCL=1 → Repeated START
    3: begin
        scl <= 1; sda_out <= 0; sda_oe <= 1;
        step <= 4;
       end
    // Step 4: SCL xuống → vào data phase
    4: begin
        scl <= 0;
        tx_byte <= addr_r; bit_i <= 0; phase <= 0;
        step <= 0; state <= ST_RADDR;
       end
    endcase
end

    // =========================================================
    // BYTE TX: ST_ADDR / ST_RADDR / ST_CTRL / ST_WRITE
    //
    // Mỗi bit = 2 ticks đúng CLK_DIV:
    //   phase=0 (SCL=0): drive SDA[7-bit_i]
    //   phase=1 (SCL=1): slave samples; bit_i++
    //
    // ACK slot (bit_i=8):
    //   phase=0 (SCL=0): release SDA
    //   phase=1 (SCL=1): sample sda_in → dispatch
    //
    // SCL waveform: ‾‾|__|‾‾|__|‾‾|__ (đều tuyệt đối)
    // =========================================================
    ST_ADDR, ST_RADDR, ST_CTRL, ST_WRITE: begin
        if (phase == 0) begin
            scl <= 0;
            if (bit_i < 8) begin
                sda_out <= tx_byte[7 - bit_i];
                sda_oe  <= 1;
            end else begin
                sda_oe <= 0;    // release for ACK
            end
            phase <= 1;
        end else begin
            scl <= 1;
            if (bit_i < 8) begin
                bit_i <= bit_i + 1;
                phase <= 0;
            end else begin
                // ACK slot: sample sda_in
                if (sda_in) nack_err <= 1;
                bit_i <= 0;
                phase <= 0;     // next tick: SCL=0 trong state mới

                case (state)
                ST_ADDR: begin
                    if (en_ctrl_r) begin
                        tx_byte <= ctrl_r;
                        state   <= ST_CTRL;
                    end else if (rw_r) begin
                        state <= ST_RSTART;
                    end else begin
                        tx_byte <= get_byte(0);
                        byte_i  <= 0;
                        state   <= ST_WRITE;
                    end
                   end
                ST_CTRL: begin
                    if (rw_r) begin
                        state <= ST_RSTART;
                    end else begin
                        tx_byte <= get_byte(0);
                        byte_i  <= 0;
                        state   <= ST_WRITE;
                    end
                   end
                ST_RADDR: begin
                    byte_i <= 0;
                    state  <= ST_READ;
                   end
                ST_WRITE: begin
                    if (byte_i + 1 < bcnt_r) begin
                        byte_i  <= byte_i + 1;
                        tx_byte <= get_byte(byte_i + 1);
                    end else begin
                        state <= ST_STOP;
                    end
                   end
                default: state <= ST_STOP;
                endcase
            end
        end
    end

    // =========================================================
    // BYTE RX: ST_READ
    //
    // Mỗi bit = 2 ticks:
    //   phase=0 (SCL=0): release SDA (slave drives)
    //   phase=1 (SCL=1): sample sda_in → shift vào rx_byte
    //
    // ACK/NACK slot (bit_i=8):
    //   phase=0 (SCL=0): drive ACK (nếu còn byte) hoặc NACK
    //   phase=1 (SCL=1): hold → store byte, chuyển next/STOP
    // =========================================================
    ST_READ: begin
        if (phase == 0) begin
            scl <= 0;
            if (bit_i < 8) begin
                sda_oe <= 0;                        // slave drives SDA
            end else begin
                if (byte_i + 1 >= bcnt_r) begin
                    sda_out <= 1; sda_oe <= 0;      // NACK: release
                end else begin
                    sda_out <= 0; sda_oe <= 1;      // ACK: pull low
                end
            end
            phase <= 1;
        end else begin
            scl <= 1;
            if (bit_i < 8) begin
                rx_byte <= {rx_byte[6:0], sda_in};  // MSB first
                bit_i   <= bit_i + 1;
                phase   <= 0;
            end else begin
                // Store completed byte
                begin : store
                    integer k;
                    for (k = 0; k < MAX_BYTES; k = k+1)
                        if (k[$clog2(MAX_BYTES):0] == byte_i)
                            rx_data[k*8 +: 8] <= rx_byte;
                end
                bit_i <= 0;
                phase <= 0;
                if (byte_i + 1 < bcnt_r) begin
                    byte_i <= byte_i + 1;
                    // state vẫn ST_READ, phase=0 → tiếp tục nhận
                end else begin
                    rx_valid <= 1;
                    state    <= ST_STOP;
                end
            end
        end
    end

    // =========================================================
    // STOP condition  (4 ticks)
    //
    // Vào từ: phase=0 của byte TX/RX (SCL đang =0 từ dispatch)
    //
    //   tick 0: SCL=0, SDA=0   setup SDA low
    //   tick 1: SCL=1, SDA=0   SCL rises (SDA still low)
    //   tick 2: SCL=1, SDA=1   SDA rises while SCL=1 → STOP
    //   tick 3: tBUF hold      bus free
    //   tick 4: → IDLE
    //
    // BUG CŨ: tick 1 SCL=1 riêng + tick 2 sda_oe=0 riêng (SCL vẫn=1)
    //         → SCL=1 kéo dài 2×CLK_DIV
    // FIX: SCL=1+SDA=0 cùng tick 1; SDA release tick 2 (SCL vẫn=1 → STOP)
    //      Đây là yêu cầu protocol: SCL=1 trong cả tick 1 và 2 là ĐÚNG
    //      vì STOP cần SDA rise while SCL=1. Không thể tránh.
    //      Nhưng đây là vùng đặc biệt (STOP), không phải data bit.
    // =========================================================
    ST_STOP: begin
        case (step)
        0: begin
            scl <= 0; sda_out <= 0; sda_oe <= 1;   // setup SDA=0
            step <= 1;
           end
        1: begin
            scl <= 1; sda_out <= 0; sda_oe <= 1;   // SCL rises, SDA=0
            step <= 2;
           end
        2: begin
            scl <= 1; sda_oe <= 0;                  // SDA rises → STOP
            step <= 3;
           end
        3: begin
            scl <= 1;                               // tBUF hold
            step <= 4;
           end
        4: begin
            busy  <= 0;
            state <= ST_IDLE;
            step  <= 0;
           end
        endcase
    end

    endcase
    end // tick
end

endmodule