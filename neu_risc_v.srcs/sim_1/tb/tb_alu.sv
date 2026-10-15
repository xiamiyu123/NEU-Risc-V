// ALU 单元测试：定向边界、可复现随机运算，以及饱和加法的全部字节输入对。
`timescale 1ns/1ps
module tb_alu;
    `include "rv32_alu_ops.vh"

    reg [3:0] op;
    reg [31:0] a, b;
    wire [31:0] result;
    reg [31:0] random_state = 32'h13579bdf;
    reg [31:0] left, right;
    integer i, j, checks = 0;

    rv32_alu dut (
        .op(op),
        .a(a),
        .b(b),
        .result(result)
    );

    // 软件参考按整数求和后比较 255，不依赖 RTL 的第 9 位进位判定。
    function automatic [31:0] saturated_sum(input [31:0] x, y);
        integer lane, sum;
        begin
            for (lane = 0; lane < 4; lane = lane + 1) begin
                sum = ((x >> (lane * 8)) & 255) + ((y >> (lane * 8)) & 255);
                saturated_sum[lane*8 +: 8] = sum > 255 ? 255 : sum;
            end
        end
    endfunction

    task automatic check(
        input [3:0] operation,
        input [31:0] x, y, expected,
        input string label
    );
        begin
            op = operation;
            a = x;
            b = y;
            #1; // 组合逻辑稳定后检查，!== 同时把 X/Z 视为失败。
            if (result !== expected)
                $fatal(1, "%s: a=%08x b=%08x got=%08x expected=%08x",
                       label, a, b, result, expected);
            checks = checks + 1;
        end
    endtask

    initial begin
        // RV32I 的整数加减按 32 位回绕，不产生算术溢出异常。
        check(ALU_ADD, 32'hffffffff, 1, 0, "add wrap");
        check(ALU_SUB, 0, 1, 32'hffffffff, "sub wrap");
        check(ALU_SLT, 32'h80000000, 32'h7fffffff, 1, "signed minimum");
        check(ALU_SLTU, 32'h80000000, 32'h7fffffff, 0, "unsigned ordering");
        check(ALU_SRA, 32'h80000000, 31, 32'hffffffff, "arithmetic sign fill");
        check(ALU_SRL, 32'h80000000, 31, 1, "logical zero fill");
        check(ALU_SLL, 1, 31, 32'h80000000, "left shift maximum");
        check(ALU_SLL, 1, 32, 1, "shift ignores high bits");
        check(ALU_SRA, 32'h80000000, 63, 32'hffffffff, "shift low five bits");
        check(ALU_UADD8SAT, 32'h102030fa, 32'h01020414, 32'h112234ff,
              "mixed byte saturation");
        check(ALU_UADD8SAT, 32'h7f7f7f7f, 32'h80808080, 32'hffffffff,
              "sum exactly 255");
        check(ALU_UADD8SAT, 32'h80808080, 32'h80808080, 32'hffffffff,
              "sum exactly 256");

        // 每个合法移位量均检查一次，并令高位非零以确认只取低 5 位。
        for (j = 0; j < 32; j = j + 1) begin
            check(ALU_SLL, 32'h89abcdef, j + 32, 32'h89abcdef << j, "all SLL amounts");
            check(ALU_SRL, 32'h89abcdef, j + 32, 32'h89abcdef >> j, "all SRL amounts");
            check(ALU_SRA, 32'h89abcdef, j + 32,
                  $signed(32'h89abcdef) >>> j, "all SRA amounts");
        end

        // 固定种子的线性同余序列；每次运行获得相同的 1024 对操作数。
        for (i = 0; i < 1024; i = i + 1) begin
            random_state = random_state * 32'd1664525 + 32'd1013904223;
            left = random_state;
            random_state = random_state * 32'd1664525 + 32'd1013904223;
            right = random_state;
            check(ALU_ADD, left, right, left + right, "random add");
            check(ALU_SUB, left, right, left - right, "random sub");
            check(ALU_SLT, left, right, $signed(left) < $signed(right), "random slt");
            check(ALU_SLTU, left, right, left < right, "random sltu");
            check(ALU_XOR, left, right, left ^ right, "random xor");
            check(ALU_OR, left, right, left | right, "random or");
            check(ALU_AND, left, right, left & right, "random and");
            check(ALU_LUI, left, right, right, "lui operand selection");
            check(ALU_SLL, left, right, left << right[4:0], "random sll");
            check(ALU_SRL, left, right, left >> right[4:0], "random srl");
            check(ALU_SRA, left, right, $signed(left) >>> right[4:0], "random sra");
            check(ALU_UADD8SAT, left, right, saturated_sum(left, right), "random saturation");
        end

        // 每个 lane 都遍历 256×256 对字节；互补值使相邻 lane 的溢出情况不同。
        for (i = 0; i < 256; i = i + 1) begin
            for (j = 0; j < 256; j = j + 1) begin
                left = {i[7:0], ~i[7:0], i[7:0], j[7:0]};
                right = {j[7:0], j[7:0], ~j[7:0], i[7:0]};
                check(ALU_UADD8SAT, left, right, saturated_sum(left, right),
                      "exhaustive byte pairs");
            end
        end
        $display("PASS: ALU boundaries, random vectors and byte pairs (%0d checks)", checks);
        $finish;
    end
endmodule
