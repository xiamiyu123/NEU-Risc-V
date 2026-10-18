`timescale 1ns/1ps
// RV32I 与 uadd8sat 组合译码。
module rv32_control (
    input  wire [31:0] instr,

    output wire [4:0]  rs1,
    output wire [4:0]  rs2,
    output wire [4:0]  rd,
    output wire [2:0]  funct3,

    output reg         valid, // 编码合法
    output reg         regwrite,
    output reg         memread,
    output reg         memwrite,

    output reg         uses_rs1, // 读取 rs1
    output reg         uses_rs2, // 读取 rs2

    output reg         op1_pc, // A 端选 PC
    output reg         op2_imm, // B 端选立即数

    output reg         branch,
    output reg         jump,
    output reg         jalr,
    output reg         link, // 写回 PC+4

    output reg         system_trap, // ECALL/EBREAK
    output reg  [4:0]  system_cause, // 系统异常原因

    output reg  [3:0]  alu_op,
    output reg  [31:0] imm
);
    `include "rv32_alu_ops.vh"

    assign rs1    = instr[19:15];
    assign rs2    = instr[24:20];
    assign rd     = instr[11:7];
    assign funct3 = instr[14:12];
    wire [6:0] funct7 = instr[31:25];

    always @* begin
        valid        = 0;
        regwrite     = 0;
        memread      = 0;
        memwrite     = 0;
        uses_rs1     = 0;
        uses_rs2     = 0;
        op1_pc       = 0;
        op2_imm      = 0;
        branch       = 0;
        jump         = 0;
        jalr         = 0;
        link         = 0;
        system_trap  = 0;
        system_cause = 0;
        alu_op       = ALU_ADD;
        imm          = 0;

        case (instr[6:0])
            7'b0110011: begin // OP
                uses_rs1 = 1;
                uses_rs2 = 1;
                case ({funct7, funct3})
                    {7'b0000000, 3'b000}: begin // ADD
                        valid = 1;
                        alu_op = ALU_ADD;
                    end
                    {7'b0100000, 3'b000}: begin // SUB
                        valid = 1;
                        alu_op = ALU_SUB;
                    end
                    {7'b0000000, 3'b010}: begin // SLT
                        valid = 1;
                        alu_op = ALU_SLT;
                    end
                    {7'b0000000, 3'b011}: begin // SLTU
                        valid = 1;
                        alu_op = ALU_SLTU;
                    end
                    {7'b0000000, 3'b001}: begin // SLL
                        valid = 1;
                        alu_op = ALU_SLL;
                    end
                    {7'b0000000, 3'b101}: begin // SRL
                        valid = 1;
                        alu_op = ALU_SRL;
                    end
                    {7'b0100000, 3'b101}: begin // SRA
                        valid = 1;
                        alu_op = ALU_SRA;
                    end
                    {7'b0000000, 3'b100}: begin // XOR
                        valid = 1;
                        alu_op = ALU_XOR;
                    end
                    {7'b0000000, 3'b110}: begin // OR
                        valid = 1;
                        alu_op = ALU_OR;
                    end
                    {7'b0000000, 3'b111}: begin // AND
                        valid = 1;
                        alu_op = ALU_AND;
                    end
                endcase
                regwrite = valid;
            end
            7'b0010011: begin // OP-IMM
                uses_rs1 = 1;
                op2_imm  = 1;
                imm = {{20{instr[31]}}, instr[31:20]};
                case (funct3)
                    3'b000: begin // ADDI
                        valid = 1;
                        alu_op = ALU_ADD;
                    end
                    3'b010: begin // SLTI
                        valid = 1;
                        alu_op = ALU_SLT;
                    end
                    3'b011: begin // SLTIU
                        valid = 1;
                        alu_op = ALU_SLTU;
                    end
                    3'b100: begin // XORI
                        valid = 1;
                        alu_op = ALU_XOR;
                    end
                    3'b110: begin // ORI
                        valid = 1;
                        alu_op = ALU_OR;
                    end
                    3'b111: begin // ANDI
                        valid = 1;
                        alu_op = ALU_AND;
                    end
                    3'b001: begin // SLLI
                        if (funct7 == 0) begin
                            valid = 1;
                            alu_op = ALU_SLL;
                        end
                    end
                    3'b101: begin // SRLI/SRAI
                        if (funct7 == 0) begin
                            valid = 1;
                            alu_op = ALU_SRL;
                        end else if (funct7 == 7'b0100000) begin
                            valid = 1;
                            alu_op = ALU_SRA;
                        end
                    end
                endcase
                regwrite = valid;
            end
            7'b0110111: begin // LUI
                valid    = 1;
                regwrite = 1;
                op2_imm  = 1;
                alu_op   = ALU_LUI;
                imm      = {instr[31:12], 12'b0};
            end
            7'b0010111: begin // AUIPC
                valid    = 1;
                regwrite = 1;
                op1_pc   = 1;
                op2_imm  = 1;
                imm      = {instr[31:12], 12'b0};
            end
            7'b0000011: begin // LOAD
                // funct3 000/001/010/100/101：LB/LH/LW/LBU/LHU
                if (funct3 == 3'b000 || funct3 == 3'b001 ||
                    funct3 == 3'b010 || funct3 == 3'b100 ||
                    funct3 == 3'b101) begin
                    valid    = 1;
                    regwrite = 1;
                    memread  = 1;
                    uses_rs1 = 1;
                    op2_imm  = 1;
                    imm      = {{20{instr[31]}}, instr[31:20]};
                end
            end
            7'b0100011: begin // STORE
                // funct3 000/001/010：SB/SH/SW
                if (funct3 == 3'b000 || funct3 == 3'b001 ||
                    funct3 == 3'b010) begin
                    valid    = 1;
                    memwrite = 1;
                    uses_rs1 = 1;
                    uses_rs2 = 1;
                    op2_imm  = 1;
                    imm      = {{20{instr[31]}}, instr[31:25], instr[11:7]};
                end
            end
            7'b1100011: begin // BRANCH
                // funct3 000/001/100/101/110/111：BEQ/BNE/BLT/BGE/BLTU/BGEU
                if (funct3 == 3'b000 || funct3 == 3'b001 ||
                    funct3 == 3'b100 || funct3 == 3'b101 ||
                    funct3 == 3'b110 || funct3 == 3'b111) begin
                    valid    = 1;
                    branch   = 1;
                    uses_rs1 = 1;
                    uses_rs2 = 1;
                    imm      = {{19{instr[31]}}, instr[31], instr[7],
                                instr[30:25], instr[11:8], 1'b0};
                end
            end
            7'b1101111: begin // JAL
                valid    = 1;
                regwrite = 1;
                jump     = 1;
                link     = 1;
                imm      = {{11{instr[31]}}, instr[31], instr[19:12],
                            instr[20], instr[30:21], 1'b0};
            end
            7'b1100111: begin // JALR
                if (funct3 == 3'b000) begin
                    valid    = 1;
                    regwrite = 1;
                    uses_rs1 = 1;
                    op2_imm  = 1;
                    jump     = 1;
                    jalr     = 1;
                    link     = 1;
                    imm      = {{20{instr[31]}}, instr[31:20]};
                end
            end
            7'b0001111: begin // FENCE
                if (funct3 == 3'b000)
                    valid = 1;
            end
            7'b1110011: begin // SYSTEM
                if (instr == 32'h00000073) begin
                    valid        = 1;
                    system_trap  = 1;
                    system_cause = 11; // ECALL
                end else if (instr == 32'h00100073) begin
                    valid        = 1;
                    system_trap  = 1;
                    system_cause = 3; // EBREAK
                end
            end
            7'b0001011: begin // CUSTOM-0：uadd8sat
                if (funct3 == 3'b000 && funct7 == 7'b0000000) begin
                    valid    = 1;
                    regwrite = 1;
                    uses_rs1 = 1;
                    uses_rs2 = 1;
                    alu_op   = ALU_UADD8SAT;
                end
            end
        endcase
    end
endmodule
