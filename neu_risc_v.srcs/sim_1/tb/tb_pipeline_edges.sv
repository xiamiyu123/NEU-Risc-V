// 流水线边界回归：同拍旁路、假依赖、load→JALR、错误路径异常、精确终止与中途复位。
`timescale 1ns/1ps
module tb_pipeline_edges;
    reg clk = 0;
    reg rst = 1;
    wire fault, result_valid;
    wire [4:0] fault_cause;
    wire [31:0] fault_pc, fault_tval, debug_pc;
    integer i, stalls = 0;
    reg [31:0] stopped_pc;

    `include "rv32_encode.svh"

    always #5 clk = ~clk;

    rv32_soc dut (
        .clk(clk),
        .rst(rst),
        .fault(fault),
        .fault_cause(fault_cause),
        .fault_pc(fault_pc),
        .fault_tval(fault_tval),
        .debug_pc(debug_pc),
        .result_valid(result_valid)
    );

    // 停顿计数检查时序行为；只检查最终寄存器值无法发现多停或少停一拍。
    always @(posedge clk) begin
        if (rst)
            stalls <= 0;
        else if (dut.core.load_stall)
            stalls <= stalls + 1;
    end

    // fault 表示老指令已排空；此后不应再有写回或写内存。
    always @(negedge clk) begin
        if (!rst && fault && (dut.core.wb_we || dut.core.dmem_we))
            $fatal(1, "side effect after fault");
    end

    task automatic check32(input [31:0] got, expected, input string label);
        if (got !== expected)
            $fatal(1, "%s: got=%08x expected=%08x", label, got, expected);
    endtask

    task automatic clear_case;
        begin
            rst = 1;
            for (i = 0; i < 256; i = i + 1) begin
                dut.imem.mem[i] = jtype(0, 0); // 未使用区域自循环，避免执行到随机指令。
                dut.dmem.mem[i] = 0;
            end
        end
    endtask

    // 所有短程序以预期异常结束；40 拍内不结束即失败，避免测试无限等待。
    task automatic run_to_trap(input [4:0] cause, input [31:0] pc, tval);
        integer cycles;
        begin
            repeat (2) @(negedge clk);
            rst = 0;
            for (cycles = 0; cycles < 40 && !fault; cycles = cycles + 1)
                @(negedge clk);
            check32(fault, 1, "trap reached");
            check32(fault_cause, cause, "trap cause");
            check32(fault_pc, pc, "trap PC");
            check32(fault_tval, tval, "trap value");
            stopped_pc = debug_pc;
            repeat (4) @(negedge clk);
            check32(debug_pc, stopped_pc, "PC held after trap");
            check32(fault, 1, "fault remains asserted");
            check32(fault_cause, cause, "trap cause remains stable");
            check32(fault_pc, pc, "trap PC remains stable");
            check32(fault_tval, tval, "trap value remains stable");
        end
    endtask

    initial begin
        #1;
        // 场景 1：生产者 WB 与消费者 ID 同拍，必须经过寄存器堆旁路。
        clear_case();
        dut.imem.mem[0] = itype(7, 0, 0, 1, 7'h13); // addi x1,x0,7
        dut.imem.mem[1] = itype(1, 0, 0, 10, 7'h13); // 两条无关指令制造所需距离。
        dut.imem.mem[2] = itype(2, 0, 0, 11, 7'h13);
        dut.imem.mem[3] = rtype(0, 1, 1, 0, 2, 7'h33); // add x2,x1,x1 = 14
        dut.imem.mem[4] = 32'h00100073; // ebreak
        run_to_trap(3, 16, 0);
        check32(dut.core.regfile.regs[2], 14, "WB to ID bypass");
        check32(stalls, 0, "ALU dependency needs no stall");

        // 场景 2：ADDI 的立即数低位虽等于 load 的 rd，但不是 rs2，不能误停顿。
        clear_case();
        dut.dmem.mem[0] = 32'h12345678;
        dut.imem.mem[0] = itype(0, 0, 2, 5, 7'h03); // lw x5,0(x0)
        dut.imem.mem[1] = itype(5, 0, 0, 6, 7'h13); // addi x6,x0,5，实际不读取 x5。
        dut.imem.mem[2] = 32'h00100073;
        run_to_trap(3, 8, 0);
        check32(dut.core.regfile.regs[5], 32'h12345678, "load completes before trap");
        check32(dut.core.regfile.regs[6], 5, "independent immediate");
        check32(stalls, 0, "no false rs2 dependency");

        // 场景 3：JALR 直接消费 load；目标 21 清最低位成为 20，只停一拍。
        clear_case();
        dut.dmem.mem[0] = 21;
        dut.dmem.mem[2] = 32'hcafebabe;
        dut.dmem.mem[3] = 32'hdeadbeef;
        dut.imem.mem[0] = itype(0, 0, 2, 1, 7'h03); // lw x1,0(x0)
        dut.imem.mem[1] = itype(0, 1, 0, 2, 7'h67); // jalr x2,0(x1)，链接地址为 8。
        dut.imem.mem[2] = stype(8, 0, 0); // 错误路径的两个 store 均不能生效。
        dut.imem.mem[3] = stype(12, 0, 0);
        dut.imem.mem[5] = itype(9, 0, 0, 3, 7'h13);
        dut.imem.mem[6] = stype(16, 3, 0);
        dut.imem.mem[7] = 32'h00100073;
        run_to_trap(3, 28, 0);
        check32(dut.core.regfile.regs[2], 8, "JALR link");
        check32(dut.dmem.mem[2], 32'hcafebabe, "flush first store");
        check32(dut.dmem.mem[3], 32'hdeadbeef, "flush second store");
        check32(dut.dmem.mem[4], 9, "JALR target executed");
        check32(stalls, 1, "load to JALR stall");

        // 场景 4：跳转冲刷错误路径的非法指令，不能错误地提交该异常。
        clear_case();
        dut.dmem.mem[0] = 32'h11223344;
        dut.imem.mem[0] = jtype(12, 0); // jal x0,+12
        dut.imem.mem[1] = 32'hffffffff; // 错误路径非法指令。
        dut.imem.mem[2] = stype(0, 0, 0); // 错误路径写内存。
        dut.imem.mem[3] = itype(42, 0, 0, 1, 7'h13);
        dut.imem.mem[4] = 32'h00100073;
        run_to_trap(3, 16, 0);
        check32(dut.core.regfile.regs[1], 42, "target survives wrong-path trap");
        check32(dut.dmem.mem[0], 32'h11223344, "wrong-path store suppressed");

        // 场景 5：异常之前的 load/ALU/store 必须完成，之后的写入全部取消。
        clear_case();
        dut.dmem.mem[0] = 32'h89abcdef;
        dut.imem.mem[0] = itype(0, 0, 2, 1, 7'h03);
        dut.imem.mem[1] = itype(17, 0, 0, 2, 7'h13);
        dut.imem.mem[2] = stype(4, 2, 0);
        dut.imem.mem[3] = 32'hffffffff;
        dut.imem.mem[4] = stype(0, 0, 0);
        dut.imem.mem[5] = itype(99, 0, 0, 3, 7'h13);
        run_to_trap(2, 12, 32'hffffffff);
        check32(dut.core.regfile.regs[1], 32'h89abcdef, "older load retired");
        check32(dut.core.regfile.regs[2], 17, "older ALU retired");
        check32(dut.dmem.mem[1], 17, "older store retired");
        check32(dut.dmem.mem[0], 32'h89abcdef, "younger store suppressed");
        check32(dut.core.regfile.regs[3], 0, "younger register write suppressed");

        // 场景 6：未命中分支的未对齐目标不应触发异常；内存最后一个字节可读。
        clear_case();
        dut.dmem.mem[255] = 32'h80ff7f01;
        dut.imem.mem[0] = btype(2, 0, 0, 3'b001); // bne x0,x0,+2，不跳转。
        dut.imem.mem[1] = itype(1023, 0, 4, 1, 7'h03); // lbu x1,1023(x0)
        dut.imem.mem[2] = itype(1022, 0, 1, 2, 7'h03); // lh x2,1022(x0)
        dut.imem.mem[3] = 32'h00100073;
        run_to_trap(3, 12, 0);
        check32(dut.core.regfile.regs[1], 128, "last byte valid");
        check32(dut.core.regfile.regs[2], 32'hffff80ff, "last halfword valid");

        // 场景 7：JALR 清除 bit0 后地址仍未对齐，链接寄存器也不能被改写。
        clear_case();
        dut.imem.mem[0] = itype(3, 0, 0, 1, 7'h13);
        dut.imem.mem[1] = itype(0, 1, 0, 2, 7'h67); // (3 & ~1)=2，未满足 4 字节对齐。
        run_to_trap(0, 4, 2);
        check32(dut.core.regfile.regs[2], 0, "misaligned JALR suppresses link");

        // 场景 8：store 位于 EX 时复位，尚未提交的访存和寄存器状态全部取消。
        clear_case();
        dut.dmem.mem[0] = 32'hcafebabe;
        dut.imem.mem[0] = itype(7, 0, 0, 1, 7'h13);
        dut.imem.mem[1] = stype(0, 1, 0);
        repeat (2) @(negedge clk);
        rst = 0;
        repeat (3) @(negedge clk);
        check32(dut.core.idex_valid && dut.core.idex_memwrite, 1, "store reached EX");
        rst = 1;
        repeat (2) @(negedge clk);
        check32(dut.dmem.mem[0], 32'hcafebabe, "reset cancels in-flight store");
        check32(dut.core.regfile.regs[1], 0, "reset clears register state");
        check32(result_valid, 0, "reset clears result latch");
        dut.imem.mem[0] = 32'h00100073;
        run_to_trap(3, 0, 0);
        check32(dut.dmem.mem[0], 32'hcafebabe, "CPU restarts without stale store");

        $display("PASS: eight pipeline boundary, trap and reset scenarios");
        $finish;
    end
endmodule
