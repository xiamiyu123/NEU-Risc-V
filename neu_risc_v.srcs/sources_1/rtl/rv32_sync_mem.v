`timescale 1ns/1ps
// 同步读、按字节写的单端口存储器。
module rv32_sync_mem #(
    parameter ADDR_BITS = 8, // 字数 = 2^ADDR_BITS
    parameter INIT_FILE = "" // 可选初始化文件
) (
    input  wire        clk,
    input  wire        re,
    input  wire        we,
    input  wire [3:0]  wstrb, // 字节写使能
    input  wire [31:0] addr, // 字节地址
    input  wire [31:0] wdata,
    output reg  [31:0] rdata
);
    reg [31:0] mem [0:(1 << ADDR_BITS)-1];
    integer    i, byte_i;

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
