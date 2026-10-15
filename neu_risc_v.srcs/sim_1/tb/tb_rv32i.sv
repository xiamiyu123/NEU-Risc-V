// RV32I 回归：每组短程序复位隔离，核对架构结果和终止异常信息。
`timescale 1ns/1ps
module tb_rv32i;
    reg clk = 0;
    reg rst = 1;
    wire fault;
    wire [4:0] fault_cause;
    wire [31:0] fault_pc, fault_tval;
    integer i;

    always #5 clk = ~clk;

    rv32_soc dut (
        .clk(clk),
        .rst(rst),
        .fault(fault),
        .fault_cause(fault_cause),
        .fault_pc(fault_pc),
        .fault_tval(fault_tval)
    );

    `include "rv32_encode.svh"

    // 严格比较 32 位结果，X/Z 也算失败；label 指明失败功能。
    task automatic check32(input [31:0] got, input [31:0] expected,
                           input string label);
        if (got !== expected)
            $fatal(1, "%s: got %08x, expected %08x", label, got, expected);
    endtask

    // 初始化测试内存；未使用的指令填为 jal x0,0，避免顺序落入非法零指令。
    task automatic clear_case;
        begin
            rst = 1;
            for (i = 0; i < 256; i = i + 1) begin
                dut.imem.mem[i] = jtype(0, 0);
                dut.dmem.mem[i] = 0;
            end
        end
    endtask

    // 在下降沿释放复位并等待足够流水周期；随后检查最终架构状态。
    task automatic run_case(input integer cycles);
        begin
            repeat (2) @(negedge clk);
            rst = 0;
            repeat (cycles) @(negedge clk);
        end
    endtask

    // 异常必须同时满足有效标志、原因、故障 PC 和附加值四个条件。
    task automatic check_trap(input [4:0] cause, input [31:0] pc,
                              input [31:0] tval);
        begin
            check32(fault, 1, "trap reported");
            check32(fault_cause, cause, "trap cause");
            check32(fault_pc, pc, "trap PC");
            check32(fault_tval, tval, "trap value");
        end
    endtask

    initial begin
        #1;
        // 整数逻辑与立即数：检查负数、±12 位边界、位运算，以及 FENCE 后访问顺序。
        clear_case();
        dut.imem.mem[0] = utype(20'h80000, 1, 7'h37); // lui x1,0x80000
        dut.imem.mem[1] = itype(-1, 0, 3'b000, 2, 7'h13); // addi x2,x0,-1
        dut.imem.mem[2] = rtype(7'b0100000, 2, 0, 0, 3, 7'h33); // sub x3,x0,x2
        dut.imem.mem[3] = itype(0, 2, 3'b010, 4, 7'h13); // slti x4,x2,0
        dut.imem.mem[4] = itype(1, 2, 3'b011, 5, 7'h13); // sltiu x5,x2,1
        dut.imem.mem[5] = itype(-1, 2, 3'b100, 6, 7'h13); // xori x6,x2,-1
        dut.imem.mem[6] = itype(8'h55, 2, 3'b111, 7, 7'h13); // andi x7,x2,85
        dut.imem.mem[7] = rtype(0, 2, 1, 3'b100, 8, 7'h33); // xor x8,x1,x2
        dut.imem.mem[8] = rtype(0, 3, 1, 3'b110, 9, 7'h33); // or x9,x1,x3
        dut.imem.mem[9] = rtype(0, 2, 1, 3'b111, 10, 7'h33); // and x10,x1,x2
        dut.imem.mem[10] = itype(2047, 3, 0, 11, 7'h13); // addi x11,x3,2047
        dut.imem.mem[11] = itype(-2048, 3, 0, 12, 7'h13); // addi x12,x3,-2048
        dut.imem.mem[12] = 32'h0ff0000f; // fence iorw,iorw：内存顺序屏障
        dut.imem.mem[13] = 32'h8330000f; // fence.tso：本存储模型中无额外动作
        dut.imem.mem[14] = stype(0, 11, 0); // sw x11,0(x0)
        run_case(45);
        check32(dut.core.regfile.regs[2], 32'hffffffff, "addi negative");
        check32(dut.core.regfile.regs[3], 1, "sub");
        check32(dut.core.regfile.regs[4], 1, "slti");
        check32(dut.core.regfile.regs[5], 0, "sltiu sign-extended immediate");
        check32(dut.core.regfile.regs[6], 0, "xori");
        check32(dut.core.regfile.regs[7], 32'h55, "andi");
        check32(dut.core.regfile.regs[8], 32'h7fffffff, "xor");
        check32(dut.core.regfile.regs[9], 32'h80000001, "or");
        check32(dut.core.regfile.regs[10], 32'h80000000, "and");
        check32(dut.core.regfile.regs[11], 2048, "addi positive limit");
        check32(dut.core.regfile.regs[12], 32'hfffff801, "addi negative limit");
        check32(dut.dmem.mem[0], 2048, "fence ordering");
        check32(fault, 0, "arithmetic program fault");

        // 子字访存：按小端顺序检查四个字节、符号/零扩展、部分写与重读。
        clear_case();
        dut.dmem.mem[0] = 32'h80ff7f01;
        dut.imem.mem[0] = itype(0, 0, 3'b000, 1, 7'h03); // lb x1,0(x0)
        dut.imem.mem[1] = itype(1, 0, 3'b000, 2, 7'h03); // lb x2,1(x0)
        dut.imem.mem[2] = itype(2, 0, 3'b000, 3, 7'h03); // lb x3,2(x0)
        dut.imem.mem[3] = itype(3, 0, 3'b000, 4, 7'h03); // lb x4,3(x0)
        dut.imem.mem[4] = itype(2, 0, 3'b100, 5, 7'h03); // lbu x5,2(x0)
        dut.imem.mem[5] = itype(2, 0, 3'b101, 6, 7'h03); // lhu x6,2(x0)
        dut.imem.mem[6] = itype(2, 0, 3'b001, 7, 7'h03); // lh x7,2(x0)
        dut.imem.mem[7] = itype(0, 0, 3'b001, 8, 7'h03); // lh x8,0(x0)
        dut.imem.mem[8] = itype(-1, 0, 0, 9, 7'h13); // addi x9,x0,-1
        dut.imem.mem[9] = storetype(1, 9, 0, 3'b000); // sb x9,1(x0)
        dut.imem.mem[10] = storetype(2, 9, 0, 3'b001); // sh x9,2(x0)
        dut.imem.mem[11] = stype(4, 9, 0); // sw x9,4(x0)
        dut.imem.mem[12] = itype(1, 0, 3'b100, 10, 7'h03); // lbu x10,1(x0)
        dut.imem.mem[13] = itype(0, 0, 3'b101, 11, 7'h03); // lhu x11,0(x0)
        run_case(50);
        check32(dut.core.regfile.regs[1], 1, "lb lane 0");
        check32(dut.core.regfile.regs[2], 127, "lb lane 1");
        check32(dut.core.regfile.regs[3], 32'hffffffff, "lb lane 2 sign extension");
        check32(dut.core.regfile.regs[4], 32'hffffff80, "lb lane 3 sign extension");
        check32(dut.core.regfile.regs[5], 255, "lbu");
        check32(dut.core.regfile.regs[6], 32'h80ff, "lhu upper half");
        check32(dut.core.regfile.regs[7], 32'hffff80ff, "lh upper half");
        check32(dut.core.regfile.regs[8], 32'h7f01, "lh lower half");
        check32(dut.dmem.mem[0], 32'hffffff01, "sb and sh byte lanes");
        check32(dut.dmem.mem[1], 32'hffffffff, "sw after subword stores");
        check32(dut.core.regfile.regs[10], 255, "lbu after sb");
        check32(dut.core.regfile.regs[11], 32'hff01, "lhu after sh");
        check32(fault, 0, "subword memory program fault");

        // 控制流：无符号分支取/不取两种方向，以及 JALR 的 bit0 清除与链接值。
        clear_case();
        dut.imem.mem[0] = itype(-1, 0, 0, 1, 7'h13); // addi x1,x0,-1
        dut.imem.mem[1] = itype(1, 0, 0, 2, 7'h13); // addi x2,x0,1
        dut.imem.mem[2] = btype(8, 2, 1, 3'b110); // bltu not taken；bltu x1,x2,+8
        dut.imem.mem[3] = btype(8, 2, 1, 3'b111); // bgeu taken；bgeu x1,x2,+8
        dut.imem.mem[4] = stype(8, 1, 0); // sw x1,8(x0)
        dut.imem.mem[5] = btype(8, 1, 2, 3'b110); // bltu taken；bltu x2,x1,+8
        dut.imem.mem[6] = stype(8, 1, 0); // sw x1,8(x0)
        dut.imem.mem[7] = btype(8, 1, 2, 3'b111); // bgeu not taken；bgeu x2,x1,+8
        dut.imem.mem[8] = utype(0, 3, 7'h17); // auipc x3,0x0
        dut.imem.mem[9] = itype(53, 0, 0, 4, 7'h13); // addi x4,x0,53
        dut.imem.mem[10] = itype(0, 4, 0, 5, 7'h67); // jalr, clear bit 0；jalr x5,0(x4)
        dut.imem.mem[11] = stype(8, 1, 0); // sw x1,8(x0)
        dut.imem.mem[12] = stype(8, 1, 0); // sw x1,8(x0)
        dut.imem.mem[13] = itype(7, 0, 0, 6, 7'h13); // addi x6,x0,7
        run_case(55);
        check32(dut.core.regfile.regs[3], 32, "unsigned branch fall-through");
        check32(dut.core.regfile.regs[5], 44, "jalr link");
        check32(dut.core.regfile.regs[6], 7, "jalr target");
        check32(dut.dmem.mem[2], 0, "unsigned branch and jalr flush");
        check32(fault, 0, "control program fault");

        // ECALL：之前的 store 必须提交，之后的 store 必须取消。
        clear_case();
        dut.imem.mem[0] = itype(7, 0, 0, 1, 7'h13); // addi x1,x0,7
        dut.imem.mem[1] = stype(0, 1, 0); // sw x1,0(x0)
        dut.imem.mem[2] = 32'h00000073; // ecall：终止并报告环境调用
        dut.imem.mem[3] = stype(0, 0, 0); // sw x0,0(x0)
        run_case(20);
        check_trap(11, 8, 0);
        check32(dut.dmem.mem[0], 7, "older store before ecall");

        // EBREAK：报告 cause=3、PC=0，不执行其后面的 store。
        clear_case();
        dut.imem.mem[0] = 32'h00100073; // ebreak：终止并报告断点
        dut.imem.mem[1] = stype(0, 0, 0); // sw x0,0(x0)
        run_case(15);
        check_trap(3, 0, 0);

        // 非法指令：保存原始机器码到 fault_tval。
        clear_case();
        dut.imem.mem[0] = 32'hffffffff; // 非法指令：用于检查异常
        run_case(15);
        check_trap(2, 0, 32'hffffffff);

        // 未对齐 JAL：目标=2 不满足 4 字节对齐，禁止链接寄存器写回。
        clear_case();
        dut.imem.mem[0] = jtype(2, 1); // jal x1,+2
        run_case(15);
        check_trap(0, 0, 2);
        check32(dut.core.regfile.regs[1], 0, "misaligned jal suppresses link");

        // 未对齐 SH：奇地址存半字必须异常，原始内存保持不变。
        clear_case();
        dut.dmem.mem[0] = 32'h12345678;
        dut.imem.mem[0] = itype(18, 0, 0, 1, 7'h13); // addi x1,x0,18
        dut.imem.mem[1] = storetype(1, 1, 0, 3'b001); // sh x1,1(x0)
        run_case(15);
        check_trap(6, 4, 1);
        check32(dut.dmem.mem[0], 32'h12345678, "misaligned store suppressed");

        // 未对齐 LH：奇地址读半字必须异常，目标寄存器保持不变。
        clear_case();
        dut.imem.mem[0] = itype(1, 0, 3'b001, 1, 7'h03); // lh x1,1(x0)
        run_case(15);
        check_trap(4, 0, 1);
        check32(dut.core.regfile.regs[1], 0, "misaligned load suppressed");

        // 越界 LW：1 KiB 存储器的地址 1024 不可读，报告加载访问故障。
        clear_case();
        dut.imem.mem[0] = itype(1024, 0, 3'b010, 1, 7'h03); // lw x1,1024(x0)
        run_case(15);
        check_trap(5, 0, 1024);

        // 越界 SW：地址 1024 不可写，报告存储访问故障。
        clear_case();
        dut.imem.mem[0] = storetype(1024, 0, 0, 3'b010); // sw x0,1024(x0)
        run_case(15);
        check_trap(7, 0, 1024);

        // 越界取指：跳转地址 1024 后报告该目标地址的取指访问故障。
        clear_case();
        dut.imem.mem[0] = jtype(1024, 0); // jal x0,+1024
        run_case(20);
        check_trap(1, 1024, 1024);

        $display("PASS: complete RV32I instruction and trap tests");
        $finish;
    end
endmodule
