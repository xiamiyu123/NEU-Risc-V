// Independent review testbench (v6) - sub-word access + traps, corrected.
`timescale 1ns/1ps
module tb_review6;
    reg clk = 0;
    reg rst = 1;
    wire fault;
    wire [4:0] fault_cause;
    wire [31:0] fault_pc, fault_tval;
    wire [31:0] debug_pc, retire_data;
    wire retire_valid;
    wire [4:0] retire_rd;
    integer i;

    always #5 clk = ~clk;

    rv32_soc dut (
        .clk(clk), .rst(rst),
        .fault(fault), .fault_cause(fault_cause),
        .fault_pc(fault_pc), .fault_tval(fault_tval),
        .debug_pc(debug_pc), .retire_valid(retire_valid),
        .retire_rd(retire_rd), .retire_data(retire_data)
    );

    `include "rv32_encode.svh"

    integer errors = 0, checks = 0;
    task automatic check32(input [31:0] got, input [31:0] exp, input string label);
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                $display("  FAIL %0s: got %08x exp %08x", label, got, exp);
            end else $display("  pass %0s = %08x", label, got);
        end
    endtask

    task automatic clear_mem;
        begin
            rst = 1;
            for (i = 0; i < 256; i = i + 1) begin
                dut.imem.mem[i] = itype(0, 0, 3'b000, 0, 7'h13);
                dut.dmem.mem[i] = 0;
            end
        end
    endtask

    task automatic run(input integer cycles);
        begin
            repeat (2) @(negedge clk);
            rst = 0;
            repeat (cycles) @(negedge clk);
        end
    endtask

    initial begin
        #1; // 等待存储器 initial 初始化结束，再写入测试程序。
        $display("==== REVIEW TB v6 (sub-word + traps, corrected) ====");

        // ---------- A: sb then lb/lbu sign extension ----------
        clear_mem();
        dut.imem.mem[0] = itype(-1, 0, 3'b000, 1, 7'h13);                       // x1 = 0xFFFFFFFF
        dut.imem.mem[1] = itype(4,  0, 3'b000, 2, 7'h13);                       // x2 = 4
        dut.imem.mem[2] = storetype(2, 1, 2, 3'b000);                           // sb x1,2(x2)
        dut.imem.mem[3] = itype(2,  2, 3'b000, 4, 7'h03);                       // lb  x4,2(x2)
        dut.imem.mem[4] = itype(2,  2, 3'b100, 5, 7'h03);                       // lbu x5,2(x2)
        run(40);
        check32(dut.core.regfile.regs[4], 32'hFFFFFFFF, "lb sign-extend");
        check32(dut.core.regfile.regs[5], 32'h000000FF, "lbu zero-extend");

        // ---------- A2: sh/lh/lhu halfword ----------
        clear_mem();
        dut.imem.mem[0] = itype(-1, 0, 3'b000, 1, 7'h13);                       // x1 = 0xFFFFFFFF
        dut.imem.mem[1] = itype(4,  0, 3'b000, 2, 7'h13);                       // x2 = 4
        dut.imem.mem[2] = storetype(2, 1, 2, 3'b001);                           // sh x1,2(x2)
        dut.imem.mem[3] = itype(2,  2, 3'b001, 4, 7'h03);                       // lh  x4,2(x2)
        dut.imem.mem[4] = itype(2,  2, 3'b101, 5, 7'h03);                       // lhu x5,2(x2)
        run(40);
        check32(dut.core.regfile.regs[4], 32'hFFFFFFFF, "lh sign-extend");
        check32(dut.core.regfile.regs[5], 32'h0000FFFF, "lhu zero-extend");

        // ---------- B: misaligned word load must trap, cause=4 ----------
        clear_mem();
        dut.imem.mem[0] = itype(1, 0, 3'b000, 1, 7'h13);                        // x1 = 1
        dut.imem.mem[1] = itype(0, 1, 3'b010, 2, 7'h03);                        // lw x2,0(x1) misaligned
        run(30);
        check32({27'b0, fault_cause}, 32'd4, "misaligned load cause=4");
        check32({31'b0, fault}, 32'd1, "fault asserted");

        // ---------- B2: misaligned word store cause=6 ----------
        clear_mem();
        dut.imem.mem[0] = itype(1, 0, 3'b000, 1, 7'h13);
        dut.imem.mem[1] = storetype(0, 1, 1, 3'b010);                           // sw x1,0(x1)
        run(30);
        check32({27'b0, fault_cause}, 32'd6, "misaligned store cause=6");

        // ---------- C: fetch far out of range (word 512 > 256) -> cause=1 ----------
        clear_mem();
        dut.imem.mem[0] = jtype(2044, 0);                                       // jal x0,+2044 -> pc 0x7FC
        run(30);
        check32({27'b0, fault_cause}, 32'd1, "out-of-range fetch cause=1");

        // ---------- D: ecall -> cause=11 ----------
        clear_mem();
        dut.imem.mem[0] = 32'h00000073;
        run(30);
        check32({27'b0, fault_cause}, 32'd11, "ecall cause=11");

        // ---------- E: illegal instruction -> cause=2 ----------
        clear_mem();
        dut.imem.mem[0] = 32'hFFFFFFFF;
        run(30);
        check32({27'b0, fault_cause}, 32'd2, "illegal instr cause=2");

        $display("==== RESULT: %0d checks, %0d errors ====", checks, errors);
        if (errors != 0)
            $fatal(1, "independent review failed: %0d errors", errors);
        $display("PASS: independent review (%0d checks)", checks);
        $finish;
    end
endmodule
