`timescale 1ns/1ps
// 32×32 位寄存器堆：双读单写、同步复位。
module rv32_regfile (
    input  wire        clk,
    input  wire        rst, // 同步高有效复位
    input  wire [4:0]  rs1,
    input  wire [4:0]  rs2,
    input  wire        we,
    input  wire [4:0]  rd,
    input  wire [31:0] wdata,
    output wire [31:0] rdata1,
    output wire [31:0] rdata2
);
    reg [31:0] regs [0:31];
    integer    reg_i;

    assign rdata1 = rs1 == 0 ? 0 :
        (we && rd == rs1 ? wdata : regs[rs1]);
    assign rdata2 = rs2 == 0 ? 0 :
        (we && rd == rs2 ? wdata : regs[rs2]);

    always @(posedge clk) begin
        if (rst) begin
            for (reg_i = 0; reg_i < 32; reg_i = reg_i + 1)
                regs[reg_i] <= 0;
        end else if (we && rd != 0) begin
            regs[rd] <= wdata;
        end
    end
endmodule
