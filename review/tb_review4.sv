// Independent review testbench (v4) - adversarial edge cases.
`timescale 1ns/1ps
module tb_review4;
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
        $display("==== REVIEW TB v4 (adversarial edge cases) ====");

        // ---------- A: load-use feeding a BRANCH (data hazard + control hazard) ----------
        clear_mem();
        dut.dmem.mem[4] = 32'd7;                                       // mem[16]
        dut.imem.mem[0] = itype(16,  0, 3'b010, 1, 7'h03);             // lw   x1,16(x0) -> 7
        dut.imem.mem[1] = itype(7,   0, 3'b000, 2, 7'h13);             // addi x2,x0,7
        dut.imem.mem[2] = btype(8,   2, 1, 3'b000);                    // beq  x1,x2,+8 (needs x1 from load)
        dut.imem.mem[3] = itype(999, 0, 3'b000, 3, 7'h13);             // must be skipped
        dut.imem.mem[4] = itype(55,  0, 3'b000, 4, 7'h13);             // target
        run(40);
        check32(dut.core.regfile.regs[3], 32'd0,  "load-use->branch skips x3");
        check32(dut.core.regfile.regs[4], 32'd55, "load-use->branch target x4=55");

        // ---------- B: store then load same address (memory consistency) ----------
        clear_mem();
        dut.imem.mem[0] = itype('h1AB, 0, 3'b000, 5, 7'h13);           // x5 = 0x1AB
        dut.imem.mem[1] = stype(8,   5, 0);                            // sw   x5,8(x0)
        dut.imem.mem[2] = itype(8,   0, 3'b010, 6, 7'h03);             // lw   x6,8(x0)
        dut.imem.mem[3] = rtype(7'b0, 6, 6, 3'b000, 7, 7'h33);         // add  x7,x6,x6 (load-use)
        run(40);
        check32(dut.core.regfile.regs[6], 32'h1AB, "store->load x6");
        check32(dut.core.regfile.regs[7], 32'h356, "load-use after store x7");

        // ---------- C: x0 as load destination must stay 0 ----------
        clear_mem();
        dut.dmem.mem[2] = 32'hCAFEBABE;
        dut.imem.mem[0] = itype(8,  0, 3'b010, 0, 7'h03);              // lw x0,8(x0)
        dut.imem.mem[1] = itype(3,  0, 3'b000, 1, 7'h13);
        run(30);
        check32(dut.core.regfile.regs[0], 32'd0, "lw to x0 keeps x0=0");

        // ---------- D: uadd8 boundary sweep (0x80+0x80 sat, 'h7F+0x80 sat) ----------
        clear_mem();
        dut.imem.mem[0] = itype(-128, 0, 3'b000, 1, 7'h13);            // x1 = 0xFFFFFF80
        dut.imem.mem[1] = itype(-128, 0, 3'b000, 2, 7'h13);            // x2 = 0xFFFFFF80
        dut.imem.mem[2] = rtype(7'b0, 2, 1, 3'b000, 3, 7'h0b);         // uadd8 -> 0xFFFFFFFF
        dut.imem.mem[3] = itype('h7F, 0, 3'b000, 4, 7'h13);            // x4 = 0x7F
        dut.imem.mem[4] = itype('h01, 0, 3'b000, 5, 7'h13);            // x5 = 0x01
        dut.imem.mem[5] = rtype(7'b0, 5, 4, 3'b000, 6, 7'h0b);         // uadd8 'h7F+1 = 0x80 no sat
        run(40);
        check32(dut.core.regfile.regs[3], 32'hFFFFFFFF, "uadd8 0x80+0x80 saturates");
        check32(dut.core.regfile.regs[6], 32'h00000080, "uadd8 'h7F+1 = 0x80");

        // ---------- E: jalr (extension beyond the 9 baseline) ----------
        clear_mem();
        dut.imem.mem[0] = itype(32, 0, 3'b000, 1, 7'h13);              // x1 = 32 (byte addr of instr 8)
        dut.imem.mem[1] = itype(0,  1, 3'b000, 2, 7'h67);              // jalr x2,x1,0 -> pc=32, link=8
        dut.imem.mem[2] = itype(777,0, 3'b000, 3, 7'h13);              // skipped
        dut.imem.mem[8] = itype(44, 0, 3'b000, 4, 7'h13);              // target
        run(40);
        check32(dut.core.regfile.regs[2], 32'd8,  "jalr link = pc+4 = 8");
        check32(dut.core.regfile.regs[3], 32'd0,  "jalr skips x3");
        check32(dut.core.regfile.regs[4], 32'd44, "jalr target x4=44");

        // ---------- F: back-to-back dependency chain through WB ----------
        clear_mem();
        dut.imem.mem[0] = itype(1, 0, 3'b000, 1, 7'h13);               // x1=1
        dut.imem.mem[1] = itype(2, 0, 3'b000, 2, 7'h13);               // x2=2
        dut.imem.mem[2] = rtype(7'b0, 2, 1, 3'b000, 3, 7'h33);         // x3=x1+x2=3
        dut.imem.mem[3] = rtype(7'b0, 3, 3, 3'b000, 4, 7'h33);         // x4=x3+x3=6
        dut.imem.mem[4] = rtype(7'b0, 4, 3, 3'b000, 5, 7'h33);         // x5=x4+x3=9
        dut.imem.mem[5] = rtype(7'b0, 5, 4, 3'b000, 6, 7'h33);         // x6=x5+x4=15
        run(40);
        check32(dut.core.regfile.regs[6], 32'd15, "4-deep EX-forward chain");

        $display("==== RESULT: %0d checks, %0d errors ====", checks, errors);
        $finish;
    end
endmodule