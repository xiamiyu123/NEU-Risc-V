`timescale 1ns/1ps
//=============================================================================
// 模块名 : rv32_regfile
// 文件   : rv32_regfile.v
// 功能   : 32 x 32 位通用寄存器堆（RV32I）
//          - 双读口（rs1/rs2）+ 单写口（rd）
//          - 写口在时钟上升沿写入；x0 恒为 0（写入被屏蔽、读出恒 0）
//          - 读写同址时提供“同拍旁路”，保证同周期写后立即读到新值
// 说明   : 组合读、时序写；同步复位（rst=1 时清空全部寄存器）
//=============================================================================
module rv32_regfile (
    input  wire        clk,     // 时钟
    input  wire        rst,     // 同步复位，高有效
    input  wire [4:0]  rs1,     // 读端口 1 地址
    input  wire [4:0]  rs2,     // 读端口 2 地址
    input  wire        we,      // 写使能
    input  wire [4:0]  rd,      // 写端口地址
    input  wire [31:0] wdata,   // 写数据
    output wire [31:0] rdata1,  // 读端口 1 数据（组合）
    output wire [31:0] rdata2   // 读端口 2 数据（组合）
);
    reg [31:0] regs [0:31];     // 32 个 32 位寄存器
    integer    reg_i;           // 复位清空循环变量

    // 组合读：地址为 0 时恒返回 0（x0 语义）；
    // 若本拍正在写入同一寄存器（we && rd == rsN），则直接旁路新数据，
    // 这样无需额外停顿即可在同一周期读到刚写入的值。
    assign rdata1 = rs1 == 0 ? 0 :
        (we && rd == rs1 ? wdata : regs[rs1]);
    assign rdata2 = rs2 == 0 ? 0 :
        (we && rd == rs2 ? wdata : regs[rs2]);

    // 时序写：复位时清空全部寄存器；否则在写使能且目标非 x0 时写入
    always @(posedge clk) begin
        if (rst) begin
            for (reg_i = 0; reg_i < 32; reg_i = reg_i + 1)
                regs[reg_i] <= 0;
        end else if (we && rd != 0) begin
            regs[rd] <= wdata;   // 写 x0 被忽略，保证 x0 恒为 0
        end
    end
endmodule