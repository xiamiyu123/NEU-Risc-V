// Independent review testbench (v7) - remaining RV32I ops not yet covered.
`timescale 1ns/1ps
module tb_review7;
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
        $display("==== REVIEW TB v7 (remaining RV32I ops) ====");
        clear_mem();
        // xor, and, slt, slti, sltiu, srli, srai, auipc, bge, bgeu, bltu
        dut.imem.mem[0]  = itype(-1, 0, 3'b000, 1, 7'h13);                       // x1=-1
        dut.imem.mem[1]  = itype(5,  0, 3'b000, 2, 7'h13);                       // x2=5
        dut.imem.mem[2]  = rtype(7'b0, 2, 1, 3'b100, 3, 7'h33);                  // xor x3,x1,x2 = FFFFFFFA
        dut.imem.mem[3]  = rtype(7'b0, 2, 1, 3'b111, 4, 7'h33);                  // and x4,x1,x2 = 5
        dut.imem.mem[4]  = rtype(7'b0, 2, 1, 3'b010, 5, 7'h33);                  // slt x5,x1,x2 = 1
        dut.imem.mem[5]  = itype(9, 2, 3'b010, 6, 7'h13);                        // slti x6,x2,9 = 1
        dut.imem.mem[6]  = itype(9, 2, 3'b011, 7, 7'h13);                        // sltiu x7,x2,9 = 1
        dut.imem.mem[7]  = itype(-16, 0, 3'b000, 8, 7'h13);                      // x8 = 0xFFFFFFF0
        dut.imem.mem[8]  = itype(4, 8, 3'b101, 9, 7'h13);                        // srli x9,x8,4 = 0x0FFFFFFF
        dut.imem.mem[9]  = itype(4|(1<<10), 8, 3'b101, 10, 7'h13);               // srai (imm[10]=1) x10,x8,4 = FFFFFFFF
        dut.imem.mem[10] = utype(20'h100, 11, 7'h17);                            // auipc x11,0x100 -> 0x100000+40
        run(60);
        check32(dut.core.regfile.regs[3],  32'hFFFFFFFA, "xor");
        check32(dut.core.regfile.regs[4],  32'd5,        "and");
        check32(dut.core.regfile.regs[5],  32'd1,        "slt");
        check32(dut.core.regfile.regs[6],  32'd1,        "slti");
        check32(dut.core.regfile.regs[7],  32'd1,        "sltiu");
        check32(dut.core.regfile.regs[9],  32'h0FFFFFFF, "srli");
        check32(dut.core.regfile.regs[10], 32'hFFFFFFFF, "srai");
        check32(dut.core.regfile.regs[11], 32'h00100028, "auipc (pc=0x28)");

        // unsigned branch variants
        clear_mem();
        dut.imem.mem[0] = itype(-1, 0, 3'b000, 1, 7'h13);                        // x1 = -1 (unsigned HUGE)
        dut.imem.mem[1] = itype(1,  0, 3'b000, 2, 7'h13);                        // x2 = 1
        dut.imem.mem[2] = btype(8, 2, 1, 3'b110);                                // bltu x1,x2 -> NOT taken (HUGE>1)
        dut.imem.mem[3] = itype(11, 0, 3'b000, 3, 7'h13);                        // executed
        dut.imem.mem[4] = btype(8, 2, 1, 3'b001);                                // bne x1,x2 -> taken to 6
        dut.imem.mem[5] = itype(99, 0, 3'b000, 4, 7'h13);                        // skipped
        dut.imem.mem[6] = btype(8, 2, 1, 3'b111);                                // bgeu x1,x2 -> taken (HUGE>=1) to 8
        dut.imem.mem[7] = itype(88, 0, 3'b000, 5, 7'h13);                        // skipped
        dut.imem.mem[8] = itype(7,  0, 3'b000, 6, 7'h13);                        // target
        run(50);
        check32(dut.core.regfile.regs[3], 32'd11, "bltu not-taken (unsigned)");
        check32(dut.core.regfile.regs[4], 32'd0,  "bne taken skips x4");
        check32(dut.core.regfile.regs[5], 32'd0,  "bgeu taken skips x5");
        check32(dut.core.regfile.regs[6], 32'd7,  "bgeu target x6");

        $display("==== RESULT: %0d checks, %0d errors ====", checks, errors);
        $finish;
    end
endmodule