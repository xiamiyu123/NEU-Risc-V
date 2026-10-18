`timescale 1ns/1ps
// 仅在波形导出时作为额外仿真顶层，不改变自检测试台。
module wave_dump;
    string filename;
    initial begin
        if ($value$plusargs("wave=%s", filename)) begin
            $dumpfile(filename);
            $dumpvars(0);
        end
    end
endmodule
