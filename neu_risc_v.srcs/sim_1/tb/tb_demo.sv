// ROM 演示：通过参数加载真实机器码，不从测试台直接写指令数组。
`timescale 1ns/1ps
module tb_demo;
    reg clk = 0;
    reg rst = 1;
    wire fault, result_valid;
    wire [31:0] result_data;

    always #5 clk = ~clk;

    rv32_soc #(.IMEM_FILE("demo.mem")) dut (
        .clk(clk),
        .rst(rst),
        .fault(fault),
        .result_valid(result_valid),
        .result_data(result_data)
    );

    initial begin
        // 复位后等待程序运行，核对错误标志、结果有效标志和饱和加法输出。
        repeat (2) @(negedge clk);
        rst = 0;
        repeat (25) @(negedge clk);
        if (fault !== 1'b0 || result_valid !== 1'b1 || result_data !== 32'h112234ff)
            $fatal(1, "demo failed: fault=%b valid=%b data=%08x",
                   fault, result_valid, result_data);
        $display("PASS: initialized ROM demo produced %08x", result_data);
        $finish;
    end
endmodule
