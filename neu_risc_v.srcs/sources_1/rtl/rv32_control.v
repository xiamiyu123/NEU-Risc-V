`timescale 1ns/1ps
// 组合译码：识别指令编码，生成立即数、数据通路控制和源寄存器使用标志。
module rv32_control (
    input wire [31:0] instr,
    output wire [4:0] rs1,
    output wire [4:0] rs2,
    output wire [4:0] rd,
    output wire [2:0] funct3,
    output reg valid,
    output reg regwrite,
    output reg memread,
    output reg memwrite,
    output reg uses_rs1,
    output reg uses_rs2,
    output reg op1_pc,
    output reg op2_imm,
    output reg branch,
    output reg jump,
    output reg jalr,
    output reg link,
    output reg system_trap,
    output reg [4:0] system_cause,
    output reg [3:0] alu_op,
    output reg [31:0] imm
);
    `include "rv32_alu_ops.vh"

    assign rs1 = instr[19:15];
    assign rs2 = instr[24:20];
    assign rd = instr[11:7];
    assign funct3 = instr[14:12];
    wire [6:0] funct7 = instr[31:25];

    always @* begin
        valid = 0;
        regwrite = 0;
        memread = 0;
        memwrite = 0;
        uses_rs1 = 0;
        uses_rs2 = 0;
        op1_pc = 0;
        op2_imm = 0;
        branch = 0;
        jump = 0;
        jalr = 0;
        link = 0;
        system_trap = 0;
        system_cause = 0;
        alu_op = ALU_ADD;
        imm = 0;
        case (instr[6:0])
            // OPCODE 0110011: R-type register-register ALU operations.
            7'b0110011: begin
                uses_rs1 = 1;
                uses_rs2 = 1;
                case ({funct7, funct3})
                    // ADD
                    {7'b0000000, 3'b000}: begin
                        valid = 1;
                        alu_op = ALU_ADD;
                    end
                    // SUB
                    {7'b0100000, 3'b000}: begin
                        valid = 1;
                        alu_op = ALU_SUB;
                    end
                    // SLT
                    {7'b0000000, 3'b010}: begin
                        valid = 1;
                        alu_op = ALU_SLT;
                    end
                    // SLTU
                    {7'b0000000, 3'b011}: begin
                        valid = 1;
                        alu_op = ALU_SLTU;
                    end
                    // SLL
                    {7'b0000000, 3'b001}: begin
                        valid = 1;
                        alu_op = ALU_SLL;
                    end
                    // SRL
                    {7'b0000000, 3'b101}: begin
                        valid = 1;
                        alu_op = ALU_SRL;
                    end
                    // SRA
                    {7'b0100000, 3'b101}: begin
                        valid = 1;
                        alu_op = ALU_SRA;
                    end
                    // XOR
                    {7'b0000000, 3'b100}: begin
                        valid = 1;
                        alu_op = ALU_XOR;
                    end
                    // OR
                    {7'b0000000, 3'b110}: begin
                        valid = 1;
                        alu_op = ALU_OR;
                    end
                    // AND
                    {7'b0000000, 3'b111}: begin
                        valid = 1;
                        alu_op = ALU_AND;
                    end
                endcase
                regwrite = valid;
            end
            // OPCODE 0010011: immediate ALU operations; funct3 selects the operation.
            7'b0010011: begin
                uses_rs1 = 1;
                op2_imm = 1;
                imm = {{20{instr[31]}}, instr[31:20]};
                case (funct3)
                    // ADDI
                    3'b000: begin
                        valid = 1;
                        alu_op = ALU_ADD;
                    end
                    // SLTI
                    3'b010: begin
                        valid = 1;
                        alu_op = ALU_SLT;
                    end
                    // SLTIU
                    3'b011: begin
                        valid = 1;
                        alu_op = ALU_SLTU;
                    end
                    // XORI
                    3'b100: begin
                        valid = 1;
                        alu_op = ALU_XOR;
                    end
                    // ORI
                    3'b110: begin
                        valid = 1;
                        alu_op = ALU_OR;
                    end
                    // ANDI
                    3'b111: begin
                        valid = 1;
                        alu_op = ALU_AND;
                    end
                    3'b001: begin
                        if (funct7 == 0) begin // SLLI requires funct7=0000000.
                            valid = 1;
                            alu_op = ALU_SLL;
                        end
                    end
                    3'b101: begin // SRLI/SRAI distinguished by funct7.
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
            // OPCODE 0110111: LUI, rd = U-immediate.
            7'b0110111: begin
                valid = 1;
                regwrite = 1;
                op2_imm = 1;
                alu_op = ALU_LUI;
                imm = {instr[31:12], 12'b0};
            end
            // OPCODE 0010111: AUIPC, rd = PC + U-immediate.
            7'b0010111: begin
                valid = 1;
                regwrite = 1;
                op1_pc = 1;
                op2_imm = 1;
                imm = {instr[31:12], 12'b0};
            end
            // OPCODE 0000011: LOAD; funct3 000/001/010/100/101 = LB/LH/LW/LBU/LHU.
            7'b0000011: begin
                if (funct3 == 3'b000 || funct3 == 3'b001 ||
                    funct3 == 3'b010 || funct3 == 3'b100 ||
                    funct3 == 3'b101) begin
                    valid = 1;
                    regwrite = 1;
                    memread = 1;
                    uses_rs1 = 1;
                    op2_imm = 1;
                    imm = {{20{instr[31]}}, instr[31:20]};
                end
            end
            // OPCODE 0100011: STORE; funct3 000/001/010 = SB/SH/SW.
            7'b0100011: begin
                if (funct3 == 3'b000 || funct3 == 3'b001 ||
                    funct3 == 3'b010) begin
                    valid = 1;
                    memwrite = 1;
                    uses_rs1 = 1;
                    uses_rs2 = 1;
                    op2_imm = 1;
                    imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
                end
            end
            // OPCODE 1100011: BRANCH; funct3 000/001/100/101/110/111 = BEQ/BNE/BLT/BGE/BLTU/BGEU.
            7'b1100011: begin
                if (funct3 == 3'b000 || funct3 == 3'b001 ||
                    funct3 == 3'b100 || funct3 == 3'b101 ||
                    funct3 == 3'b110 || funct3 == 3'b111) begin
                    valid = 1;
                    branch = 1;
                    uses_rs1 = 1;
                    uses_rs2 = 1;
                    imm = {{19{instr[31]}}, instr[31], instr[7],
                           instr[30:25], instr[11:8], 1'b0};
                end
            end
            // OPCODE 1101111: JAL, PC-relative jump with link.
            7'b1101111: begin
                valid = 1;
                regwrite = 1;
                jump = 1;
                link = 1;
                imm = {{11{instr[31]}}, instr[31], instr[19:12],
                       instr[20], instr[30:21], 1'b0};
            end
            // OPCODE 1100111: JALR (funct3=000).
            7'b1100111: begin
                if (funct3 == 3'b000) begin
                    valid = 1;
                    regwrite = 1;
                    uses_rs1 = 1;
                    op2_imm = 1;
                    jump = 1;
                    jalr = 1;
                    link = 1;
                    imm = {{20{instr[31]}}, instr[31:20]};
                end
            end
            // OPCODE 0001111, funct3=000: FENCE.
            7'b0001111: begin
                if (funct3 == 3'b000)
                    valid = 1; // FENCE: memory accesses already retire in order.
            end
            // OPCODE 1110011: SYSTEM; exact 32-bit encodings below.
            7'b1110011: begin
                if (instr == 32'h00000073) begin
                    valid = 1;
                    system_trap = 1;
                    system_cause = 11; // ECALL from machine mode
                end else if (instr == 32'h00100073) begin
                    valid = 1;
                    system_trap = 1;
                    system_cause = 3; // EBREAK
                end
            end
            // CUSTOM-0: uadd8sat.
            7'b0001011: begin
                if (funct3 == 3'b000 && funct7 == 7'b0000000) begin
                    valid = 1;
                    regwrite = 1;
                    uses_rs1 = 1;
                    uses_rs2 = 1;
                    alu_op = ALU_UADD8SAT;
                end
            end
        endcase
    end
endmodule
