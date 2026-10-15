// 译码单元测试：标准指令/定制指令的控制输出、立即数边界及非法编码空间。
`timescale 1ns/1ps
module tb_control;
    `include "rv32_alu_ops.vh"
    `include "rv32_encode.svh"

    reg [31:0] instr;
    wire [4:0] rs1, rs2, rd, system_cause;
    wire [2:0] funct3;
    wire [3:0] alu_op;
    wire [31:0] imm;
    wire valid, regwrite, memread, memwrite;
    wire uses_rs1, uses_rs2, op1_pc, op2_imm;
    wire branch, jump, jalr, link, system_trap;
    integer f3, f7, checks = 0;

    // 各掩码只用于测试预期值，名字对应硬件控制端口。
    localparam [11:0] WRITE_RD = 12'h800;
    localparam [11:0] READ_MEM = 12'h400;
    localparam [11:0] WRITE_MEM = 12'h200;
    localparam [11:0] READ_RS1 = 12'h100;
    localparam [11:0] READ_RS2 = 12'h080;
    localparam [11:0] USE_PC = 12'h040;
    localparam [11:0] USE_IMM = 12'h020;
    localparam [11:0] BRANCH = 12'h010;
    localparam [11:0] JUMP = 12'h008;
    localparam [11:0] JALR = 12'h004;
    localparam [11:0] LINK = 12'h002;
    localparam [11:0] TRAP = 12'h001;
    localparam [11:0] REG_ALU = WRITE_RD | READ_RS1 | READ_RS2;
    localparam [11:0] IMM_ALU = WRITE_RD | READ_RS1 | USE_IMM;

    rv32_control dut (
        .instr(instr),
        .rs1(rs1),
        .rs2(rs2),
        .rd(rd),
        .funct3(funct3),
        .valid(valid),
        .regwrite(regwrite),
        .memread(memread),
        .memwrite(memwrite),
        .uses_rs1(uses_rs1),
        .uses_rs2(uses_rs2),
        .op1_pc(op1_pc),
        .op2_imm(op2_imm),
        .branch(branch),
        .jump(jump),
        .jalr(jalr),
        .link(link),
        .system_trap(system_trap),
        .system_cause(system_cause),
        .alu_op(alu_op),
        .imm(imm)
    );

    // 一次检查完整控制字，防止某条指令误带上另一类别的写内存/跳转等控制。
    task automatic check_decode(
        input [31:0] encoding,
        input [3:0] expected_alu,
        input [31:0] expected_imm,
        input [11:0] expected_flags,
        input [4:0] expected_cause
    );
        reg [11:0] flags;
        begin
            instr = encoding;
            #1;
            flags = {regwrite, memread, memwrite, uses_rs1, uses_rs2, op1_pc,
                     op2_imm, branch, jump, jalr, link, system_trap};
            if (valid !== 1 || flags !== expected_flags || alu_op !== expected_alu ||
                imm !== expected_imm || system_cause !== expected_cause)
                $fatal(1, "decode %08x: valid=%b flags=%03x/%03x alu=%0d/%0d imm=%08x/%08x cause=%0d/%0d",
                       instr, valid, flags, expected_flags, alu_op, expected_alu,
                       imm, expected_imm, system_cause, expected_cause);
            if ({rs1, rs2, rd, funct3} !==
                {instr[19:15], instr[24:20], instr[11:7], instr[14:12]})
                $fatal(1, "register/funct3 fields miswired: %08x", instr);
            checks = checks + 1;
        end
    endtask

    // 非法指令必须被拒绝，并且不能留下寄存器或内存写使能。
    task automatic check_illegal(input [31:0] encoding);
        begin
            instr = encoding;
            #1;
            if (valid !== 0 || regwrite !== 0 || memread !== 0 || memwrite !== 0)
                $fatal(1, "illegal instruction accepted: %08x", instr);
            checks = checks + 1;
        end
    endtask

    initial begin
        // 十条 R 型指令：funct7 必须区分 ADD/SUB、SRL/SRA。
        check_decode(rtype(0, 29, 17, 0, 31, 7'h33), ALU_ADD, 0, REG_ALU, 0);
        check_decode(rtype(32, 29, 17, 0, 31, 7'h33), ALU_SUB, 0, REG_ALU, 0);
        check_decode(rtype(0, 29, 17, 1, 31, 7'h33), ALU_SLL, 0, REG_ALU, 0);
        check_decode(rtype(0, 29, 17, 2, 31, 7'h33), ALU_SLT, 0, REG_ALU, 0);
        check_decode(rtype(0, 29, 17, 3, 31, 7'h33), ALU_SLTU, 0, REG_ALU, 0);
        check_decode(rtype(0, 29, 17, 4, 31, 7'h33), ALU_XOR, 0, REG_ALU, 0);
        check_decode(rtype(0, 29, 17, 5, 31, 7'h33), ALU_SRL, 0, REG_ALU, 0);
        check_decode(rtype(32, 29, 17, 5, 31, 7'h33), ALU_SRA, 0, REG_ALU, 0);
        check_decode(rtype(0, 29, 17, 6, 31, 7'h33), ALU_OR, 0, REG_ALU, 0);
        check_decode(rtype(0, 29, 17, 7, 31, 7'h33), ALU_AND, 0, REG_ALU, 0);

        // 九条立即数运算。SLTIU 的立即数仍先符号扩展；SRAI 保留编码高位。
        check_decode(itype(-2048, 31, 0, 1, 7'h13), ALU_ADD, 32'hfffff800, IMM_ALU, 0);
        check_decode(itype(2047, 31, 2, 1, 7'h13), ALU_SLT, 2047, IMM_ALU, 0);
        check_decode(itype(-1, 31, 3, 1, 7'h13), ALU_SLTU, 32'hffffffff, IMM_ALU, 0);
        check_decode(itype(-1, 31, 4, 1, 7'h13), ALU_XOR, 32'hffffffff, IMM_ALU, 0);
        check_decode(itype(2047, 31, 6, 1, 7'h13), ALU_OR, 2047, IMM_ALU, 0);
        check_decode(itype(-2048, 31, 7, 1, 7'h13), ALU_AND, 32'hfffff800, IMM_ALU, 0);
        check_decode(itype(31, 31, 1, 1, 7'h13), ALU_SLL, 31, IMM_ALU, 0);
        check_decode(itype(31, 31, 5, 1, 7'h13), ALU_SRL, 31, IMM_ALU, 0);
        check_decode(itype(12'h41f, 31, 5, 1, 7'h13), ALU_SRA, 32'h41f, IMM_ALU, 0);

        // 遍历访存与分支的全部 funct3；合法项检查全部输出，保留项应非法。
        for (f3 = 0; f3 < 8; f3 = f3 + 1) begin
            if (f3 == 0 || f3 == 1 || f3 == 2 || f3 == 4 || f3 == 5)
                check_decode(itype(-2048, 17, f3, 31, 7'h03), ALU_ADD,
                             32'hfffff800, IMM_ALU | READ_MEM, 0);
            else
                check_illegal(itype(0, 17, f3, 31, 7'h03));
            if (f3 < 3)
                check_decode(storetype(-2048, 29, 17, f3), ALU_ADD,
                             32'hfffff800, READ_RS1 | READ_RS2 | USE_IMM | WRITE_MEM, 0);
            else
                check_illegal(storetype(0, 29, 17, f3));
            if (f3 == 0 || f3 == 1 || f3 >= 4) begin
                check_decode(btype(-4096, 29, 17, f3), ALU_ADD,
                             32'hfffff000, READ_RS1 | READ_RS2 | BRANCH, 0);
                check_decode(btype(4094, 29, 17, f3), ALU_ADD,
                             4094, READ_RS1 | READ_RS2 | BRANCH, 0);
            end else begin
                check_illegal(btype(0, 29, 17, f3));
            end
        end

        // U/J 立即数重排和上下界；链接地址的选择由 LINK 控制。
        check_decode(utype(20'h80001, 31, 7'h37), ALU_LUI, 32'h80001000, WRITE_RD | USE_IMM, 0);
        check_decode(utype(20'hfffff, 31, 7'h17), ALU_ADD, 32'hfffff000,
                     WRITE_RD | USE_PC | USE_IMM, 0);
        check_decode(jtype(-1048576, 31), ALU_ADD, 32'hfff00000, WRITE_RD | JUMP | LINK, 0);
        check_decode(jtype(1048574, 31), ALU_ADD, 1048574, WRITE_RD | JUMP | LINK, 0);
        check_decode(itype(-2048, 17, 0, 31, 7'h67), ALU_ADD, 32'hfffff800,
                     IMM_ALU | JUMP | JALR | LINK, 0);
        check_decode(32'h0ff0000f, ALU_ADD, 0, 0, 0); // FENCE 无数据写入。
        check_decode(32'h00000073, ALU_ADD, 0, TRAP, 11); // ECALL。
        check_decode(32'h00100073, ALU_ADD, 0, TRAP, 3); // EBREAK。
        check_decode(rtype(0, 29, 17, 0, 31, 7'h0b), ALU_UADD8SAT, 0, REG_ALU, 0);

        // R 型全部 1024 种 funct7/funct3 组合，不能误接受 M 扩展等其他编码。
        for (f7 = 0; f7 < 128; f7 = f7 + 1) begin
            for (f3 = 0; f3 < 8; f3 = f3 + 1) begin
                instr = rtype(f7, 2, 1, f3, 3, 7'h33);
                #1;
                if (valid !== (f7 == 0 || (f7 == 32 && (f3 == 0 || f3 == 5))))
                    $fatal(1, "R-type legality mismatch: %08x", instr);
                if (!valid && {regwrite, memread, memwrite} !== 3'b000)
                    $fatal(1, "illegal R-type has side-effect controls: %08x", instr);
                checks = checks + 1;
            end
            // 左移仅允许 funct7=0；右移仅允许 0 或 32。
            if (f7 != 0)
                check_illegal(itype(f7 << 5, 1, 1, 3, 7'h13));
            if (f7 != 0 && f7 != 32)
                check_illegal(itype(f7 << 5, 1, 5, 3, 7'h13));
        end
        check_illegal(32'h0000100f); // FENCE.I 属于另一个扩展。
        check_illegal(32'h300110f3); // CSR 指令未实现。
        check_illegal(32'h00200073); // SYSTEM 不能只凭 opcode 接受。
        check_illegal(rtype(1, 2, 1, 0, 3, 7'h0b)); // 定制 funct7 不匹配。
        check_illegal(rtype(0, 2, 1, 1, 3, 7'h0b)); // 定制 funct3 不匹配。
        check_illegal(itype(0, 1, 1, 3, 7'h67)); // JALR 仅允许 funct3=000。
        check_illegal(32'hffffffff);
        check_illegal(32'h00000000);
        $display("PASS: decode controls, immediate boundaries and illegal encodings (%0d checks)", checks);
        $finish;
    end
endmodule
