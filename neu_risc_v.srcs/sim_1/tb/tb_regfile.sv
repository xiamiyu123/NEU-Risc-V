// 寄存器堆单元测试：覆盖全部寄存器、两路旁路、写使能、x0 和复位优先级。
`timescale 1ns/1ps
module tb_regfile;
    reg clk = 0;
    reg rst = 1;
    reg we = 0;
    reg [4:0] rs1 = 0, rs2 = 0, rd = 0;
    reg [31:0] wdata = 0;
    wire [31:0] rdata1, rdata2;
    integer i;

    always #5 clk = ~clk;

    rv32_regfile dut (
        .clk(clk),
        .rst(rst),
        .rs1(rs1),
        .rs2(rs2),
        .we(we),
        .rd(rd),
        .wdata(wdata),
        .rdata1(rdata1),
        .rdata2(rdata2)
    );

    task automatic check_reads(input [31:0] expected1, expected2);
        begin
            #1;
            if (rdata1 !== expected1 || rdata2 !== expected2)
                $fatal(1, "regfile: rs1=%0d got=%08x expected=%08x; rs2=%0d got=%08x expected=%08x",
                       rs1, rdata1, expected1, rs2, rdata2, expected2);
        end
    endtask

    initial begin
        repeat (2) @(negedge clk);
        rst = 0;
        // 复位后逐个读取；两个端口以相反次序遍历所有寄存器。
        for (i = 0; i < 32; i = i + 1) begin
            rs1 = i;
            rs2 = 31 - i;
            check_reads(0, 0);
        end

        for (i = 1; i < 32; i = i + 1) begin
            @(negedge clk);
            we = 1;
            rd = i;
            rs1 = i;
            rs2 = i;
            wdata = 32'h12340000 + i;
            // 上升沿之前应已旁路到两个读端口。
            check_reads(wdata, wdata);
            @(negedge clk);
            we = 0;
            // 关闭写使能后依然读到新值，证明数据已写入存储单元。
            check_reads(32'h12340000 + i, 32'h12340000 + i);
        end

        // 全部写完后交叉读回，防止不同寄存器号错误地指向同一存储位置。
        for (i = 1; i < 32; i = i + 1) begin
            rs1 = i;
            rs2 = 32 - i;
            check_reads(32'h12340000 + i, 32'h12340000 + 32 - i);
        end

        // 写其他寄存器时，不相关读端保持原值。
        @(negedge clk);
        rd = 5;
        rs1 = 5;
        rs2 = 31;
        wdata = 32'hcafebabe;
        we = 1;
        check_reads(32'hcafebabe, 32'h1234001f);
        @(negedge clk);
        we = 0;
        wdata = 32'hdeadbeef;
        repeat (2) @(negedge clk);
        check_reads(32'hcafebabe, 32'h1234001f);

        // x0 的读取和存储状态均保持零，不能被写入或旁路覆盖。
        rd = 0;
        rs1 = 0;
        rs2 = 0;
        we = 1;
        check_reads(0, 0);
        @(negedge clk);
        we = 0;
        check_reads(0, 0);
        if (dut.regs[0] !== 0)
            $fatal(1, "x0 storage changed");

        // 复位与写使能同时有效，复位必须胜出并清零所有寄存器。
        rst = 1;
        we = 1;
        rd = 31;
        @(negedge clk);
        we = 0;
        rst = 0;
        for (i = 0; i < 32; i = i + 1) begin
            rs1 = i;
            rs2 = 31 - i;
            check_reads(0, 0);
        end
        $display("PASS: regfile reset, all registers, bypass, write enable and x0");
        $finish;
    end
endmodule
