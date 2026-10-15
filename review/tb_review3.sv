// Independent review testbench (v3) - uses the real SoC with synchronous memory.
// Written by the reviewer for acceptance checking; NOT part of the hand-in.
`timescale 1ns/1ps
module tb_review3;
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
                dut.imem.mem[i] = itype(0, 0, 3'b000, 0, 7'h13); // NOP: addi x0,x0,0
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
        $display("==== REVIEW TB v3 (real SoC, synchronous memory) ====");

        // ---------- A: load-use hazard with NO independent instruction between ----------
        clear_mem();
        dut.dmem.mem[0] = 32'd100;
        dut.imem.mem[0] = itype(0,   0, 3'b010, 1, 7'h03);            // lw   x1,0(x0)
        dut.imem.mem[1] = rtype(7'b0, 1, 1, 3'b000, 2, 7'h33);        // add  x2,x1,x1
        dut.imem.mem[2] = rtype(7'b0, 1, 2, 3'b000, 3, 7'h33);        // add  x3,x2,x1
        dut.imem.mem[3] = itype(1,   0, 3'b000, 4, 7'h13);            // addi x4,x0,1
        run(40);
        check32(dut.core.regfile.regs[2], 32'd200, "load-use x2 = 200");
        check32(dut.core.regfile.regs[3], 32'd300, "ex/forward chain x3 = 300");
        check32(dut.core.regfile.regs[4], 32'd1,   "x4 = 1");

        // ---------- B: branch direction taken / not-taken ----------
        clear_mem();
        dut.imem.mem[0] = itype(5,   0, 3'b000, 1, 7'h13);            // addi x1,x0,5
        dut.imem.mem[1] = itype(5,   0, 3'b000, 2, 7'h13);            // addi x2,x0,5
        dut.imem.mem[2] = btype(8,   2, 1, 3'b001);                   // bne x1,x2,+8 -> NOT taken
        dut.imem.mem[3] = itype(111, 0, 3'b000, 3, 7'h13);            // addi x3,x0,111 (executed)
        dut.imem.mem[4] = btype(8,   2, 1, 3'b000);                   // beq x1,x2,+8 -> taken to 6
        dut.imem.mem[5] = itype(999, 0, 3'b000, 5, 7'h13);            // skipped
        dut.imem.mem[6] = itype(77,  0, 3'b000, 6, 7'h13);            // target
        run(40);
        check32(dut.core.regfile.regs[3], 32'd111, "bne not-taken x3=111");
        check32(dut.core.regfile.regs[5], 32'd0,   "beq taken -> x5 still 0");
        check32(dut.core.regfile.regs[6], 32'd77,  "beq target x6=77");

        // ---------- C: jal link value + x0 hardwired ----------
        clear_mem();
        dut.imem.mem[0] = jtype(12, 7);                                // jal x7,+12 -> pc 0x0C, link=4
        dut.imem.mem[1] = itype(888, 0, 3'b000, 8, 7'h13);             // skipped
        dut.imem.mem[2] = itype(999, 0, 3'b000, 9, 7'h13);             // skipped
        dut.imem.mem[3] = rtype(7'b0, 6, 6, 3'b000, 0, 7'h33);         // add x0,x6,x6
        dut.imem.mem[4] = itype(1,   0, 3'b000, 10, 7'h13);
        run(40);
        check32(dut.core.regfile.regs[7], 32'd4, "jal link x7 = pc+4 = 4");
        check32(dut.core.regfile.regs[8], 32'd0, "jal skips x8");
        check32(dut.core.regfile.regs[0], 32'd0, "x0 stays 0");

        // ---------- D: uadd8.sat saturation semantics ----------
        clear_mem();
        dut.imem.mem[0] = utype(20'hFFFFF, 1, 7'h37);                  // lui  x1,0xFFFFF -> 0xFFFFF000
        dut.imem.mem[1] = itype(-1, 1, 3'b110, 1, 7'h13);              // ori  x1,x1,-1 -> 0xFFFFFFFF
        dut.imem.mem[2] = itype(1,  0, 3'b000, 2, 7'h13);              // addi x2,x0,1
        dut.imem.mem[3] = rtype(7'b0, 2, 1, 3'b000, 3, 7'h0b);         // uadd8 x3,x1,x2 -> all saturate
        dut.imem.mem[4] = itype(127,0, 3'b000, 4, 7'h13);              // x4 = 0x7F
        dut.imem.mem[5] = rtype(7'b0, 2, 4, 3'b000, 6, 7'h0b);         // uadd8 x6,x4,x2 -> 0x80 (no sat)
        dut.imem.mem[6] = rtype(7'b0, 2, 4, 3'b000, 5, 7'h0b);         // (placeholder)
        run(40);
        check32(dut.core.regfile.regs[3], 32'hFFFFFFFF, "uadd8 all bytes saturate");
        check32(dut.core.regfile.regs[6], 32'h00000080, "uadd8 127+1 = 128 no saturation");

        // ---------- E: shift / sltu extension sanity ----------
        clear_mem();
        dut.imem.mem[0] = itype(-1, 0, 3'b000, 1, 7'h13);              // x1 = 0xFFFFFFFF
        dut.imem.mem[1] = itype(4,  0, 3'b000, 2, 7'h13);              // x2 = 4
        dut.imem.mem[2] = rtype(7'b0,      2, 1, 3'b001, 3, 7'h33);    // sll  x3,x1,x2
        dut.imem.mem[3] = rtype(7'b0100000,2, 1, 3'b101, 4, 7'h33);    // sra  x4,x1,x2
        dut.imem.mem[4] = rtype(7'b0,      1, 2, 3'b011, 5, 7'h33);    // sltu x5,x2,x1
        run(40);
        check32(dut.core.regfile.regs[3], 32'hFFFFFFF0, "sll x3");
        check32(dut.core.regfile.regs[4], 32'hFFFFFFFF, "sra x4");
        check32(dut.core.regfile.regs[5], 32'd1,        "sltu x5");

        $display("==== RESULT: %0d checks, %0d errors ====", checks, errors);
        $finish;
    end
endmodule