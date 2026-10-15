`timescale 1ns/1ps
//=============================================================================
// 模块名 : rv32_sync_mem
// 文件   : rv32_sync_mem.v
// 功能   : 同步（时序）读写的单端口 RAM，同时作为指令存储器与数据存储器使用
//          - 读：时钟上升沿采样，rdata 在下一拍输出（同步读，1 拍延迟）
//          - 写：时钟上升沿按字节使能 wstrb 写入
//          - 支持通过 INIT_FILE 参数在仿真开始时预装载 hex 程序/数据
// 参数   : ADDR_BITS 地址位宽（默认 8 → 256 个字 = 1KB）
//          INIT_FILE 初始化文件路径（为空则不装载）
// 说明   : 使用 1<<ADDR_BITS 个 32 位字；地址按字寻址，忽略低 2 位
//=============================================================================
module rv32_sync_mem #(
    parameter ADDR_BITS = 8,        // 地址位宽：字数 = 2^ADDR_BITS
    parameter INIT_FILE = ""        // $readmemh 初始化文件，空字符串表示不装载
) (
    input  wire        clk,         // 时钟
    input  wire        re,          // 读使能
    input  wire        we,          // 写使能
    input  wire [3:0]  wstrb,       // 字节写使能：wstrb[i]=1 时写第 i 个字节
    input  wire [31:0] addr,        // 字节地址（低 2 位被忽略，按字对齐访问）
    input  wire [31:0] wdata,       // 写数据
    output reg  [31:0] rdata        // 读数据（同步输出）
);
    reg [31:0] mem [0:(1 << ADDR_BITS)-1]; // 存储阵列
    integer    i, byte_i;                  // i: 清零循环; byte_i: 字节写循环

    // 仿真初始化：先全部清零，再按需从文件装载程序/数据
    initial begin
        for (i = 0; i < (1 << ADDR_BITS); i = i + 1)
            mem[i] = 0;
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    // 同步读写：读数据下一拍有效；写按字节使能生效
    always @(posedge clk) begin
        if (re)
            rdata <= mem[addr[ADDR_BITS+1:2]]; // 取字地址（去掉低 2 位字节偏移）
        if (we)
            for (byte_i = 0; byte_i < 4; byte_i = byte_i + 1)
                if (wstrb[byte_i])
                    mem[addr[ADDR_BITS+1:2]][byte_i*8 +: 8] <= wdata[byte_i*8 +: 8];
    end
endmodule