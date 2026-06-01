module simplegpio #(
    parameter integer NUM_GPIO = 8
) (
    input  clk,
    input  resetn,


    inout  [NUM_GPIO-1:0] gpio,


    input         reg_dir_we,
    input  [31:0] reg_dir_di,
    output [31:0] reg_dir_do,


    input         reg_out_we,
    input  [31:0] reg_out_di,
    output [31:0] reg_out_do,


    output [31:0] reg_in_do,


    input         reg_set_we,
    input  [31:0] reg_set_di,
    input         reg_clr_we,
    input  [31:0] reg_clr_di,
    input         reg_tog_we,
    input  [31:0] reg_tog_di,


    input         reg_ien_we,
    input  [31:0] reg_ien_di,
    output [31:0] reg_ien_do,


    input         reg_istat_we,
    input  [31:0] reg_istat_di,
    output [31:0] reg_istat_do,


    input         reg_icfg_we,
    input  [31:0] reg_icfg_di,
    output [31:0] reg_icfg_do,


    output irq
);

    // -------------------------------------------------------------------------
    // Registers
    // -------------------------------------------------------------------------
    reg [NUM_GPIO-1:0] dir_reg;    // 0=in, 1=out
    reg [NUM_GPIO-1:0] out_reg;    // output latch
    reg [NUM_GPIO-1:0] ien_reg;    // interrupt enable
    reg [NUM_GPIO-1:0] istat_reg;  // interrupt status
    reg [2*NUM_GPIO-1:0] icfg_reg; // interrupt config (2 bits/pin)

    // -------------------------------------------------------------------------
    // Input synchronizer (2-stage FF)
    // -------------------------------------------------------------------------
    reg [NUM_GPIO-1:0] sync0, sync1, sync2;

    always @(posedge clk) begin
        sync0 <= gpio;
        sync1 <= sync0;
        sync2 <= sync1; 
    end

    wire [NUM_GPIO-1:0] gpio_in   = sync1;
    wire [NUM_GPIO-1:0] gpio_prev = sync2;

    // -------------------------------------------------------------------------
    // Tri-state output drivers
    // -------------------------------------------------------------------------
    genvar gi;
    generate
        for (gi = 0; gi < NUM_GPIO; gi = gi + 1) begin : gpio_drv
            assign gpio[gi] = dir_reg[gi] ? out_reg[gi] : 1'bz;
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Register reads
    // -------------------------------------------------------------------------
    assign reg_dir_do   = {{(32-NUM_GPIO){1'b0}}, dir_reg};
    assign reg_out_do   = {{(32-NUM_GPIO){1'b0}}, out_reg};
    assign reg_in_do    = {{(32-NUM_GPIO){1'b0}}, gpio_in};
    assign reg_ien_do   = {{(32-NUM_GPIO){1'b0}}, ien_reg};
    assign reg_istat_do = {{(32-NUM_GPIO){1'b0}}, istat_reg};
    assign reg_icfg_do  = {{(32-2*NUM_GPIO){1'b0}}, icfg_reg};

    // -------------------------------------------------------------------------
    // Direction register
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!resetn)
            dir_reg <= {NUM_GPIO{1'b0}};  // all inputs
        else if (reg_dir_we)
            dir_reg <= reg_dir_di[NUM_GPIO-1:0];
    end

    // -------------------------------------------------------------------------
    // Output register (with atomic set/clear/toggle)
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!resetn) begin
            out_reg <= {NUM_GPIO{1'b0}};
        end else begin
            if (reg_out_we) out_reg <=  reg_out_di[NUM_GPIO-1:0];
            if (reg_set_we) out_reg <=  out_reg |  reg_set_di[NUM_GPIO-1:0];
            if (reg_clr_we) out_reg <=  out_reg & ~reg_clr_di[NUM_GPIO-1:0];
            if (reg_tog_we) out_reg <=  out_reg ^  reg_tog_di[NUM_GPIO-1:0];
        end
    end

    // -------------------------------------------------------------------------
    // Interrupt config register
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!resetn)
            icfg_reg <= {2*NUM_GPIO{1'b0}};  // default: rising edge
        else if (reg_icfg_we)
            icfg_reg <= reg_icfg_di[2*NUM_GPIO-1:0];
    end

    // -------------------------------------------------------------------------
    // Interrupt enable register
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!resetn)
            ien_reg <= {NUM_GPIO{1'b0}};
        else if (reg_ien_we)
            ien_reg <= reg_ien_di[NUM_GPIO-1:0];
    end

    // -------------------------------------------------------------------------
    // Interrupt detection and status register
    // -------------------------------------------------------------------------
    integer i;
    always @(posedge clk) begin
        if (!resetn) begin
            istat_reg <= {NUM_GPIO{1'b0}};
        end else begin
            // Bước 1: apply write-1-to-clear trước
            if (reg_istat_we)
                istat_reg <= istat_reg & ~reg_istat_di[NUM_GPIO-1:0];

            // Bước 2: hardware set — dùng |= để không mất clear ở bước 1
            // Trick: tính pending rồi OR vào, không assign trực tiếp
            for (i = 0; i < NUM_GPIO; i = i + 1) begin
                case (icfg_reg[2*i +: 2])
                    2'b00: if (!gpio_prev[i] &&  gpio_in[i]) istat_reg[i] <= 1'b1;
                    2'b01: if ( gpio_prev[i] && !gpio_in[i]) istat_reg[i] <= 1'b1;
                    2'b10: if ( gpio_prev[i] !=  gpio_in[i]) istat_reg[i] <= 1'b1;
                    2'b11: if ( gpio_in[i])                  istat_reg[i] <= 1'b1;
                endcase
            end
        end
    end
    // -------------------------------------------------------------------------
    // IRQ output
    // -------------------------------------------------------------------------
    assign irq = |(istat_reg & ien_reg);

endmodule