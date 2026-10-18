// Independent review testbench (v8) - classic store-data hazard + fence/wfi.
`timescale 1ns/1ps
module tb_review8;
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
            if (got !== exp) begin errors = errors + 1; $display("  FAIL %0s: got %08x exp %08x", label, got, exp); end
            else $display("  pass %0s = %08x", label, got);
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
            repeat (2) @(negedge clk); rst = 0;
            repeat (cycles) @(negedge clk);
        end
    endtask

    initial begin
        #1; // 等待存储器 initial 初始化结束，再写入测试程序。
        $display("==== REVIEW TB v8 (store-data hazard / fence) ====");

        // A: lw -> sw (store data comes from a load, load-use on store path)
        clear_mem();
        dut.dmem.mem[8] = 32'h12345678;                                // mem[32]
        dut.imem.mem[0] = itype(32, 0, 3'b010, 1, 7'h03);              // lw  x1,32(x0)
        dut.imem.mem[1] = storetype(64, 1, 0, 3'b010);                 // sw  x1,64(x0)  <- store data hazard
        dut.imem.mem[2] = itype(64, 0, 3'b010, 2, 7'h03);              // lw  x2,64(x0)
        dut.imem.mem[3] = rtype(7'b0, 2, 2, 3'b000, 3, 7'h33);         // add x3,x2,x2
        run(40);
        check32(dut.core.regfile.regs[2], 32'h12345678, "lw->sw->lw value");
        check32(dut.core.regfile.regs[3], 32'h2468ACF0, "use of reloaded value");

        // B: load-use where consumer is another load's address (base reg)
        clear_mem();
        dut.dmem.mem[1] = 32'd32;                                      // mem[4] = 32 (a pointer)
        dut.dmem.mem[8] = 32'hAABBCCDD;
        dut.imem.mem[0] = itype(4,  0, 3'b010, 1, 7'h03);              // lw  x1,4(x0)   -> x1=32
        dut.imem.mem[1] = itype(0,  1, 3'b010, 2, 7'h03);              // lw  x2,0(x1)   <- addr depends on load
        dut.imem.mem[2] = itype(0,  0, 3'b000, 4, 7'h13);              // addi x4,x0,0
        run(40);
        check32(dut.core.regfile.regs[2], 32'hAABBCCDD, "load-use on load base");

        // C: fence (opcode 0001111) must not corrupt state
        clear_mem();
        dut.imem.mem[0] = itype(7, 0, 3'b000, 1, 7'h13);
        dut.imem.mem[1] = 32'h0000000F;                                // fence (rd=0,rs1=0,f3=0)
        dut.imem.mem[2] = itype(9, 0, 3'b000, 2, 7'h13);
        run(40);
        check32(dut.core.regfile.regs[1], 32'd7, "x1 before fence");
        check32(dut.core.regfile.regs[2], 32'd9, "x2 after fence");

        // D: ebreak -> cause 3
        clear_mem();
        dut.imem.mem[0] = 32'h00100073;                                // ebreak
        run(30);
        check32({27'b0, fault_cause}, 32'd3, "ebreak cause=3");

        $display("==== RESULT: %0d checks, %0d errors ====", checks, errors);
        if (errors != 0)
            $fatal(1, "independent review failed: %0d errors", errors);
        $display("PASS: independent review (%0d checks)", checks);
        $finish;
    end
endmodule
