module picorv32_ram #(
    parameter MEM_WORDS = 8192   // 32KB
)(
    input  wire        clk,

    input  wire        mem_valid,
    output reg         mem_ready,
    input  wire [31:0] mem_addr,
    input  wire [31:0] mem_wdata,
    input  wire [3:0]  mem_wstrb,
    output reg  [31:0] mem_rdata
);

    // 32KB RAM
    reg [31:0] memory [0:MEM_WORDS-1];

    // Nạp firmware
    initial begin
        $readmemh("firmware.hex", memory);
    end

    wire [12:0] word_addr = mem_addr[14:2];
    // 14:2 vì:
    // 32KB → cần 15 bit địa chỉ byte (0–32767)
    // bỏ 2 bit thấp → còn 13 bit word address

    always @(posedge clk) begin
        mem_ready <= 1'b0;

        if (mem_valid) begin
            mem_ready <= 1'b1;

            // READ
            mem_rdata <= memory[word_addr];

            // WRITE
            if (mem_wstrb[0]) memory[word_addr][7:0]   <= mem_wdata[7:0];
            if (mem_wstrb[1]) memory[word_addr][15:8]  <= mem_wdata[15:8];
            if (mem_wstrb[2]) memory[word_addr][23:16] <= mem_wdata[23:16];
            if (mem_wstrb[3]) memory[word_addr][31:24] <= mem_wdata[31:24];
        end
    end

endmodule