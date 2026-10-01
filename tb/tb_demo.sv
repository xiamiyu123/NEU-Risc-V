module tb_demo;
    reg clk = 0;
    reg rst = 1;
    wire fault, result_valid;
    wire [31:0] result_data;

    always #5 clk = ~clk;

    rv32_soc #(.IMEM_FILE("program/demo.hex")) dut (
        .clk(clk), .rst(rst), .fault(fault),
        .result_valid(result_valid), .result_data(result_data)
    );

    initial begin
        repeat (2) @(negedge clk);
        rst = 0;
        repeat (25) @(negedge clk);
        if (fault || !result_valid || result_data !== 32'h112234ff)
            $fatal(1, "demo failed: fault=%b valid=%b data=%08x",
                   fault, result_valid, result_data);
        $display("PASS: initialized ROM demo produced %08x", result_data);
        $finish;
    end
endmodule
