
`default_nettype none

module simpletimer #(
    parameter integer NUM_CH = 4
) (
    input  wire                  clk,
    input  wire                  resetn,

    output wire [NUM_CH-1:0]     pwm_out,

    // Control register (one word covers all channels)
    input  wire                  reg_ctrl_we,
    input  wire [31:0]           reg_ctrl_di,
    output wire [31:0]           reg_ctrl_do,

    // Prescaler
    input  wire [3:0]            reg_psc_we,
    input  wire [31:0]           reg_psc_di,
    output wire [31:0]           reg_psc_do,

    // Per-channel counter read (channel selected by reg_cnt_sel)
    input  wire [1:0]            reg_cnt_sel,
    output wire [31:0]           reg_cnt_do,

    // Per-channel TOP value
    input  wire [1:0]            reg_top_sel,
    input  wire                  reg_top_we,
    input  wire [31:0]           reg_top_di,
    output wire [31:0]           reg_top_do,

    // Per-channel CMP value
    input  wire [1:0]            reg_cmp_sel,
    input  wire                  reg_cmp_we,
    input  wire [31:0]           reg_cmp_di,
    output wire [31:0]           reg_cmp_do,

    // Interrupt status (W1C)
    input  wire                  reg_istat_we,
    input  wire [31:0]           reg_istat_di,
    output wire [31:0]           reg_istat_do,

    output wire                  irq
);

    // ------------------------------------------------------------------ //
    //  Control bits
    // ------------------------------------------------------------------ //
    reg [NUM_CH-1:0] ctrl_en;
    reg [NUM_CH-1:0] ctrl_mode;     // 1 = one-shot
    reg [NUM_CH-1:0] ctrl_ien;
    reg [NUM_CH-1:0] ctrl_pwmen;
    reg [NUM_CH-1:0] ctrl_cmpen;

    reg [NUM_CH-1:0] ctrl_en_next;
    reg [NUM_CH-1:0] istat_next;

    assign reg_ctrl_do = {
        12'b0,
        ctrl_cmpen,
        ctrl_pwmen,
        ctrl_ien,
        ctrl_mode,
        ctrl_en
    };

    // ------------------------------------------------------------------ //
    //  Prescaler
    // ------------------------------------------------------------------ //
    reg  [31:0] cfg_psc;
    reg  [31:0] psc_cnt;
    wire        psc_tick;

    assign psc_tick   = (psc_cnt >= cfg_psc);
    assign reg_psc_do = cfg_psc;

    always @(posedge clk) begin
        if (!resetn)
            cfg_psc <= 32'b0;
        else begin
            if (reg_psc_we[0]) cfg_psc[ 7: 0] <= reg_psc_di[ 7: 0];
            if (reg_psc_we[1]) cfg_psc[15: 8] <= reg_psc_di[15: 8];
            if (reg_psc_we[2]) cfg_psc[23:16] <= reg_psc_di[23:16];
            if (reg_psc_we[3]) cfg_psc[31:24] <= reg_psc_di[31:24];
        end
    end

    always @(posedge clk) begin
        if (!resetn)
            psc_cnt <= 32'b0;
        else if (psc_tick)
            psc_cnt <= 32'b0;
        else
            psc_cnt <= psc_cnt + 32'd1;
    end

    // ------------------------------------------------------------------ //
    //  Per-channel registers
    // ------------------------------------------------------------------ //
    reg [31:0] ch_top   [0:NUM_CH-1];
    reg [31:0] ch_cmp   [0:NUM_CH-1];
    reg [31:0] ch_cnt   [0:NUM_CH-1];
    reg [NUM_CH-1:0] ch_pwm;
    reg [NUM_CH-1:0] istat_reg;

    assign reg_cnt_do   = ch_cnt[reg_cnt_sel];
    assign reg_top_do   = ch_top[reg_top_sel];
    assign reg_cmp_do   = ch_cmp[reg_cmp_sel];
    assign reg_istat_do = {{(32-NUM_CH){1'b0}}, istat_reg};

    integer j;
    always @(posedge clk) begin
        if (!resetn) begin
            for (j = 0; j < NUM_CH; j = j + 1) begin
                ch_top[j] <= 32'hFFFF_FFFF;
                ch_cmp[j] <= 32'h0000_0000;
            end
        end else begin
            if (reg_top_we)
                ch_top[reg_top_sel] <= reg_top_di;
            if (reg_cmp_we)
                ch_cmp[reg_cmp_sel] <= reg_cmp_di;
        end
    end

    // ------------------------------------------------------------------ //
    //  Combinational next-state for ctrl_en and istat
    //  BUG FIX #1 & #2: clear has highest priority; psc_tick processed first
    // ------------------------------------------------------------------ //
    integer i;
    always @(*) begin
        ctrl_en_next = ctrl_en;
        istat_next   = istat_reg;

        // 1. Hardware events on psc_tick (lowest priority)
        if (psc_tick) begin
            for (i = 0; i < NUM_CH; i = i + 1) begin
                if (ctrl_en[i]) begin
                    // Compare match → set interrupt flag
                    if (ch_cnt[i] == ch_cmp[i]) begin
                        if (ctrl_ien[i])
                            istat_next[i] = 1'b1;
                    end
                    // One-shot auto-disable at TOP
                    if ((ch_cnt[i] >= ch_top[i]) && ctrl_mode[i]) begin
                        ctrl_en_next[i] = 1'b0;
                    end
                end
            end
        end

        // 2. Software enable write (overrides one-shot disable in same cycle)
        if (reg_ctrl_we)
            ctrl_en_next = reg_ctrl_di[NUM_CH-1:0];

        // 3. Software W1C clear (highest priority - clears even if hw set above)
        if (reg_istat_we)
            istat_next = istat_next & ~reg_istat_di[NUM_CH-1:0];
    end

    // ------------------------------------------------------------------ //
    //  Sequential: control and interrupt registers
    // ------------------------------------------------------------------ //
    always @(posedge clk) begin
        if (!resetn) begin
            ctrl_en    <= {NUM_CH{1'b0}};
            ctrl_mode  <= {NUM_CH{1'b0}};
            ctrl_ien   <= {NUM_CH{1'b0}};
            ctrl_pwmen <= {NUM_CH{1'b0}};
            ctrl_cmpen <= {NUM_CH{1'b0}};
            istat_reg  <= {NUM_CH{1'b0}};
        end else begin
            ctrl_en   <= ctrl_en_next;
            istat_reg <= istat_next;

            if (reg_ctrl_we) begin
                ctrl_mode  <= reg_ctrl_di[NUM_CH-1+4  : 4];
                ctrl_ien   <= reg_ctrl_di[NUM_CH-1+8  : 8];
                ctrl_pwmen <= reg_ctrl_di[NUM_CH-1+12 : 12];
                ctrl_cmpen <= reg_ctrl_di[NUM_CH-1+16 : 16];
            end
        end
    end

    // ------------------------------------------------------------------ //
    //  Sequential: counters and PWM output
    // ------------------------------------------------------------------ //
    integer k;
    always @(posedge clk) begin
        if (!resetn) begin
            for (k = 0; k < NUM_CH; k = k + 1) begin
                ch_cnt[k] <= 32'b0;
                ch_pwm[k] <= 1'b0;
            end
        end else if (psc_tick) begin
            for (k = 0; k < NUM_CH; k = k + 1) begin
                if (ctrl_en[k]) begin
                    // Toggle on compare match
                    if (ch_cnt[k] == ch_cmp[k]) begin
                        if (ctrl_pwmen[k] || ctrl_cmpen[k])
                            ch_pwm[k] <= ~ch_pwm[k];
                    end
                    // Wrap at TOP
                    if (ch_cnt[k] >= ch_top[k]) begin
                        ch_cnt[k] <= 32'b0;
                        ch_pwm[k] <= 1'b0;
                    end else begin
                        ch_cnt[k] <= ch_cnt[k] + 32'd1;
                    end
                end
            end
        end
    end

    // ------------------------------------------------------------------ //
    //  PWM output drivers
    // ------------------------------------------------------------------ //
    genvar gi;
    generate
        for (gi = 0; gi < NUM_CH; gi = gi + 1) begin : pwm_drv
            assign pwm_out[gi] = (ctrl_pwmen[gi] || ctrl_cmpen[gi]) ? ch_pwm[gi] : 1'b0;
        end
    endgenerate

    assign irq = |(istat_reg & ctrl_ien);

endmodule

`default_nettype wire