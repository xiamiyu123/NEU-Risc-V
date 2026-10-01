module tb_rv32i;
    reg clk = 0;
    reg rst = 1;
    wire fault;
    wire [4:0] fault_cause;
    wire [31:0] fault_pc, fault_tval;
    integer i;

    always #5 clk = ~clk;

    rv32_soc dut (
        .clk(clk), .rst(rst), .fault(fault),
        .fault_cause(fault_cause), .fault_pc(fault_pc), .fault_tval(fault_tval)
    );

    `include "rv32_encode.svh"

    task automatic check32(input [31:0] got, input [31:0] expected,
                           input string label);
        if (got !== expected)
            $fatal(1, "%s: got %08x, expected %08x", label, got, expected);
    endtask

    task automatic clear_case;
        begin
            rst = 1;
            for (i = 0; i < 256; i = i + 1) begin
                dut.imem.mem[i] = jtype(0, 0);
                dut.dmem.mem[i] = 0;
            end
        end
    endtask

    task automatic run_case(input integer cycles);
        begin
            repeat (2) @(negedge clk);
            rst = 0;
            repeat (cycles) @(negedge clk);
        end
    endtask

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
        clear_case();
        dut.imem.mem[0] = utype(20'h80000, 1, 7'h37);
        dut.imem.mem[1] = itype(-1, 0, 3'b000, 2, 7'h13); // addi
        dut.imem.mem[2] = rtype(7'b0100000, 2, 0, 0, 3, 7'h33); // sub
        dut.imem.mem[3] = itype(0, 2, 3'b010, 4, 7'h13); // slti
        dut.imem.mem[4] = itype(1, 2, 3'b011, 5, 7'h13); // sltiu
        dut.imem.mem[5] = itype(-1, 2, 3'b100, 6, 7'h13); // xori
        dut.imem.mem[6] = itype(8'h55, 2, 3'b111, 7, 7'h13); // andi
        dut.imem.mem[7] = rtype(0, 2, 1, 3'b100, 8, 7'h33); // xor
        dut.imem.mem[8] = rtype(0, 3, 1, 3'b110, 9, 7'h33); // or
        dut.imem.mem[9] = rtype(0, 2, 1, 3'b111, 10, 7'h33); // and
        dut.imem.mem[10] = itype(2047, 3, 0, 11, 7'h13);
        dut.imem.mem[11] = itype(-2048, 3, 0, 12, 7'h13);
        dut.imem.mem[12] = 32'h0ff0000f; // fence iorw,iorw
        dut.imem.mem[13] = 32'h8330000f; // fence.tso
        dut.imem.mem[14] = stype(0, 11, 0);
        run_case(45);
        check32(dut.core.regs[2], 32'hffffffff, "addi negative");
        check32(dut.core.regs[3], 1, "sub");
        check32(dut.core.regs[4], 1, "slti");
        check32(dut.core.regs[5], 0, "sltiu sign-extended immediate");
        check32(dut.core.regs[6], 0, "xori");
        check32(dut.core.regs[7], 32'h55, "andi");
        check32(dut.core.regs[8], 32'h7fffffff, "xor");
        check32(dut.core.regs[9], 32'h80000001, "or");
        check32(dut.core.regs[10], 32'h80000000, "and");
        check32(dut.core.regs[11], 2048, "addi positive limit");
        check32(dut.core.regs[12], 32'hfffff801, "addi negative limit");
        check32(dut.dmem.mem[0], 2048, "fence ordering");
        check32(fault, 0, "arithmetic program fault");

        clear_case();
        dut.dmem.mem[0] = 32'h80ff7f01;
        dut.imem.mem[0] = itype(0, 0, 3'b000, 1, 7'h03); // lb
        dut.imem.mem[1] = itype(1, 0, 3'b000, 2, 7'h03);
        dut.imem.mem[2] = itype(2, 0, 3'b000, 3, 7'h03);
        dut.imem.mem[3] = itype(3, 0, 3'b000, 4, 7'h03);
        dut.imem.mem[4] = itype(2, 0, 3'b100, 5, 7'h03); // lbu
        dut.imem.mem[5] = itype(2, 0, 3'b101, 6, 7'h03); // lhu
        dut.imem.mem[6] = itype(2, 0, 3'b001, 7, 7'h03); // lh
        dut.imem.mem[7] = itype(0, 0, 3'b001, 8, 7'h03);
        dut.imem.mem[8] = itype(-1, 0, 0, 9, 7'h13);
        dut.imem.mem[9] = storetype(1, 9, 0, 3'b000); // sb
        dut.imem.mem[10] = storetype(2, 9, 0, 3'b001); // sh
        dut.imem.mem[11] = stype(4, 9, 0);
        dut.imem.mem[12] = itype(1, 0, 3'b100, 10, 7'h03);
        dut.imem.mem[13] = itype(0, 0, 3'b101, 11, 7'h03);
        run_case(50);
        check32(dut.core.regs[1], 1, "lb lane 0");
        check32(dut.core.regs[2], 127, "lb lane 1");
        check32(dut.core.regs[3], 32'hffffffff, "lb lane 2 sign extension");
        check32(dut.core.regs[4], 32'hffffff80, "lb lane 3 sign extension");
        check32(dut.core.regs[5], 255, "lbu");
        check32(dut.core.regs[6], 32'h80ff, "lhu upper half");
        check32(dut.core.regs[7], 32'hffff80ff, "lh upper half");
        check32(dut.core.regs[8], 32'h7f01, "lh lower half");
        check32(dut.dmem.mem[0], 32'hffffff01, "sb and sh byte lanes");
        check32(dut.dmem.mem[1], 32'hffffffff, "sw after subword stores");
        check32(dut.core.regs[10], 255, "lbu after sb");
        check32(dut.core.regs[11], 32'hff01, "lhu after sh");
        check32(fault, 0, "subword memory program fault");

        clear_case();
        dut.imem.mem[0] = itype(-1, 0, 0, 1, 7'h13);
        dut.imem.mem[1] = itype(1, 0, 0, 2, 7'h13);
        dut.imem.mem[2] = btype(8, 2, 1, 3'b110); // bltu not taken
        dut.imem.mem[3] = btype(8, 2, 1, 3'b111); // bgeu taken
        dut.imem.mem[4] = stype(8, 1, 0);
        dut.imem.mem[5] = btype(8, 1, 2, 3'b110); // bltu taken
        dut.imem.mem[6] = stype(8, 1, 0);
        dut.imem.mem[7] = btype(8, 1, 2, 3'b111); // bgeu not taken
        dut.imem.mem[8] = utype(0, 3, 7'h17);
        dut.imem.mem[9] = itype(53, 0, 0, 4, 7'h13);
        dut.imem.mem[10] = itype(0, 4, 0, 5, 7'h67); // jalr, clear bit 0
        dut.imem.mem[11] = stype(8, 1, 0);
        dut.imem.mem[12] = stype(8, 1, 0);
        dut.imem.mem[13] = itype(7, 0, 0, 6, 7'h13);
        run_case(55);
        check32(dut.core.regs[3], 32, "unsigned branch fall-through");
        check32(dut.core.regs[5], 44, "jalr link");
        check32(dut.core.regs[6], 7, "jalr target");
        check32(dut.dmem.mem[2], 0, "unsigned branch and jalr flush");
        check32(fault, 0, "control program fault");

        clear_case();
        dut.imem.mem[0] = itype(7, 0, 0, 1, 7'h13);
        dut.imem.mem[1] = stype(0, 1, 0);
        dut.imem.mem[2] = 32'h00000073; // ecall
        dut.imem.mem[3] = stype(0, 0, 0);
        run_case(20);
        check_trap(11, 8, 0);
        check32(dut.dmem.mem[0], 7, "older store before ecall");

        clear_case();
        dut.imem.mem[0] = 32'h00100073; // ebreak
        dut.imem.mem[1] = stype(0, 0, 0);
        run_case(15);
        check_trap(3, 0, 0);

        clear_case();
        dut.imem.mem[0] = 32'hffffffff;
        run_case(15);
        check_trap(2, 0, 32'hffffffff);

        clear_case();
        dut.imem.mem[0] = jtype(2, 1);
        run_case(15);
        check_trap(0, 0, 2);
        check32(dut.core.regs[1], 0, "misaligned jal suppresses link");

        clear_case();
        dut.dmem.mem[0] = 32'h12345678;
        dut.imem.mem[0] = itype(18, 0, 0, 1, 7'h13);
        dut.imem.mem[1] = storetype(1, 1, 0, 3'b001);
        run_case(15);
        check_trap(6, 4, 1);
        check32(dut.dmem.mem[0], 32'h12345678, "misaligned store suppressed");

        clear_case();
        dut.imem.mem[0] = itype(1, 0, 3'b001, 1, 7'h03);
        run_case(15);
        check_trap(4, 0, 1);
        check32(dut.core.regs[1], 0, "misaligned load suppressed");

        clear_case();
        dut.imem.mem[0] = itype(1024, 0, 3'b010, 1, 7'h03);
        run_case(15);
        check_trap(5, 0, 1024);

        clear_case();
        dut.imem.mem[0] = storetype(1024, 0, 0, 3'b010);
        run_case(15);
        check_trap(7, 0, 1024);

        clear_case();
        dut.imem.mem[0] = jtype(1024, 0);
        run_case(20);
        check_trap(1, 1024, 1024);

        $display("PASS: complete RV32I instruction and trap tests");
        $finish;
    end
endmodule
