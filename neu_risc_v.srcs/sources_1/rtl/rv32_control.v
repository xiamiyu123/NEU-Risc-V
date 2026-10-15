`timescale 1ns/1ps
//=============================================================================
// 模块名 : rv32_control
// 文件   : rv32_control.v
// 功能   : 指令译码器（纯组合逻辑）
//          根据 32 位指令编码，生成本模块内部所有的数据通路控制信号、立即数
//          以及“是否使用 rs1/rs2”标志（后者用于冒险检测的 load-use 停顿判断）。
// 输入   : instr —— 32 位指令（来自 IF/ID 流水寄存器）
// 输出   : 见端口注释
// 约定   : 所有输出在 always @* 开头先置默认值（全 0 / ALU_ADD），
//          再由 case 覆盖，避免综合出锁存器（latch）。
// 支持指令（RV32I 子集 + 定制指令）：
//   基础 9 条 : add, slt, sltu, ori, lui, lw, sw, beq, jal
//   扩展      : sub/and/or/xor/sll/srl/sra, addi/slti/sltiu/xori/andi/slli/srli/srai,
//               auipc, lb/lh/lbu/lhu, sb/sh, bne/blt/bge/bltu/bgeu, jalr,
//               fence(空操作), ecall/ebreak(触发异常)
//   定制      : uadd8sat（Custom-0，4 路字节饱和加法）
//=============================================================================
module rv32_control (
    input  wire [31:0] instr,          // 待译码指令
    // ---- 寄存器索引与功能位（直接从指令位域提取）----
    output wire [4:0]  rs1,            // 源寄存器 1 索引
    output wire [4:0]  rs2,            // 源寄存器 2 索引
    output wire [4:0]  rd,             // 目的寄存器索引
    output wire [2:0]  funct3,         // funct3 位域（选择运算/宽度/分支类型）
    // ---- 主控制信号 ----
    output reg         valid,          // 指令合法（否则进入非法指令异常）
    output reg         regwrite,       // 写回寄存器堆使能
    output reg         memread,        // 读数据存储器使能（load）
    output reg         memwrite,       // 写数据存储器使能（store）
    // ---- 冒险检测辅助：本指令是否真正使用对应源寄存器 ----
    output reg         uses_rs1,       // 使用 rs1（如 lw 的基址、add 的两个源）
    output reg         uses_rs2,       // 使用 rs2
    // ---- ALU 操作数来源选择 ----
    output reg         op1_pc,         // ALU A 端取 PC（AUIPC）
    output reg         op2_imm,        // ALU B 端取立即数（否则取 rs2）
    // ---- 控制流 ----
    output reg         branch,         // 条件分支指令
    output reg         jump,           // 无条件跳转（JAL/JALR）
    output reg         jalr,           // JALR（跳转目标由寄存器给出）
    output reg         link,           // 写回 PC+4（JAL/JALR 的链接值）
    // ---- 异常 ----
    output reg         system_trap,    // 系统指令触发异常（ecall/ebreak）
    output reg  [4:0]  system_cause,   // 系统指令异常原因码
    // ---- ALU ----
    output reg  [3:0]  alu_op,         // ALU 操作选择码
    output reg  [31:0] imm             // 译码得到的立即数（已按要求扩展）
);
    `include "rv32_alu_ops.vh"

    // 从指令位域直接提取寄存器索引与 funct3（多数字段位置固定）
    assign rs1    = instr[19:15];
    assign rs2    = instr[24:20];
    assign rd     = instr[11:7];
    assign funct3 = instr[14:12];
    wire [6:0] funct7 = instr[31:25]; // funct7 位域：区分 R 型同一 funct3 的不同操作

    always @* begin
        //---------------------------------------------------------------------
        // 默认值：所有信号先清零，再按 opcode 逐条覆盖，避免锁存器
        //---------------------------------------------------------------------
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

        //---------------------------------------------------------------------
        // 按 opcode（instr[6:0]）分派
        //---------------------------------------------------------------------
        case (instr[6:0])
            //=================================================================
            // OPCODE 0110011：R 型寄存器-寄存器运算，由 {funct7,funct3} 唯一确定
            //=================================================================
            7'b0110011: begin
                uses_rs1 = 1;
                uses_rs2 = 1;
                case ({funct7, funct3})
                    {7'b0000000, 3'b000}: begin valid = 1; alu_op = ALU_ADD;  end // ADD
                    {7'b0100000, 3'b000}: begin valid = 1; alu_op = ALU_SUB;  end // SUB
                    {7'b0000000, 3'b010}: begin valid = 1; alu_op = ALU_SLT;  end // SLT
                    {7'b0000000, 3'b011}: begin valid = 1; alu_op = ALU_SLTU; end // SLTU
                    {7'b0000000, 3'b001}: begin valid = 1; alu_op = ALU_SLL;  end // SLL
                    {7'b0000000, 3'b101}: begin valid = 1; alu_op = ALU_SRL;  end // SRL
                    {7'b0100000, 3'b101}: begin valid = 1; alu_op = ALU_SRA;  end // SRA
                    {7'b0000000, 3'b100}: begin valid = 1; alu_op = ALU_XOR;  end // XOR
                    {7'b0000000, 3'b110}: begin valid = 1; alu_op = ALU_OR;   end // OR
                    {7'b0000000, 3'b111}: begin valid = 1; alu_op = ALU_AND;  end // AND
                endcase
                regwrite = valid; // 仅对已识别指令写回
            end
            //=================================================================
            // OPCODE 0010011：I 型立即数运算，funct3 选操作
            //   立即数：instr[31:20] 符号扩展（移位类指令复用该域高 7 位作 funct7）
            //=================================================================
            7'b0010011: begin
                uses_rs1 = 1;
                op2_imm  = 1;
                imm = {{20{instr[31]}}, instr[31:20]};
                case (funct3)
                    3'b000:  begin valid = 1; alu_op = ALU_ADD;  end // ADDI
                    3'b010:  begin valid = 1; alu_op = ALU_SLT;  end // SLTI
                    3'b011:  begin valid = 1; alu_op = ALU_SLTU; end // SLTIU
                    3'b100:  begin valid = 1; alu_op = ALU_XOR;  end // XORI
                    3'b110:  begin valid = 1; alu_op = ALU_OR;   end // ORI
                    3'b111:  begin valid = 1; alu_op = ALU_AND;  end // ANDI
                    3'b001: begin                                     // SLLI
                        if (funct7 == 0) begin // SLLI 要求 funct7=0000000
                            valid = 1;
                            alu_op = ALU_SLL;
                        end
                    end
                    3'b101: begin                                     // SRLI / SRAI
                        if (funct7 == 0) begin                      // funct7=0 → 逻辑右移
                            valid = 1;
                            alu_op = ALU_SRL;
                        end else if (funct7 == 7'b0100000) begin    // funct7=0100000 → 算术右移
                            valid = 1;
                            alu_op = ALU_SRA;
                        end
                    end
                endcase
                regwrite = valid;
            end
            //=================================================================
            // OPCODE 0110111：LUI，rd = 立即数 << 12（低 12 位补 0）
            //=================================================================
            7'b0110111: begin
                valid    = 1;
                regwrite = 1;
                op2_imm  = 1;
                alu_op   = ALU_LUI;
                imm      = {instr[31:12], 12'b0};
            end
            //=================================================================
            // OPCODE 0010111：AUIPC，rd = PC + (立即数 << 12)
            //=================================================================
            7'b0010111: begin
                valid    = 1;
                regwrite = 1;
                op1_pc   = 1; // ALU A 端取 PC
                op2_imm  = 1;
                imm      = {instr[31:12], 12'b0};
            end
            //=================================================================
            // OPCODE 0000011：LOAD，funct3 = 000/001/010/100/101 = LB/LH/LW/LBU/LHU
            //=================================================================
            7'b0000011: begin
                if (funct3 == 3'b000 || funct3 == 3'b001 ||
                    funct3 == 3'b010 || funct3 == 3'b100 ||
                    funct3 == 3'b101) begin
                    valid    = 1;
                    regwrite = 1;
                    memread  = 1;
                    uses_rs1 = 1;   // 基址寄存器
                    op2_imm  = 1;   // 地址 = rs1 + imm
                    imm      = {{20{instr[31]}}, instr[31:20]};
                end
            end
            //=================================================================
            // OPCODE 0100011：STORE，funct3 = 000/001/010 = SB/SH/SW
            //   立即数为 S 型不规则拼接：立即数的高位分布在 instr[31:25] 与 [11:7]
            //=================================================================
            7'b0100011: begin
                if (funct3 == 3'b000 || funct3 == 3'b001 ||
                    funct3 == 3'b010) begin
                    valid    = 1;
                    memwrite = 1;
                    uses_rs1 = 1;   // 基址寄存器
                    uses_rs2 = 1;   // 待写入的数据寄存器
                    op2_imm  = 1;
                    imm      = {{20{instr[31]}}, instr[31:25], instr[11:7]};
                end
            end
            //=================================================================
            // OPCODE 1100011：BRANCH，funct3 = 000/001/100/101/110/111
            //                              = BEQ/BNE/BLT/BGE/BLTU/BGEU
            //   B 型立即数拼接：instr[31],[7],[30:25],[11:8]，最低位恒 0
            //=================================================================
            7'b1100011: begin
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
            //=================================================================
            // OPCODE 1101111：JAL，PC 相对跳转并写回链接地址 PC+4
            //   J 型立即数拼接：instr[31],[19:12],[20],[30:21]，最低位恒 0
            //=================================================================
            7'b1101111: begin
                valid    = 1;
                regwrite = 1;
                jump     = 1;
                link     = 1;
                imm      = {{11{instr[31]}}, instr[31], instr[19:12],
                            instr[20], instr[30:21], 1'b0};
            end
            //=================================================================
            // OPCODE 1100111：JALR（funct3=000），跳转目标 = (rs1 + imm) & ~1
            //=================================================================
            7'b1100111: begin
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
            //=================================================================
            // OPCODE 0001111，funct3=000：FENCE
            //   本核的访存严格按序退休，故 FENCE 译码为合法但不产生任何动作。
            //=================================================================
            7'b0001111: begin
                if (funct3 == 3'b000)
                    valid = 1; // FENCE：访存已按程序顺序完成，无需额外处理
            end
            //=================================================================
            // OPCODE 1110011：SYSTEM，仅识别 ecall / ebreak 两条精确编码
            //=================================================================
            7'b1110011: begin
                if (instr == 32'h00000073) begin        // ECALL
                    valid        = 1;
                    system_trap  = 1;
                    system_cause = 11;                  // 机器模式 ecall
                end else if (instr == 32'h00100073) begin // EBREAK
                    valid        = 1;
                    system_trap  = 1;
                    system_cause = 3;                   // 断点
                end
            end
            //=================================================================
            // OPCODE 0001011：CUSTOM-0，仅实现 uadd8sat（funct3=000, funct7=0000000）
            //   4 路字节饱和加法：把 rs1、rs2 各拆成 4 字节，逐字节相加，
            //   结果超过 255 的字节饱和为 0xFF。
            //=================================================================
            7'b0001011: begin
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