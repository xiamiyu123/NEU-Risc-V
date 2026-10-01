module tb_rv32_soc;
    reg clk = 0;
    reg rst = 1;
    wire fault;
    wire [31:0] debug_pc, retire_data;
    wire [4:0] retire_rd;
    wire retire_valid;
    wire result_valid;
    wire [31:0] result_data;
    integer stalls = 0;
    integer redirects = 0;

    always #5 clk = ~clk;

    rv32_soc dut (
        .clk(clk), .rst(rst), .fault(fault), .debug_pc(debug_pc),
        .retire_valid(retire_valid), .retire_rd(retire_rd),
        .retire_data(retire_data),
        .result_valid(result_valid), .result_data(result_data)
    );

    always @(posedge clk) if (!rst) begin
        if (dut.core.load_stall) stalls = stalls + 1;
        if (dut.core.redirect) redirects = redirects + 1;
    end

    `include "rv32_encode.svh"

    task automatic check32(input [31:0] got, input [31:0] expected,
                           input string label);
        if (got !== expected)
            $fatal(1, "%s: got %08x, expected %08x", label, got, expected);
    endtask

    task automatic clear_memories;
        integer i;
        begin
            for (i = 0; i < 256; i = i + 1) begin
                dut.imem.mem[i] = jtype(0, 0);
                dut.dmem.mem[i] = 0;
            end
            stalls = 0;
            redirects = 0;
        end
    endtask

    task automatic boot;
        begin
            repeat (2) @(negedge clk);
            rst = 0;
        end
    endtask

    initial begin
        #1;
        clear_memories();

        dut.imem.mem[0] = itype(5, 0, 3'b110, 1, 7'h13);     // ori x1,x0,5
        dut.imem.mem[1] = itype(3, 0, 3'b110, 2, 7'h13);
        dut.imem.mem[2] = rtype(0, 2, 1, 3'b000, 3, 7'h33); // add
        dut.imem.mem[3] = rtype(0, 1, 2, 3'b010, 4, 7'h33); // slt
        dut.imem.mem[4] = rtype(0, 1, 2, 3'b011, 5, 7'h33); // sltu
        dut.imem.mem[5] = utype(20'h80000, 6, 7'h37);       // lui
        dut.imem.mem[6] = rtype(7'b0100000, 2, 6, 3'b101, 7, 7'h33);
        dut.imem.mem[7] = rtype(0, 2, 6, 3'b101, 8, 7'h33);
        dut.imem.mem[8] = rtype(0, 2, 1, 3'b001, 9, 7'h33);
        dut.imem.mem[9] = itype(2, 1, 3'b001, 10, 7'h13);
        dut.imem.mem[10] = itype(4, 6, 3'b101, 11, 7'h13);
        dut.imem.mem[11] = itype(12'h404, 6, 3'b101, 12, 7'h13);
        dut.imem.mem[12] = itype(-1, 0, 3'b110, 13, 7'h13);
        dut.imem.mem[13] = rtype(0, 0, 13, 3'b010, 14, 7'h33);
        dut.imem.mem[14] = rtype(0, 0, 13, 3'b011, 15, 7'h33);
        dut.imem.mem[15] = stype(0, 3, 0);
        dut.imem.mem[16] = itype(0, 0, 3'b010, 16, 7'h03);
        dut.imem.mem[17] = rtype(0, 2, 16, 3'b000, 17, 7'h33);
        dut.imem.mem[18] = stype(4, 17, 0);
        dut.imem.mem[19] = itype(4, 0, 3'b010, 18, 7'h03);
        dut.imem.mem[20] = itype(32, 18, 3'b110, 19, 7'h13);
        dut.imem.mem[21] = btype(8, 0, 19, 3'b000);       // beq not taken
        dut.imem.mem[22] = btype(8, 0, 19, 3'b001);       // bne taken
        dut.imem.mem[23] = stype(8, 13, 0);
        dut.imem.mem[24] = btype(8, 2, 13, 3'b100);       // blt taken
        dut.imem.mem[25] = stype(8, 13, 0);
        dut.imem.mem[26] = btype(8, 13, 2, 3'b101);       // bge taken
        dut.imem.mem[27] = stype(8, 13, 0);
        dut.imem.mem[28] = utype(0, 20, 7'h17);           // auipc
        dut.imem.mem[29] = jtype(8, 21);                  // jal
        dut.imem.mem[30] = stype(8, 13, 0);
        dut.imem.mem[31] = rtype(0, 2, 1, 0, 22, 7'h0b); // uadd8sat
        dut.imem.mem[32] = stype(12, 22, 0);
        dut.imem.mem[33] = itype(1, 0, 3'b110, 23, 7'h13);
        dut.imem.mem[34] = itype(2, 23, 3'b110, 23, 7'h13);
        dut.imem.mem[35] = rtype(0, 23, 23, 0, 24, 7'h33);

        boot();
        repeat (85) @(negedge clk);
        check32(dut.core.regs[3], 8, "add");
        check32(dut.core.regs[4], 1, "slt");
        check32(dut.core.regs[5], 1, "sltu");
        check32(dut.core.regs[7], 32'hf0000000, "sra");
        check32(dut.core.regs[8], 32'h10000000, "srl");
        check32(dut.core.regs[9], 40, "sll");
        check32(dut.core.regs[10], 20, "slli");
        check32(dut.core.regs[11], 32'h08000000, "srli");
        check32(dut.core.regs[12], 32'hf8000000, "srai");
        check32(dut.core.regs[13], 32'hffffffff, "ori sign extension");
        check32(dut.core.regs[14], 1, "signed comparison");
        check32(dut.core.regs[15], 0, "unsigned comparison");
        check32(dut.core.regs[17], 11, "load-use add");
        check32(dut.core.regs[19], 43, "load-use ori");
        check32(dut.core.regs[20], 112, "auipc PC");
        check32(dut.core.regs[21], 120, "jal link");
        check32(dut.core.regs[24], 6, "forward priority");
        check32(dut.dmem.mem[0], 8, "store data");
        check32(dut.dmem.mem[1], 11, "store forwarding");
        check32(dut.dmem.mem[2], 0, "flush wrong-path stores");
        check32(dut.dmem.mem[3], 8, "custom result");
        check32(stalls, 2, "load-use stall count");
        check32(fault, 0, "illegal instruction flag");

        rst = 1;
        clear_memories();
        dut.dmem.mem[0] = 32'h102030fa;
        dut.dmem.mem[1] = 32'h01020414;
        dut.imem.mem[0] = itype(0, 0, 3'b010, 1, 7'h03);
        dut.imem.mem[1] = itype(4, 0, 3'b010, 2, 7'h03);
        dut.imem.mem[2] = rtype(0, 2, 1, 0, 3, 7'h0b);
        dut.imem.mem[3] = stype(8, 3, 0);
        dut.imem.mem[4] = btype(8, 2, 1, 3'b101);
        dut.imem.mem[5] = stype(8, 0, 0);
        dut.imem.mem[6] = btype(8, 0, 0, 3'b000);
        dut.imem.mem[7] = stype(8, 0, 0);
        boot();
        repeat (40) @(negedge clk);
        check32(dut.core.regs[3], 32'h112234ff, "saturating packed add");
        check32(dut.dmem.mem[2], 32'h112234ff, "custom store and flush");
        check32(stalls, 1, "custom load-use stall");
        check32(fault, 0, "custom program fault");

        rst = 1;
        clear_memories();
        dut.imem.mem[0] = itype(3, 0, 3'b110, 1, 7'h13);
        dut.imem.mem[1] = itype(-1, 0, 3'b110, 2, 7'h13);
        dut.imem.mem[2] = itype(0, 0, 3'b010, 0, 7'h03);
        dut.imem.mem[3] = rtype(0, 2, 1, 0, 1, 7'h33);
        dut.imem.mem[4] = btype(-4, 0, 1, 3'b001);
        dut.imem.mem[5] = itype(7, 1, 3'b110, 0, 7'h13);
        dut.imem.mem[6] = stype(16, 1, 0);
        boot();
        repeat (50) @(negedge clk);
        check32(dut.core.regs[0], 0, "x0 invariant");
        check32(dut.core.regs[1], 0, "backward branch loop");
        check32(dut.dmem.mem[4], 0, "loop final store");
        check32(stalls, 0, "load x0 does not stall");
        check32(fault, 0, "loop fault");

        rst = 1;
        clear_memories();
        dut.dmem.mem[0] = 32'habcd1234;
        dut.dmem.mem[2] = 32'hcafebabe;
        dut.imem.mem[0] = itype(0, 0, 3'b010, 1, 7'h03);
        dut.imem.mem[1] = stype(4, 1, 0);
        dut.imem.mem[2] = itype(4, 0, 3'b010, 2, 7'h03);
        dut.imem.mem[3] = btype(8, 1, 2, 3'b000);
        dut.imem.mem[4] = stype(8, 0, 0);
        dut.imem.mem[5] = itype(7, 0, 3'b110, 3, 7'h13);
        dut.imem.mem[6] = stype(12, 3, 0);
        boot();
        repeat (40) @(negedge clk);
        check32(dut.dmem.mem[1], 32'habcd1234, "load-to-store forwarding");
        check32(dut.dmem.mem[2], 32'hcafebabe, "load-to-branch flush");
        check32(dut.dmem.mem[3], 7, "branch target execution");
        check32(stalls, 2, "load-to-store and load-to-branch stalls");
        check32(fault, 0, "memory hazard program fault");

        rst = 1;
        clear_memories();
        $readmemh("program/demo.hex", dut.imem.mem);
        boot();
        repeat (25) @(negedge clk);
        check32(result_valid, 1, "demo result flag");
        check32(result_data, 32'h112234ff, "demo result output");
        check32(dut.dmem.mem[0], 32'h112234ff, "demo memory result");
        check32(fault, 0, "demo program fault");

        $display("PASS: instruction, hazard, branch, custom and memory tests");
        $finish;
    end
endmodule
