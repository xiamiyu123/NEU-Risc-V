`timescale 1ns/1ps
//=============================================================================
// 模块名 : rv32_alu
// 文件   : rv32_alu.v
// 功能   : 纯组合逻辑算术运算单元（ALU）
//          - RV32I 基础运算：加、减、按位与/或/异或、移位、有符号/无符号比较
//          - 额外支持定制指令 uadd8sat（4 路字节饱和加法）
// 结构   : 单个 always @* 组合块；无时钟、无复位、无内部状态寄存器
// 说明   : result 直接在组合逻辑中给出，随 op/a/b 变化而立即变化
//=============================================================================
module rv32_alu (
    input  wire [3:0]  op,      // ALU 操作选择码，取值见 rv32_alu_ops.vh
    input  wire [31:0] a,       // 操作数 A：来自寄存器 rs1，或（AUIPC）来自 PC
    input  wire [31:0] b,       // 操作数 B：来自寄存器 rs2，或（I 型）来自立即数 imm
    output reg  [31:0] result   // 运算结果（组合输出）
);
    // 操作码常量定义：ALU_ADD / ALU_SUB / ALU_SLT / ... / ALU_UADD8SAT
    `include "rv32_alu_ops.vh"

    reg [31:0] sat_result; // uadd8sat 的逐字节饱和结果暂存
    reg [8:0]  byte_sum;   // 单字节相加的 9 位中间值（多 1 位用于判断是否溢出 8 位）
    integer    byte_i;     // 字节循环下标 0..3，对应 bit[7:0]/[15:8]/[23:16]/[31:24]

    always @* begin
        //---------------------------------------------------------------------
        // 第 1 段：预先计算 uadd8sat（4 路字节饱和加法）的结果
        //   把 a、b 各拆成 4 个独立字节，逐字节相加；
        //   每对字节的和若 >= 256，则“饱和”截断为 0xFF，否则保留原和。
        //   例如 a=0x102030FA, b=0x01020414 → 0x11_22_34_FF
        //---------------------------------------------------------------------
        sat_result = 0;
        byte_sum   = 0;
        for (byte_i = 0; byte_i < 4; byte_i = byte_i + 1) begin
            // 操作数各自零扩展到 9 位再相加，避免 8 位相加时的高位丢失（回绕）
            byte_sum = {1'b0, a[byte_i*8 +: 8]} +
                       {1'b0, b[byte_i*8 +: 8]};
            // byte_sum[8]==1 表示和 >= 256，需要饱和为 0xFF；否则取低的 8 位
            sat_result[byte_i*8 +: 8] = byte_sum[8] ? 8'hff : byte_sum[7:0];
        end

        //---------------------------------------------------------------------
        // 第 2 段：按操作码选择最终结果
        //---------------------------------------------------------------------
        case (op)
            ALU_ADD:      result = a + b;                   // 加法（ADDI/AUIPC/LUI 载入等共用）
            ALU_SUB:      result = a - b;                   // 减法
            ALU_SLT:      result = $signed(a) < $signed(b); // 有符号小于比较，结果 1 位
            ALU_SLTU:     result = a < b;                   // 无符号小于比较，结果 1 位
            ALU_XOR:      result = a ^ b;                   // 按位异或
            ALU_OR:       result = a | b;                   // 按位或
            ALU_AND:      result = a & b;                   // 按位与
            ALU_LUI:      result = b;                       // LUI：立即数经 B 端直接透传
            ALU_SLL:      result = a << b[4:0];             // 逻辑左移，移位量取低 5 位
            ALU_SRL:      result = a >> b[4:0];             // 逻辑右移（高位补 0）
            ALU_SRA:      result = $signed(a) >>> b[4:0];   // 算术右移（高位补符号位）
            ALU_UADD8SAT: result = sat_result;              // 定制指令：4 路字节饱和加法
            default:      result = 0;                       // 非法操作码：输出 0（防御性处理）
        endcase
    end
endmodule