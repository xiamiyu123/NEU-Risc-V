// 存储器单元测试：同步读、关闭读使能时保持输出、字节写与同址读写语义。
`timescale 1ns/1ps
module tb_memory;
    reg clk = 0;
    reg re = 0, we = 0;
    reg [3:0] wstrb = 0;
    reg [31:0] addr = 0, wdata = 0;
    wire [31:0] rdata;
    integer lane;

    always #5 clk = ~clk;

    rv32_sync_mem dut (
        .clk(clk),
        .re(re),
        .we(we),
        .wstrb(wstrb),
        .addr(addr),
        .wdata(wdata),
        .rdata(rdata)
    );

    task automatic check_data(input [31:0] expected, input string label);
        if (rdata !== expected)
            $fatal(1, "%s: got=%08x expected=%08x", label, rdata, expected);
    endtask

    // 输入在下降沿之后改变；等待上升沿的非阻塞赋值完成，再检查读数据。
    task automatic cycle;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        @(negedge clk);
        re = 1;
        cycle();
        check_data(0, "initial zero");

        // 同址读写采用 read-first：本拍返回旧字，下一拍才能读到新字。
        @(negedge clk);
        we = 1;
        wstrb = 4'b1111;
        wdata = 32'h11223344;
        cycle();
        check_data(0, "read-first old data");
        @(negedge clk);
        we = 0;
        cycle();
        check_data(32'h11223344, "read new data");

        // 仅改变地址不应组合改变输出，必须等读使能有效的上升沿。
        @(negedge clk);
        addr = 4;
        #1;
        check_data(32'h11223344, "synchronous read holds before edge");
        cycle();
        check_data(0, "next word initially zero");

        // re=0 时即使写入另一个地址，rdata 仍保持之前的读结果。
        @(negedge clk);
        re = 0;
        we = 1;
        addr = 1020;
        wdata = 32'hffffffff;
        cycle();
        check_data(0, "read enable holds output");
        @(negedge clk);
        re = 1;
        we = 0;
        cycle();
        check_data(32'hffffffff, "last word address");

        // 逐个字节写零，未选中的 lane 保持原值。
        for (lane = 0; lane < 4; lane = lane + 1) begin
            @(negedge clk);
            we = 1;
            wstrb = 4'b0001 << lane;
            wdata = 0;
            cycle();
            @(negedge clk);
            we = 0;
            cycle();
            check_data(32'hffffffff << ((lane + 1) * 8), "individual byte write");
        end

        // 非连续掩码 1010 只更新第 1、3 字节；0000 必须完全禁止写入。
        @(negedge clk);
        we = 1;
        wstrb = 4'b1010;
        wdata = 32'h12345678;
        cycle();
        @(negedge clk);
        we = 0;
        cycle();
        check_data(32'h12005600, "noncontiguous byte mask");
        @(negedge clk);
        we = 1;
        wstrb = 0;
        wdata = 32'hffffffff;
        cycle();
        @(negedge clk);
        we = 0;
        cycle();
        check_data(32'h12005600, "zero byte mask");
        $display("PASS: synchronous memory timing, read-first and byte enables");
        $finish;
    end
endmodule
