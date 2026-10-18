`timescale 1ns/1ps
// 组合 ALU；操作编号见 rv32_alu_ops.vh。
module rv32_alu (
    input  wire [3:0]  op, // rv32_alu_ops.vh
    input  wire [31:0] a,
    input  wire [31:0] b,
    output reg  [31:0] result
);

    `include "rv32_alu_ops.vh"

    reg [31:0] sat_result;
    reg [8:0]  byte_sum; // 9 位字节和
    integer    byte_i;

    always @* begin
        sat_result = 0;
        byte_sum   = 0;
        for (byte_i = 0; byte_i < 4; byte_i = byte_i + 1) begin
            byte_sum = {1'b0, a[byte_i*8 +: 8]} +
                       {1'b0, b[byte_i*8 +: 8]};

            sat_result[byte_i*8 +: 8] = byte_sum[8] ? 8'hff : byte_sum[7:0]; // 进位时饱和到 255
        end

        case (op)
            ALU_ADD:      result = a + b;
            ALU_SUB:      result = a - b;
            ALU_SLT:      result = $signed(a) < $signed(b);
            ALU_SLTU:     result = a < b;
            ALU_XOR:      result = a ^ b;
            ALU_OR:       result = a | b;
            ALU_AND:      result = a & b;
            ALU_LUI:      result = b;
            ALU_SLL:      result = a << b[4:0];
            ALU_SRL:      result = a >> b[4:0];
            ALU_SRA:      result = $signed(a) >>> b[4:0];
            ALU_UADD8SAT: result = sat_result;
            default:      result = 0;
        endcase
    end
endmodule
