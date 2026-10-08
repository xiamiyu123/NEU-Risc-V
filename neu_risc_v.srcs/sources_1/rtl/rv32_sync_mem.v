module rv32_sync_mem #(
    parameter ADDR_BITS = 8,
    parameter INIT_FILE = ""
) (
    input wire clk,
    input wire re,
    input wire we,
    input wire [3:0] wstrb,
    input wire [31:0] addr,
    input wire [31:0] wdata,
    output reg [31:0] rdata
);
    reg [31:0] mem [0:(1 << ADDR_BITS)-1];
    integer i, byte_i;

    initial begin
        for (i = 0; i < (1 << ADDR_BITS); i = i + 1)
            mem[i] = 0;
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    always @(posedge clk) begin
        if (re)
            rdata <= mem[addr[ADDR_BITS+1:2]];
        if (we)
            for (byte_i = 0; byte_i < 4; byte_i = byte_i + 1)
                if (wstrb[byte_i])
                    mem[addr[ADDR_BITS+1:2]][byte_i*8 +: 8] <= wdata[byte_i*8 +: 8];
    end
endmodule
